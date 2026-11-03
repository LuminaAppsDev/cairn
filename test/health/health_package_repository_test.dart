import 'dart:async';

import 'package:cairn/src/health/health_gateway.dart';
import 'package:cairn/src/health/health_metric.dart';
import 'package:cairn/src/health/health_package_repository.dart';
import 'package:cairn/src/health/health_repository.dart';
import 'package:cairn/src/health/health_sample.dart';
import 'package:cairn/src/health/health_source.dart';
import 'package:cairn/src/health/read_access_status.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

/// In-memory [HealthGateway] for testing the repository's orchestration without
/// the platform plugin.
class _FakeGateway implements HealthGateway {
  new({
    this.permissions = const {},
    this.samples = const {},
    this.failRead = const {},
    this.readError,
  });

  final Map<HealthMetric, bool?> permissions;
  final Map<HealthMetric, List<HealthSample>> samples;
  final Set<HealthMetric> failRead;

  /// What a [failRead] read throws, if not the default denial.
  final PlatformException? readError;

  /// Whether the store answers as present; `false` mimics a device without
  /// Health Connect.
  bool available = true;

  /// When set, [configure] throws it — mimicking the plugin's
  /// `UnsupportedError` (an `Error`, not an `Exception`).
  Error? configureError;

  int configureCalls = 0;
  Set<HealthMetric>? requestedMetrics;

  /// The background-read status; granting it is what [requestBackgroundRead]
  /// does unless [background] stays put (declined).
  ReadAccessStatus background = ReadAccessStatus.missing;
  bool grantsBackground = true;

  /// The history-read status; [requestHistoryRead] grants it.
  ReadAccessStatus history = ReadAccessStatus.missing;

  /// When set, the read-permission sheet stays open until it completes.
  Completer<void>? readSheet;

