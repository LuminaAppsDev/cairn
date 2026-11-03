import 'package:cairn/src/health/health_gateway.dart';
import 'package:cairn/src/health/health_metric.dart';
import 'package:cairn/src/health/read_access_status.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:health/health.dart';

/// Records which types the gateway asks the plugin about.
class _RecordingHealth extends Fake implements Health {
  _RecordingHealth({
    this.backgroundAvailable = true,
    this.backgroundGranted,
    this.historyAvailable = true,
    this.historyGranted = false,
  });

  final List<List<HealthDataType>> asked = [];
  List<HealthDataType> requested = const [];

  final bool backgroundAvailable;
  final bool? backgroundGranted;
  int backgroundRequests = 0;

  final bool historyAvailable;
  final bool historyGranted;

  /// Plugin calls in order — the read sheet, then the history sheet.
  final List<String> sheets = [];

  @override
  Future<bool> isHealthDataInBackgroundAvailable() async => backgroundAvailable;

  @override
  Future<bool> isHealthDataInBackgroundAuthorized() async =>
      backgroundGranted ?? false;

  @override
  Future<bool> requestHealthDataInBackgroundAuthorization() async {
    backgroundRequests++;
    return true;
  }

  @override
  Future<bool> isHealthDataHistoryAvailable() async => historyAvailable;

  @override
  Future<bool> isHealthDataHistoryAuthorized() async => historyGranted;

  @override
  Future<bool> requestHealthDataHistoryAuthorization() async {
    sheets.add('history');
    return true;
  }

  @override
  Future<bool?> hasPermissions(
    List<HealthDataType> types, {
    List<HealthDataAccess>? permissions,
  }) async {
    asked.add(types);
    return true;
  }

  @override
  Future<bool> requestAuthorization(
    List<HealthDataType> types, {
    List<HealthDataAccess>? permissions,
  }) async {
    requested = types;
    sheets.add('reads');
    return true;
  }
}

void main() {
  // The Android reader also reads the distance, calories and steps records
  // inside each workout; without any of them the whole read fails. So a
  // partial grant must count as "not granted" up front (skipped, anchor
  // kept), not be read into a failure on every refresh.
  const workoutReadTypes = [
    HealthDataType.WORKOUT,
    HealthDataType.DISTANCE_DELTA,
    HealthDataType.TOTAL_CALORIES_BURNED,
    HealthDataType.STEPS,
  ];

  test(
    'on Android, activity needs every type the workout read touches',
    () async {
      final health = _RecordingHealth();
      await HealthPackageGateway(
        health: health,
        isIos: false,
      ).hasReadPermission(HealthMetric.activity);

      expect(health.asked.single, containsAll(workoutReadTypes));
    },
  );

  test('on iOS, activity asks only about workouts', () async {
    // iOS can't answer for Android-only types such as DISTANCE_DELTA.
    final health = _RecordingHealth();
    await HealthPackageGateway(
      health: health,
      isIos: true,
    ).hasReadPermission(HealthMetric.activity);

    expect(health.asked.single, [HealthDataType.WORKOUT]);
  });

  test('authorising activity requests everything its read needs', () async {
    final health = _RecordingHealth();
    await HealthPackageGateway(
      health: health,
      isIos: false,
    ).requestReadAuthorization({HealthMetric.activity});

    expect(health.requested, containsAll(workoutReadTypes));
  });

  group('background reads', () {
    Future<ReadAccessStatus> statusOn(
      _RecordingHealth health, {
      bool isIos = false,
    }) => HealthPackageGateway(
      health: health,
      isIos: isIos,
    ).backgroundReadStatus();

    test('Android maps the plugin onto the status', () async {
      expect(
        await statusOn(_RecordingHealth(backgroundAvailable: false)),
        ReadAccessStatus.unavailable,
      );
      expect(
        await statusOn(_RecordingHealth(backgroundGranted: false)),
        ReadAccessStatus.missing,
      );
      expect(
        await statusOn(_RecordingHealth(backgroundGranted: true)),
        ReadAccessStatus.granted,
      );
    });

    test('iOS has no such permission to ask for', () async {
      final health = _RecordingHealth();
      final gateway = HealthPackageGateway(health: health, isIos: true);

      expect(
        await gateway.backgroundReadStatus(),
        ReadAccessStatus.notApplicable,
      );
      await gateway.requestBackgroundRead();
      expect(health.backgroundRequests, 0);
    });

    test('Android asks the plugin for it', () async {
      final health = _RecordingHealth();
      await HealthPackageGateway(
        health: health,
        isIos: false,
      ).requestBackgroundRead();

      expect(health.backgroundRequests, 1);
    });
  });

  group('history reads', () {
    Future<ReadAccessStatus> statusOn(_RecordingHealth health) =>
        HealthPackageGateway(health: health, isIos: false).historyReadStatus();

    Future<List<String>> sheetsForReadRequest(
      _RecordingHealth health, {
      bool isIos = false,
    }) async {
      await HealthPackageGateway(
        health: health,
        isIos: isIos,
      ).requestReadAuthorization({HealthMetric.heartRate});
      return health.sheets;
    }

    test('Android maps the plugin onto the status', () async {
      expect(
        await statusOn(_RecordingHealth(historyAvailable: false)),
        ReadAccessStatus.unavailable,
      );
      expect(await statusOn(_RecordingHealth()), ReadAccessStatus.missing);
      expect(
        await statusOn(_RecordingHealth(historyGranted: true)),
        ReadAccessStatus.granted,
      );
    });

    test('the read request asks for it too, before any read', () async {
      // A re-grant after a full revoke restarts Health Connect's 30-day
      // window; history must be in place before the catch-up reads.
      expect(await sheetsForReadRequest(_RecordingHealth()), [
        'reads',
        'history',
      ]);
    });

    test('but not once granted, nor where it is unavailable', () async {
      expect(
        await sheetsForReadRequest(_RecordingHealth(historyGranted: true)),
        ['reads'],
      );
      expect(
        await sheetsForReadRequest(_RecordingHealth(historyAvailable: false)),
        ['reads'],
      );
    });

    test('iOS has no such permission to ask for', () async {
      final health = _RecordingHealth();
      final gateway = HealthPackageGateway(health: health, isIos: true);

      expect(
        await gateway.historyReadStatus(),
        ReadAccessStatus.notApplicable,
      );
      expect(await sheetsForReadRequest(health, isIos: true), ['reads']);
    });
  });
}
