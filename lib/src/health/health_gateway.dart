import 'dart:io';

import 'package:cairn/src/health/health_metric.dart';
import 'package:cairn/src/health/health_sample.dart';
import 'package:cairn/src/health/health_source.dart';
import 'package:health/health.dart';

/// A thin, mockable seam over the `health` package (DESIGN.md §13).
///
/// Speaks Cairn's domain types ([HealthMetric], [HealthSample]) so the
/// repository — and everything above it — never depends on the plugin. The
/// real implementation is [HealthPackageGateway]; tests provide a fake.
abstract interface class HealthGateway {
  /// Initialises the underlying plugin; must run before any other operation.
  Future<void> configure();

  /// Shows the OS permission dialog for the read types backing [metrics].
  Future<void> requestReadAuthorization(Set<HealthMetric> metrics);

  /// Whether READ access is granted for [metric]. Returns `null` on iOS, which
  /// hides read-authorisation status (DESIGN.md §4.2).
  Future<bool?> hasReadPermission(HealthMetric metric);

  /// Reads samples of [metric] recorded in `[start, end]`, converted to Cairn's
  /// [HealthSample] model. May throw if the OS denies the read.
  Future<List<HealthSample>> readSamples({
    required HealthMetric metric,
    required DateTime start,
    required DateTime end,
  });
}

/// [HealthGateway] backed by the real `health` package (Apple HealthKit /
/// Android Health Connect). Cairn only ever reads (DESIGN.md §2, §4.1).
final class HealthPackageGateway implements HealthGateway {
  /// Creates a gateway over [health] (defaults to the package singleton).
  /// [isIos] overrides platform detection for the sleep-type set.
  HealthPackageGateway({Health? health, bool? isIos})
    : _health = health ?? Health(),
      _isIos = isIos ?? Platform.isIOS;

  final Health _health;
  final bool _isIos;

  @override
  Future<void> configure() => _health.configure();

  @override
  Future<void> requestReadAuthorization(Set<HealthMetric> metrics) async {
    final types = metrics.expand(_authTypesFor).toList();
    await _health.requestAuthorization(types);
  }

  @override
  Future<bool?> hasReadPermission(HealthMetric metric) =>
      _health.hasPermissions(_readTypesFor(metric));

  @override
  Future<List<HealthSample>> readSamples({
    required HealthMetric metric,
    required DateTime start,
    required DateTime end,
  }) async {
    final points = await _health.getHealthDataFromTypes(
      types: _readTypesFor(metric),
      startTime: start,
      endTime: end,
    );
    return points
        .map((point) => _toSample(metric, point))
        .whereType<HealthSample>()
        .toList();
  }

  List<HealthDataType> _readTypesFor(HealthMetric metric) => switch (metric) {
    HealthMetric.heartRate => const [HealthDataType.HEART_RATE],
    HealthMetric.steps => const [HealthDataType.STEPS],
    HealthMetric.weight => const [HealthDataType.WEIGHT],
    HealthMetric.activity => const [HealthDataType.WORKOUT],
    HealthMetric.sleep => _isIos ? _iosSleepTypes : _androidSleepTypes,
  };

  // Authorisation must also cover the records the plugin reads alongside a
  // workout (distance + calories); without them the WORKOUT read fails with a
  // SecurityException for those record types.
  List<HealthDataType> _authTypesFor(HealthMetric metric) => switch (metric) {
    HealthMetric.activity => const [
      HealthDataType.WORKOUT,
      HealthDataType.DISTANCE_DELTA,
      HealthDataType.TOTAL_CALORIES_BURNED,
      HealthDataType.ACTIVE_ENERGY_BURNED,
    ],
    _ => _readTypesFor(metric),
  };

