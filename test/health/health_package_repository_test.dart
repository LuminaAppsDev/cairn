import 'package:cairn/src/health/health_gateway.dart';
import 'package:cairn/src/health/health_metric.dart';
import 'package:cairn/src/health/health_package_repository.dart';
import 'package:cairn/src/health/health_repository.dart';
import 'package:cairn/src/health/health_sample.dart';
import 'package:cairn/src/health/health_source.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

/// In-memory [HealthGateway] for testing the repository's orchestration without
/// the platform plugin.
class _FakeGateway implements HealthGateway {
  _FakeGateway({
    this.permissions = const {},
    this.samples = const {},
    this.failRead = const {},
  });

  final Map<HealthMetric, bool?> permissions;
  final Map<HealthMetric, List<HealthSample>> samples;
  final Set<HealthMetric> failRead;

  /// Whether the store answers as present; `false` mimics a device without
  /// Health Connect.
  bool available = true;

  /// When set, [configure] throws it — mimicking the plugin's
  /// `UnsupportedError` (an `Error`, not an `Exception`).
  Error? configureError;

  int configureCalls = 0;
  Set<HealthMetric>? requestedMetrics;

  @override
  Future<bool> isAvailable() async => available;

  @override
  Future<void> configure() async {
    configureCalls++;
    final error = configureError;
    if (error != null) throw error;
  }

  @override
  Future<void> requestReadAuthorization(Set<HealthMetric> metrics) async {
    requestedMetrics = metrics;
  }

  @override
  Future<bool?> hasReadPermission(HealthMetric metric) async =>
      permissions.containsKey(metric) ? permissions[metric] : true;

  @override
  Future<List<HealthSample>> readSamples({
    required HealthMetric metric,
    required DateTime start,
    required DateTime end,
  }) async {
    if (failRead.contains(metric)) {
      throw PlatformException(
        code: 'HEALTH_READ_FAILED',
        message: 'SecurityException: read denied',
      );
    }
    return samples[metric] ?? const [];
  }
}

void main() {
  final t = DateTime(2026, 6, 14, 8);

  HealthSource source(String name) => HealthSource(
    name: name,
    platform: HealthPlatform.googleHealthConnect,
    recordingMethod: RecordingMethodKind.automatic,
  );

  test('requestAuthorization returns only the granted metrics', () async {
    final gateway = _FakeGateway(
      permissions: {
        HealthMetric.heartRate: true,
        HealthMetric.steps: false,
        HealthMetric.weight: null, // iOS-style: unknown => assume granted
      },
    );
    final repo = HealthPackageRepository(gateway: gateway);

    final granted = await repo.requestAuthorization({
      HealthMetric.heartRate,
      HealthMetric.steps,
      HealthMetric.weight,
    });

    expect(granted, {HealthMetric.heartRate, HealthMetric.weight});
    expect(gateway.requestedMetrics, {
      HealthMetric.heartRate,
      HealthMetric.steps,
      HealthMetric.weight,
    });
  });

  test('configure runs once across authorization and reads', () async {
    final gateway = _FakeGateway();
    final repo = HealthPackageRepository(gateway: gateway);

    await repo.requestAuthorization({HealthMetric.heartRate});
    await repo.readSamples(metric: HealthMetric.heartRate, start: t, end: t);
    await repo.readSamples(metric: HealthMetric.steps, start: t, end: t);

    expect(gateway.configureCalls, 1);
  });

  test('readSamples deduplicates competing same-window readings', () async {
    ScalarSample hr(double value, String sourceName) => ScalarSample(
      metric: HealthMetric.heartRate,
      value: value,
      unit: 'count/min',
      start: t,
      end: t,
      source: source(sourceName),
    );
    final gateway = _FakeGateway(
      samples: {
        HealthMetric.heartRate: [hr(70, 'Pixel Phone'), hr(68, 'Galaxy Watch')],
      },
    );
    final repo = HealthPackageRepository(gateway: gateway);

    final samples = await repo.readSamples(
      metric: HealthMetric.heartRate,
      start: t,
      end: t,
    );

    expect(samples, hasLength(1));
    expect(samples.single.source.name, 'Galaxy Watch');
  });

  test('a failed read throws HealthReadException, never an empty list', () {
    // An empty list would read as "no data" and let ingest advance the anchor
    // past readings it never got.
    final gateway = _FakeGateway(failRead: {HealthMetric.heartRate});
    final repo = HealthPackageRepository(gateway: gateway);

    expect(
      repo.readSamples(metric: HealthMetric.heartRate, start: t, end: t),
      throwsA(
        isA<HealthReadException>()
            .having((e) => e.metric, 'metric', HealthMetric.heartRate)
            .having((e) => e.code, 'code', 'HEALTH_READ_FAILED')
            // Kept for the log line: it tells a rate limit from a denial.
            .having((e) => e.message, 'message', contains('SecurityException')),
      ),
    );
  });

  group('when the health store is not available', () {
    // A device without Health Connect. The plugin's own signal for this is an
    // UnsupportedError — an Error, which slips through `on Exception` — so the
    // repository checks first and raises a typed Exception instead.
    test('authorisation fails with the typed exception, not an Error', () {
      final gateway = _FakeGateway()..available = false;
      final repo = HealthPackageRepository(gateway: gateway);

      expect(
        repo.requestAuthorization({HealthMetric.steps}),
        throwsA(isA<HealthStoreUnavailableException>()),
      );
    });

    test('reading fails with the typed exception too', () {
      final gateway = _FakeGateway()..available = false;
      final repo = HealthPackageRepository(gateway: gateway);

      expect(
        repo.readSamples(metric: HealthMetric.steps, start: t, end: t),
        throwsA(isA<HealthStoreUnavailableException>()),
      );
    });

    test('the plugin is never configured or asked for permissions', () async {
      final gateway = _FakeGateway()..available = false;
      final repo = HealthPackageRepository(gateway: gateway);

      await expectLater(
        repo.requestAuthorization({HealthMetric.steps}),
        throwsA(isA<HealthStoreUnavailableException>()),
      );

      expect(gateway.configureCalls, 0);
      expect(gateway.requestedMetrics, isNull);
    });
  });

  test('a failed configure is retried, not cached forever', () async {
    // Installing Health Connect fixes the cause; the very next refresh has to
    // be able to succeed, so the failed future must not be remembered.
    final gateway = _FakeGateway()
      ..configureError = UnsupportedError('Health Connect unavailable');
    final repo = HealthPackageRepository(gateway: gateway);

    await expectLater(
      repo.requestAuthorization({HealthMetric.steps}),
      throwsUnsupportedError,
    );

    gateway.configureError = null;
    final granted = await repo.requestAuthorization({HealthMetric.steps});

    expect(granted, {HealthMetric.steps});
    expect(gateway.configureCalls, 2);
  });
}