  /// Sheets in the order they opened and closed, to check they never overlap.
  final List<String> sheetEvents = [];

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
    sheetEvents.add('reads open');
    requestedMetrics = metrics;
    await readSheet?.future;
    sheetEvents.add('reads closed');
  }

  @override
  Future<ReadAccessStatus> backgroundReadStatus() async => background;

  @override
  Future<void> requestBackgroundRead() async {
    sheetEvents
      ..add('background open')
      ..add('background closed');
    if (grantsBackground) background = ReadAccessStatus.granted;
  }

  @override
  Future<ReadAccessStatus> historyReadStatus() async => history;

  @override
  Future<void> requestHistoryRead() async {
    sheetEvents
      ..add('history open')
      ..add('history closed');
    history = ReadAccessStatus.granted;
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
      throw readError ??
          PlatformException(
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

  group('a failed read is classified', () {
    PlatformException failed(String? exception, Object? platformError) =>
        PlatformException(
          code: 'HEALTH_READ_FAILED',
          details: {'exception': exception, 'platformError': platformError},
        );

    final cases = <String, (PlatformException, HealthReadFailure)>{
      'a rate limit (platform code 7)': (
        failed('IllegalStateException', 7),
        HealthReadFailure.rateLimited,
      ),
      'a sync in progress (platform code 8)': (
        failed('IllegalStateException', 8),
        HealthReadFailure.transient,
      ),
      'an invalid request (platform code 3)': (
        failed('IllegalArgumentException', 3),
        HealthReadFailure.unexpected,
      ),
      'an unsupported operation (platform code 9)': (
        failed('IllegalStateException', 9),
        HealthReadFailure.unexpected,
      ),
      'an internal error (platform code 2)': (
        failed('IllegalStateException', 2),
        HealthReadFailure.transient,
      ),
      'a binder failure without a code': (
        failed('RemoteException', null),
        HealthReadFailure.transient,
      ),
      'a dead binder without a code': (
        failed('DeadObjectException', null),
        HealthReadFailure.transient,
      ),
      'an I/O failure without a code': (
        failed('IOException', null),
        HealthReadFailure.transient,
      ),
      'a withdrawn permission without a code': (
        failed('SecurityException', null),
        HealthReadFailure.transient,
      ),
      'a converter fault': (
        failed('NullPointerException', null),
        HealthReadFailure.unexpected,
      ),
      'a read without details': (
        PlatformException(code: 'HEALTH_READ_FAILED'),
        HealthReadFailure.unexpected,
      ),
      'a read with malformed details': (
        PlatformException(code: 'HEALTH_READ_FAILED', details: 'oops'),
        HealthReadFailure.unexpected,
      ),
      'a revocation mid-run (patch 2)': (
        PlatformException(code: 'HEALTH_READ_NOT_AUTHORIZED'),
        HealthReadFailure.transient,
      ),
      'a HealthKit error (iOS)': (
        PlatformException(code: 'HEALTH_ERROR'),
        HealthReadFailure.transient,
      ),
      'a code the read path never sends': (
        PlatformException(code: 'INVALID_TYPE'),
        HealthReadFailure.unexpected,
      ),
    };

    for (final MapEntry(key: name, value: (error, expected)) in cases.entries) {
      test('$name as ${expected.name}', () {
        final repo = HealthPackageRepository(
          gateway: _FakeGateway(
            failRead: {HealthMetric.steps},
            readError: error,
          ),
        );

        expect(
          repo.readSamples(metric: HealthMetric.steps, start: t, end: t),
          throwsA(
            isA<HealthReadException>().having(
              (e) => e.failure,
              'failure',
              expected,
            ),
          ),
        );
      });
    }
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

  group('history reads', () {
    test('report the gateway status once the store is up', () async {
      final gateway = _FakeGateway()..history = ReadAccessStatus.unavailable;
      final repo = HealthPackageRepository(gateway: gateway);

      expect(await repo.historyReadStatus(), ReadAccessStatus.unavailable);
      expect(gateway.configureCalls, 1);
    });

    test('a request returns the status it left behind', () async {
      final repo = HealthPackageRepository(gateway: _FakeGateway());

      expect(await repo.requestHistoryRead(), ReadAccessStatus.granted);
    });

    test('without a health store, fail with the typed exception', () {
      final repo = HealthPackageRepository(
        gateway: _FakeGateway()..available = false,
      );

      expect(
        repo.historyReadStatus(),
        throwsA(isA<HealthStoreUnavailableException>()),
      );
    });
  });

  group('background reads', () {
    test('report the gateway status once the store is up', () async {
      final gateway = _FakeGateway()..background = ReadAccessStatus.unavailable;
      final repo = HealthPackageRepository(gateway: gateway);

      expect(await repo.backgroundReadStatus(), ReadAccessStatus.unavailable);
      expect(gateway.configureCalls, 1);
    });

    test('a request returns the status it left behind', () async {
      final repo = HealthPackageRepository(gateway: _FakeGateway());

      expect(await repo.requestBackgroundRead(), ReadAccessStatus.granted);
    });

    test('without a health store, fail with the typed exception', () {
      final repo = HealthPackageRepository(
        gateway: _FakeGateway()..available = false,
      );

      expect(
        repo.backgroundReadStatus(),
        throwsA(isA<HealthStoreUnavailableException>()),
      );
    });

    test('a second permission sheet waits for the first', () async {
      // The plugin holds one pending result for any sheet; overlapping
      // launches (Settings' Allow during a refresh's read request) would
      // orphan the first future.
      final gateway = _FakeGateway()..readSheet = Completer<void>();
      final repo = HealthPackageRepository(gateway: gateway);

      final reads = repo.requestAuthorization({HealthMetric.steps});
      final background = repo.requestBackgroundRead();
      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(gateway.sheetEvents, ['reads open']);

      gateway.readSheet!.complete();
      await Future.wait([reads, background]);
      expect(gateway.sheetEvents, [
        'reads open',
        'reads closed',
        'background open',
        'background closed',
      ]);
    });
  });
}
