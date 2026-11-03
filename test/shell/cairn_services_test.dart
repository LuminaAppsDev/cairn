import 'dart:async';
import 'dart:io';

import 'package:cairn/src/health/background_read_prompt.dart';
import 'package:cairn/src/health/health_metric.dart';
import 'package:cairn/src/health/health_repository.dart';
import 'package:cairn/src/health/health_sample.dart';
import 'package:cairn/src/health/read_access_status.dart';
import 'package:cairn/src/profile/profile.dart';
import 'package:cairn/src/profile/profile_store.dart';
import 'package:cairn/src/profile/profile_sync.dart';
import 'package:cairn/src/query/health_query_service.dart';
import 'package:cairn/src/shell/cairn_services.dart';
import 'package:cairn/src/shell/cross_isolate_lock.dart';
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
  new(this.fail);

  /// Raises the failure under test. A callback rather than a stored object so
  /// the `throw` happens at the caller, carrying a real stack trace — the same
  /// thing the plugin hands us on a device.
  final Never Function() fail;

  @override
  Future<bool> isAvailable() async => false;

  @override
  Future<ReadAccessStatus> backgroundReadStatus() async => fail();

  @override
  Future<ReadAccessStatus> requestBackgroundRead() async => fail();

  @override
  Future<ReadAccessStatus> historyReadStatus() async => fail();

  @override
  Future<ReadAccessStatus> requestHistoryRead() async => fail();

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
  new(
    this.failing, {
    this.background = ReadAccessStatus.notApplicable,
    this.grantsReads = true,
    this.failsWithBug = false,
    this.bugInEveryRead = false,
    this.readFailure = HealthReadFailure.transient,
    this.failsEveryRead = false,
  });

  /// The metric whose read fails (`null`: none).
  final HealthMetric? failing;

  /// The background-read status reported; asking leaves it as is (declined).
  ReadAccessStatus background;

  /// Whether any read permission is granted.
  final bool grantsReads;

  /// Whether [failing]'s read fails with a bug (a `StateError`) rather than a
  /// failed read.
  final bool failsWithBug;

  /// Whether every read fails with the same bug — a shared fault.
  final bool bugInEveryRead;

  /// How [failing]'s failed read is classified.
  final HealthReadFailure readFailure;

  /// Whether every read fails like [failing]'s — a shared plugin fault.
  final bool failsEveryRead;

  final List<HealthMetric> reads = [];
  int backgroundRequests = 0;

  /// How many reads had happened when background reads were requested.
  int? readsBeforeAsk;

  @override
  Future<bool> isAvailable() async => true;

  @override
  Future<Set<HealthMetric>> requestAuthorization(
    Set<HealthMetric> metrics,
  ) async => grantsReads ? metrics : const {};

  @override
  Future<List<HealthSample>> readSamples({
    required HealthMetric metric,
    required DateTime start,
    required DateTime end,
  }) async {
    reads.add(metric);
    if (bugInEveryRead) throw StateError('shared bug');
    if (metric == failing || failsEveryRead) {
      if (failsWithBug) throw StateError('bug while reading ${metric.name}');
      throw HealthReadException(metric, failure: readFailure);
    }
    return const [];
  }

  @override
  Future<ReadAccessStatus> backgroundReadStatus() async {
    if (failsBackgroundCheck) throw Exception('binder failure');
    return background;
  }

  @override
  Future<ReadAccessStatus> requestBackgroundRead() async {
    backgroundRequests++;
    readsBeforeAsk ??= reads.length;
    return background;
  }

  /// The history-read status; [requestHistoryRead] grants it.
  ReadAccessStatus history = ReadAccessStatus.notApplicable;

  /// Whether the background-read status check fails.
  bool failsBackgroundCheck = false;

  @override
  Future<ReadAccessStatus> historyReadStatus() async => history;

  @override
  Future<ReadAccessStatus> requestHistoryRead() async =>
      history = ReadAccessStatus.granted;
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
  new({this.fails = false});

  /// Whether every upload fails, as with the server unreachable.
  final bool fails;

  final List<String> puts = [];

  @override
  Future<String?> putFile({
    required String remotePath,
    required Uint8List bytes,
  }) async {
    if (fails) {
      throw const NextcloudSyncException(
        'unreachable',
        kind: SyncErrorKind.network,
        retryable: true,
      );
    }
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
    CrossIsolateLock? refreshLock,
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
      backgroundReadPrompt: BackgroundReadPrompt(
        marker: File(p.join(dir.path, 'support', 'background_read_asked')),
      ),
      refreshLock: refreshLock,
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
    expect(result.failedMetrics, {HealthMetric.heartRate});
  });

  test('a plugin fault in one metric is reported as a bug', () async {
    // It fails the same way every run until a fix ships.
    final services = servicesOver(
      _PartlyFailingRepository(
        HealthMetric.heartRate,
        readFailure: HealthReadFailure.unexpected,
      ),
    );
    addTearDown(services.dispose);

    final result = await services.refresh();

    expect(result.status, RefreshStatus.readFailed);
    expect(reported.single.exception, isA<HealthReadException>());
    expect(result.failedMetrics, {HealthMetric.heartRate});
  });

  test('a plugin fault failing every metric is reported once', () async {
    final services = servicesOver(
      _PartlyFailingRepository(
        null,
        failsEveryRead: true,
        readFailure: HealthReadFailure.unexpected,
      ),
    );
    addTearDown(services.dispose);

    final result = await services.refresh();

    expect(reported, hasLength(1));
    expect(result.failedMetrics, HealthMetric.values.toSet());
  });

  test('a rate limit names the metrics it left unread', () async {
    final repo = _PartlyFailingRepository(
      HealthMetric.values.first,
      readFailure: HealthReadFailure.rateLimited,
    );
    final services = servicesOver(repo);
    addTearDown(services.dispose);

    final result = await services.refresh();

    expect(result.status, RefreshStatus.readFailed);
    expect(repo.reads, [HealthMetric.values.first]);
    expect(result.failedMetrics, HealthMetric.values.toSet());
    expect(reported, isEmpty);
  });

  test('a bug in one metric is reported, and the rest still run', () async {
    final repo = _PartlyFailingRepository(
      HealthMetric.heartRate,
      failsWithBug: true,
    );
    final services = servicesOver(repo);
    addTearDown(services.dispose);

    final result = await services.refresh();

    expect(result.status, RefreshStatus.readFailed);
    expect(reported.single.exception, isA<StateError>());
    expect(services.dataRevision.value, 1);
    final weight = await services.store.lastSyncAnchor(HealthMetric.weight);
    expect(
      weight!.isAfter(DateTime.now().subtract(const Duration(days: 1))),
      isTrue,
    );
  });

  test('the upload still runs when the whole read fails', () async {
    final target = _RecordingTarget();
    final services = servicesOver(
      _FailingRepository(() => throw UnsupportedError('no Health Connect')),
      target: target,
    );
    addTearDown(services.dispose);
    // Something from an earlier run waiting to go up.
    await services.store.setSyncAnchor(HealthMetric.weight, DateTime(2026));

    final result = await services.refresh();

    expect(result.status, RefreshStatus.readFailed);
    expect(target.puts, isNotEmpty);
    expect(result.failedMetrics, isEmpty); // nothing to name
  });

  test('no upload while Health Connect is missing', () async {
    // Nothing new to send, and the user has to act on the device first.
    final target = _RecordingTarget();
    final services = servicesOver(
      _FailingRepository(() => throw const HealthStoreUnavailableException()),
      target: target,
    );
    addTearDown(services.dispose);
    await services.store.setSyncAnchor(HealthMetric.weight, DateTime(2026));

    final result = await services.refresh();

    expect(result.status, RefreshStatus.healthUnavailable);
    expect(target.puts, isEmpty);
  });

  test('a read that saved nothing outranks a failed upload', () async {
    // The upload's message would claim "saved locally" — untrue here.
    final services = servicesOver(
      _FailingRepository(() => throw UnsupportedError('no Health Connect')),
      target: _RecordingTarget(fails: true),
    );
    addTearDown(services.dispose);
    await services.store.setSyncAnchor(HealthMetric.weight, DateTime(2026));

    final result = await services.refresh();

    expect(result.status, RefreshStatus.readFailed);
  });

  test('with something saved, a failed upload is shown first', () async {
    final services = servicesOver(
      _PartlyFailingRepository(HealthMetric.heartRate),
      target: _RecordingTarget(fails: true),
    );
    addTearDown(services.dispose);

    final result = await services.refresh();

    expect(result.status, RefreshStatus.syncFailed);
    expect(result.cause?.kind, SyncErrorKind.network);
  });

  test('a shared bug failing every metric is reported once', () async {
    final services = servicesOver(
      _PartlyFailingRepository(null, bugInEveryRead: true),
    );
    addTearDown(services.dispose);

    await services.refresh();

    expect(reported, hasLength(1));
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

  group('while another isolate is refreshing', () {
    // A second lock under the same name stands in for the other isolate's
    // refresh; the name-to-port mapping is process-wide either way.
    const lockName = 'cairn.test.refresh';
    late Completer<void> otherDone;
    late Future<void> otherRefresh;

    setUp(() {
      otherDone = Completer<void>();
      otherRefresh = CrossIsolateLock(lockName).run(() => otherDone.future);
    });
    tearDown(() async {
      if (!otherDone.isCompleted) otherDone.complete();
      await otherRefresh;
    });

    CairnServices servicesSharing() => servicesOver(
      _PartlyFailingRepository(HealthMetric.heartRate),
      refreshLock: CrossIsolateLock(
        lockName,
        pollInterval: const Duration(milliseconds: 10),
      ),
    );

    test('a foreground refresh waits its turn', () async {
      final services = servicesSharing();
      addTearDown(services.dispose);

      var finished = false;
      final refresh = services.refresh().then((_) => finished = true);
      await Future<void>.delayed(const Duration(milliseconds: 100));
      expect(finished, isFalse);
      // Not merely unfinished: ingest itself hasn't started.
      expect(services.dataRevision.value, 0);

      otherDone.complete();
      await refresh;
      expect(finished, isTrue);
    });

    test('a background refresh skips instead of waiting', () async {
      final services = servicesSharing();
      addTearDown(services.dispose);

      expect(await services.refreshInBackground(), isNull);
      expect(services.dataRevision.value, 0);
    });
  });

  group('background reads', () {
    test('a background run without the permission only uploads', () async {
      final repo = _PartlyFailingRepository(
        null,
        background: ReadAccessStatus.missing,
      );
      final target = _RecordingTarget();
      final services = servicesOver(repo, target: target);
      addTearDown(services.dispose);
      // Something on disk to upload.
      await services.store.setSyncAnchor(HealthMetric.weight, DateTime(2026));

      final result = await services.refreshInBackground();

      expect(result!.status, RefreshStatus.ok);
      expect(repo.reads, isEmpty);
      expect(target.puts, isNotEmpty);
    });

    test('a background run with the permission reads', () async {
      final repo = _PartlyFailingRepository(
        null,
        background: ReadAccessStatus.granted,
      );
      final services = servicesOver(repo);
      addTearDown(services.dispose);

      await services.refreshInBackground();

      expect(repo.reads, isNotEmpty);
    });

    test('a foreground refresh asks once per device, never again', () async {
      final repo = _PartlyFailingRepository(
        null,
        background: ReadAccessStatus.missing,
      );
      final first = servicesOver(repo);
      addTearDown(first.dispose);
      await first.refresh();
      await first.checkReadAccess();
      await first.refresh();
      await first.checkReadAccess();
      // A later launch on the same device remembers it asked (and was
      // declined: the status is still missing).
      final relaunched = servicesOver(repo);
      addTearDown(relaunched.dispose);
      await relaunched.refresh();
      await relaunched.checkReadAccess();

      expect(repo.backgroundRequests, 1);
    });

    test('no ask where there is nothing to ask for', () async {
      for (final status in [
        ReadAccessStatus.granted,
        ReadAccessStatus.unavailable,
        ReadAccessStatus.notApplicable,
      ]) {
        final repo = _PartlyFailingRepository(null, background: status);
        final services = servicesOver(repo);
        addTearDown(services.dispose);

        await services.refresh();
        await services.checkReadAccess();

        expect(repo.backgroundRequests, 0, reason: '$status');
      }
    });

    test('the ask comes only after the data was read', () async {
      // An open permission sheet must not hold up reading and uploading.
      final repo = _PartlyFailingRepository(
        null,
        background: ReadAccessStatus.missing,
      );
      final services = servicesOver(repo);
      addTearDown(services.dispose);

      await services.refresh();
      // The ask runs after the refresh has returned, not inside it.
      expect(repo.backgroundRequests, 0);
      await services.checkReadAccess();

      expect(repo.readsBeforeAsk, greaterThan(0));
      expect(services.backgroundRead.value, ReadAccessStatus.missing);
    });

    test(
      'a grant already in place is remembered: no prompt on revoke',
      () async {
        final repo = _PartlyFailingRepository(
          null,
          background: ReadAccessStatus.granted,
        );
        final services = servicesOver(repo);
        addTearDown(services.dispose);
        await services.refresh();
        await services.checkReadAccess();

        // Revoked on purpose in Health Connect later: not nagged about it.
        repo.background = ReadAccessStatus.missing;
        await services.refresh();
        await services.checkReadAccess();

        expect(repo.backgroundRequests, 0);
        expect(services.backgroundRead.value, ReadAccessStatus.missing);
      },
    );

    test('a background run where Health Connect cannot read there', () async {
      final repo = _PartlyFailingRepository(
        null,
        background: ReadAccessStatus.unavailable,
      );
      final services = servicesOver(repo);
      addTearDown(services.dispose);

      await services.refreshInBackground();

      expect(repo.reads, isEmpty);
    });

    test('no ask while no read is granted at all', () async {
      final repo = _PartlyFailingRepository(
        null,
        background: ReadAccessStatus.missing,
        grantsReads: false,
      );
      final services = servicesOver(repo);
      addTearDown(services.dispose);

      await services.refresh();
      await services.checkReadAccess();

      expect(repo.backgroundRequests, 0);
    });
  });

  group('history reads', () {
    test('a refresh publishes the status for Settings', () async {
      final repo = _PartlyFailingRepository(null)
        ..history = ReadAccessStatus.missing;
      final services = servicesOver(repo);
      addTearDown(services.dispose);

      await services.refresh();
      await services.checkReadAccess();

      expect(services.historyRead.value, ReadAccessStatus.missing);
    });

    test('a failed background check still updates history', () async {
      final repo = _PartlyFailingRepository(null)
        ..history = ReadAccessStatus.missing
        ..failsBackgroundCheck = true;
      final services = servicesOver(repo);
      addTearDown(services.dispose);

      await services.checkReadAccess();

      expect(services.historyRead.value, ReadAccessStatus.missing);
      expect(services.backgroundRead.value, isNull);
    });

    test('asking publishes the status it left behind', () async {
      final repo = _PartlyFailingRepository(null)
        ..history = ReadAccessStatus.missing;
      final services = servicesOver(repo);
      addTearDown(services.dispose);

      expect(await services.askForHistoryRead(), ReadAccessStatus.granted);
      expect(services.historyRead.value, ReadAccessStatus.granted);
    });
  });

  test('a refresh after dispose does nothing, and does not throw', () async {
    // E.g. one that waited for the lock while the shell was torn down: the
    // notifiers and the HTTP client are gone by the time it runs.
    final services = servicesOver(
      _PartlyFailingRepository(HealthMetric.heartRate),
    )..dispose();

    final result = await services.refresh();

    expect(result.status, RefreshStatus.ok);
    expect(await services.store.lastSyncAnchor(HealthMetric.weight), isNull);
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
