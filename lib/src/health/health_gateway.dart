import 'dart:io';

import 'package:cairn/src/health/health_metric.dart';
import 'package:cairn/src/health/health_sample.dart';
import 'package:cairn/src/health/health_source.dart';
import 'package:cairn/src/health/read_access_status.dart';
import 'package:health/health.dart';

/// A thin, mockable seam over the `health` package (DESIGN.md §13).
///
/// Speaks Cairn's domain types ([HealthMetric], [HealthSample]) so the
/// repository — and everything above it — never depends on the plugin. The
/// real implementation is [HealthPackageGateway]; tests provide a fake.
abstract interface class HealthGateway {
  /// Whether the platform health store can be talked to at all.
  ///
  /// Android only in practice: Health Connect may be missing or need a provider
  /// update, in which case every other call throws. Always `true` on iOS, where
  /// HealthKit is part of the OS.
  Future<bool> isAvailable();

  /// Initialises the underlying plugin; must run before any other operation.
  Future<void> configure();

  /// Shows the OS permission dialog for the read types backing [metrics] —
  /// and, on Android, for history reads while those are missing.
  Future<void> requestReadAuthorization(Set<HealthMetric> metrics);

  /// Whether READ access is granted for [metric]. Returns `null` on iOS, which
  /// hides read-authorisation status (DESIGN.md §4.2).
  Future<bool?> hasReadPermission(HealthMetric metric);

  /// Whether the store may be read from the background.
  Future<ReadAccessStatus> backgroundReadStatus();

  /// Shows the OS dialog for background reads (Android); a no-op on iOS.
  Future<void> requestBackgroundRead();

  /// Whether data older than 30 days before the first grant may be read.
  Future<ReadAccessStatus> historyReadStatus();

  /// Shows the OS dialog for history reads (Android); a no-op on iOS.
  Future<void> requestHistoryRead();

  /// Reads samples of [metric] whose start time is in `[start, end)` (Health
  /// Connect's own read filter; HealthKit via `.strictStartDate`), converted
  /// to Cairn's [HealthSample] model. Throws a `PlatformException` when the
  /// store fails the read (on Android only with the vendored plugin's patch —
  /// third_party/health/CAIRN_PATCHES.md); an empty list means no data.
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
  Future<bool> isAvailable() => _health.isHealthConnectAvailable();

  @override
  Future<void> configure() => _health.configure();

  @override
  Future<void> requestReadAuthorization(Set<HealthMetric> metrics) async {
    final types = metrics.expand(_authTypesFor).toList();
    await _health.requestAuthorization(types);
    // In the same flow, before any read: without history, Health Connect
    // silently clamps a read to 30 days before the first grant, and a re-grant
    // after every permission was revoked counts as a new first grant. A
    // catch-up over an older gap would then read nothing and move past it.
    if (await historyReadStatus() == ReadAccessStatus.missing) {
      await requestHistoryRead();
    }
  }

  @override
  Future<bool?> hasReadPermission(HealthMetric metric) =>
      _health.hasPermissions(_requiredTypesFor(metric));

  @override
  Future<ReadAccessStatus> backgroundReadStatus() async {
    if (_isIos) return ReadAccessStatus.notApplicable;
    if (!await _health.isHealthDataInBackgroundAvailable()) {
      return ReadAccessStatus.unavailable;
    }
    return await _health.isHealthDataInBackgroundAuthorized()
        ? ReadAccessStatus.granted
        : ReadAccessStatus.missing;
  }

  @override
  Future<void> requestBackgroundRead() async {
    if (_isIos) return;
    await _health.requestHealthDataInBackgroundAuthorization();
  }

  @override
  Future<ReadAccessStatus> historyReadStatus() async {
    if (_isIos) return ReadAccessStatus.notApplicable;
    if (!await _health.isHealthDataHistoryAvailable()) {
      return ReadAccessStatus.unavailable;
    }
    return await _health.isHealthDataHistoryAuthorized()
        ? ReadAccessStatus.granted
        : ReadAccessStatus.missing;
  }

  @override
  Future<void> requestHistoryRead() async {
    if (_isIos) return;
    await _health.requestHealthDataHistoryAuthorization();
  }

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
  // workout (distance, calories, steps); without them the WORKOUT read fails
  // with a SecurityException for those record types.
  List<HealthDataType> _authTypesFor(HealthMetric metric) => switch (metric) {
    HealthMetric.activity => const [
      ..._workoutReadTypes,
      HealthDataType.ACTIVE_ENERGY_BURNED,
    ],
    _ => _readTypesFor(metric),
  };

  // A metric counts as granted only if every type its read touches is: a
  // partial workout grant is then skipped (anchor kept) up front, rather than
  // read into a failure on every refresh. Android only — the extra types are
  // the Android reader's, and iOS can't answer for Android-only ones.
  List<HealthDataType> _requiredTypesFor(HealthMetric metric) =>
      metric == HealthMetric.activity && !_isIos
      ? _workoutReadTypes
      : _readTypesFor(metric);

  // Everything the plugin's Android reader reads for one workout.
  static const List<HealthDataType> _workoutReadTypes = [
    HealthDataType.WORKOUT,
    HealthDataType.DISTANCE_DELTA,
    HealthDataType.TOTAL_CALORIES_BURNED,
    HealthDataType.STEPS,
  ];

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