  HealthSample? _toSample(HealthMetric metric, HealthDataPoint point) {
    final source = HealthSource(
      name: point.sourceName,
      platform: point.sourcePlatform == HealthPlatformType.appleHealth
          ? HealthPlatform.appleHealth
          : HealthPlatform.googleHealthConnect,
      recordingMethod: _recordingKind(point.recordingMethod),
      deviceId: point.sourceDeviceId.isEmpty ? null : point.sourceDeviceId,
    );
    return switch (metric) {
      HealthMetric.heartRate ||
      HealthMetric.steps ||
      HealthMetric.weight => _scalar(metric, point, source),
      HealthMetric.activity => _workout(point, source),
      HealthMetric.sleep => _sleep(point, source),
    };
  }

  ScalarSample? _scalar(
    HealthMetric metric,
    HealthDataPoint point,
    HealthSource source,
  ) {
    final value = point.value;
    if (value is! NumericHealthValue) return null;
    return ScalarSample(
      metric: metric,
      value: value.numericValue.toDouble(),
      unit: point.unit.name,
      start: point.dateFrom,
      end: point.dateTo,
      source: source,
    );
  }

  WorkoutSample? _workout(HealthDataPoint point, HealthSource source) {
    final value = point.value;
    if (value is! WorkoutHealthValue) return null;
    return WorkoutSample(
      start: point.dateFrom,
      end: point.dateTo,
      source: source,
      activityName: value.workoutActivityType.name,
      totalDistanceMeters: value.totalDistance?.toDouble(),
      totalEnergyKcal: value.totalEnergyBurned?.toDouble(),
      totalSteps: value.totalSteps,
    );
  }

  SleepSegmentSample? _sleep(HealthDataPoint point, HealthSource source) {
    final stage = _sleepStage(point.type);
    if (stage == null) return null;
    return SleepSegmentSample(
      start: point.dateFrom,
      end: point.dateTo,
      source: source,
      stage: stage,
    );
  }

  RecordingMethodKind _recordingKind(RecordingMethod method) =>
      switch (method) {
        RecordingMethod.automatic => RecordingMethodKind.automatic,
        RecordingMethod.manual => RecordingMethodKind.manual,
        RecordingMethod.active => RecordingMethodKind.active,
        RecordingMethod.unknown => RecordingMethodKind.unknown,
      };

  SleepStage? _sleepStage(HealthDataType type) => switch (type) {
    HealthDataType.SLEEP_DEEP => SleepStage.deep,
    HealthDataType.SLEEP_LIGHT => SleepStage.light,
    HealthDataType.SLEEP_REM => SleepStage.rem,
    HealthDataType.SLEEP_ASLEEP => SleepStage.asleepUnspecified,
    HealthDataType.SLEEP_AWAKE => SleepStage.awake,
    HealthDataType.SLEEP_AWAKE_IN_BED => SleepStage.awake,
    HealthDataType.SLEEP_OUT_OF_BED => SleepStage.outOfBed,
    HealthDataType.SLEEP_IN_BED => SleepStage.inBed,
    // The whole-session record (Android), used when a sleep has no per-stage
    // breakdown (e.g. a manual entry). A distinct stage so it is not conflated
    // with SLEEP_ASLEEP sub-segments; the aggregator unions asleep intervals so
    // a session never double-counts against its stages.
    HealthDataType.SLEEP_SESSION => SleepStage.session,
    _ => null,
  };

  static const List<HealthDataType> _iosSleepTypes = [
    HealthDataType.SLEEP_ASLEEP,
    HealthDataType.SLEEP_AWAKE,
    HealthDataType.SLEEP_DEEP,
    HealthDataType.SLEEP_LIGHT,
    HealthDataType.SLEEP_REM,
    HealthDataType.SLEEP_IN_BED,
  ];

  static const List<HealthDataType> _androidSleepTypes = [
    HealthDataType.SLEEP_SESSION,
    HealthDataType.SLEEP_ASLEEP,
    HealthDataType.SLEEP_AWAKE,
    HealthDataType.SLEEP_AWAKE_IN_BED,
    HealthDataType.SLEEP_DEEP,
    HealthDataType.SLEEP_LIGHT,
    HealthDataType.SLEEP_OUT_OF_BED,
    HealthDataType.SLEEP_REM,
  ];
}
