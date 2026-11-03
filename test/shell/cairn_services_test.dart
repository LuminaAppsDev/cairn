import 'dart:io';

import 'package:cairn/src/health/health_metric.dart';
import 'package:cairn/src/health/health_repository.dart';
import 'package:cairn/src/health/health_sample.dart';
import 'package:cairn/src/profile/profile.dart';
import 'package:cairn/src/profile/profile_store.dart';
import 'package:cairn/src/profile/profile_sync.dart';
import 'package:cairn/src/query/health_query_service.dart';
import 'package:cairn/src/shell/cairn_services.dart';
import 'package:cairn/src/storage/jsonl_omh_file_store.dart';
import 'package:cairn/src/sync/nextcloud_auth.dart';
import 'package:cairn/src/sync/nextcloud_credentials.dart';
import 'package:cairn/src/sync/nextcloud_sync_coordinator.dart';
import 'package:cairn/src/sync/nextcloud_sync_target.dart';
import 'package:cairn/src/sync/secure_token_store.dart';
import 'package:cairn/src/sync/sync_journal.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;

/// A health store that fails the way a real device does.
class _FailingRepository implements HealthRepository {
  _FailingRepository(this.fail);

  /// Raises the failure under test. A callback rather than a stored object so
  /// the `throw` happens at the caller, carrying a real stack trace — the same
  /// thing the plugin hands us on a device.
  final Never Function() fail;

  @override
  Future<bool> isAvailable() async => false;

  @override
  Future<Set<HealthMetric>> requestAuthorization(
    Set<HealthMetric> metrics,
  ) async => fail();

  @override
  Future<List<HealthSample>> readSamples({
    required HealthMetric metric,
    required DateTime start,
    required DateTime end,
  }) async => fail();
}

/// Grants everything and reads nothing, except [failing], whose read fails.
class _PartlyFailingRepository implements HealthRepository {
  _PartlyFailingRepository(this.failing);

  final HealthMetric failing;

  @override
  Future<bool> isAvailable() async => true;

  @override
  Future<Set<HealthMetric>> requestAuthorization(
    Set<HealthMetric> metrics,
  ) async => metrics;

  @override
  Future<List<HealthSample>> readSamples({
    required HealthMetric metric,
    required DateTime start,
    required DateTime end,
  }) async {
    if (metric == failing) throw HealthReadException(metric);
    return const [];
  }
}

class _StubAuth implements NextcloudAuth {
  @override
  Future<LoginFlowSession> begin(Uri host) async =>
      LoginFlowSession(loginUrl: host, pollToken: 't', pollEndpoint: host);

  @override
  Future<NextcloudCredentials?> poll(LoginFlowSession session) async => null;
}

/// Always connected, so a refresh goes on to push.
class _ConnectedTokenStore implements SecureTokenStore {
  @override
  Future<void> writeCredentials(NextcloudCredentials credentials) async {}

  @override
  Future<NextcloudCredentials?> readCredentials() async => NextcloudCredentials(
    server: Uri.parse('https://cloud.example.com'),
    loginName: 'alice',
    appPassword: 'pw',
  );

  @override
  Future<void> deleteCredentials() async {}
}

/// Records what a push uploads.
class _RecordingTarget implements NextcloudSyncTarget {
  final List<String> puts = [];

  @override
  Future<String?> putFile({
    required String remotePath,
    required Uint8List bytes,
  }) async {
    puts.add(remotePath);
    return 'etag';
  }

  @override
  Future<List<RemoteResource>> list(String remoteDir) async => const [];

  @override
  Future<Uint8List> getFile(String remotePath, {int? maxBytes}) async =>
      throw NextcloudNotFoundException(remotePath);
}

/// Never connected, so a refresh stops after the read step.
class _EmptyTokenStore implements SecureTokenStore {
  @override
  Future<void> writeCredentials(NextcloudCredentials credentials) async {}

  @override
  Future<NextcloudCredentials?> readCredentials() async => null;

  @override
  Future<void> deleteCredentials() async {}
}

void main() {
  late Directory dir;
  late List<FlutterErrorDetails> reported;
  FlutterExceptionHandler? previousOnError;

  setUp(() {
    dir = Directory.systemTemp.createTempSync('cairn_services_test');
    // Capture what the app hands to Flutter's error machinery, instead of
    // letting it dump to the console.
    reported = [];
    previousOnError = FlutterError.onError;
    FlutterError.onError = reported.add;
  });

  tearDown(() {
    FlutterError.onError = previousOnError;
    dir.deleteSync(recursive: true);
  });

  CairnServices servicesOver(
    HealthRepository repository, {
    NextcloudSyncTarget? target,
  }) {
    final root = Directory(p.join(dir.path, 'Cairn'))..createSync();
    final store = JsonlOmhFileStore(root: root);
    final profileStore = JsonProfileStore(root: root);
    return CairnServices(
      client: http.Client(),
      store: store,
      profileStore: profileStore,
      profile: ValueNotifier(Profile.empty()),
      query: OmhHealthQueryService(store: store),
      coordinator: NextcloudSyncCoordinator(
        auth: _StubAuth(),
        tokenStore: target == null
            ? _EmptyTokenStore()
            : _ConnectedTokenStore(),
        targetFactory: target == null ? null : (_) => target,
        localRoot: root,
        journalStore: JsonSyncJournalStore(
          file: File(p.join(dir.path, 'journal.json')),
        ),
      ),
      profileSync: ProfileSyncService(
        store: profileStore,
        download: () async => null,
      ),
      repository: repository,
    );
  }

  CairnServices servicesWith(Never Function() readFailure) =>
      servicesOver(_FailingRepository(readFailure));

  // The regression this file exists for: on a device without Health Connect the
  // plugin throws an UnsupportedError, which is an Error and not an Exception.
  // When that escaped, `await refresh()` threw in every caller, so the Home
  // spinner turned forever and Settings stayed on "Syncing…" with its buttons
  // disabled until the process was restarted.
  test('a missing health store resolves, and says so', () async {
    final services = servicesWith(
      () => throw const HealthStoreUnavailableException(),
    );
    addTearDown(services.dispose);

    final result = await services.refresh();

    expect(result.status, RefreshStatus.healthUnavailable);
  });

  test('a raw Error from the plugin resolves as a read failure', () async {
    final services = servicesWith(
      () => throw UnsupportedError('no Health Connect'),
    );
    addTearDown(services.dispose);

    final result = await services.refresh();

    expect(result.status, RefreshStatus.readFailed);
  });

  // A failed metric read used to come back as an empty list, so ingest moved
  // its anchor past data it never read. Now it holds that metric, lets the
  // rest through, and still tells the user.
  test('a failed metric read holds it, and still saves the rest', () async {
    final target = _RecordingTarget();
    final services = servicesOver(
      _PartlyFailingRepository(HealthMetric.heartRate),
      target: target,
    );
    addTearDown(services.dispose);

    final result = await services.refresh();

    expect(result.status, RefreshStatus.readFailed);
    expect(services.dataRevision.value, 1);
    // The upload still ran, and its report survives for the conflict notice.
    expect(target.puts, isNotEmpty);
    expect(result.report, isNotNull);
    // Heart rate stays pinned at its first-run start; weight moved to now.
    final store = services.store;
    final aMonthAgo = DateTime.now().subtract(const Duration(days: 29));
    final held = await store.lastSyncAnchor(HealthMetric.heartRate);
    expect(held!.isBefore(aMonthAgo), isTrue);
    final advanced = await store.lastSyncAnchor(HealthMetric.weight);
    expect(advanced!.isAfter(aMonthAgo), isTrue);
    // An anticipated failure, not a bug.
    expect(reported, isEmpty);
  });

  test('a failed read leaves the data revision untouched', () async {
    final services = servicesWith(
      () => throw UnsupportedError('no Health Connect'),
    );
    addTearDown(services.dispose);

    await services.refresh();

    expect(services.dataRevision.value, 0);
  });

  // A broad `on Object` catch keeps the UI alive, but a Dart Error means a bug,
  // and a bug that only ever reached debugPrint is a bug nobody fixes.
  test('a raw Error is reported to Flutter, not just swallowed', () async {
    final services = servicesWith(
      () => throw UnsupportedError('no Health Connect'),
    );
    addTearDown(services.dispose);

    await services.refresh();

    expect(reported, hasLength(1));
    expect(reported.single.exception, isA<UnsupportedError>());
  });

  test('an expected Exception is not reported as a bug', () async {
    final services = servicesWith(
      () => throw const HealthStoreUnavailableException(),
    );
    addTearDown(services.dispose);

    await services.refresh();

    expect(reported, isEmpty);
  });

  test('a coalesced concurrent refresh resolves for both callers', () async {
    final services = servicesWith(
      () => throw const HealthStoreUnavailableException(),
    );
    addTearDown(services.dispose);

    final results = await Future.wait([services.refresh(), services.refresh()]);

    expect(
      results.map((r) => r.status),
      everyElement(RefreshStatus.healthUnavailable),
    );
  });
}
