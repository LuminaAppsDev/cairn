import 'dart:async';

import 'package:cairn/src/health/background_read_prompt.dart';
import 'package:cairn/src/health/background_read_status.dart';
import 'package:cairn/src/health/health_metric.dart';
import 'package:cairn/src/health/health_package_repository.dart';
import 'package:cairn/src/health/health_repository.dart';
import 'package:cairn/src/profile/profile.dart';
import 'package:cairn/src/profile/profile_store.dart';
import 'package:cairn/src/profile/profile_sync.dart';
import 'package:cairn/src/query/health_query_service.dart';
import 'package:cairn/src/shell/cross_isolate_lock.dart';
import 'package:cairn/src/shell/error_reporting.dart';
import 'package:cairn/src/storage/atomic_file.dart';
import 'package:cairn/src/storage/health_ingest_service.dart';
import 'package:cairn/src/storage/jsonl_omh_file_store.dart';
import 'package:cairn/src/sync/flutter_secure_token_store.dart';
import 'package:cairn/src/sync/http_nextcloud_auth.dart';
import 'package:cairn/src/sync/nextcloud_sync_coordinator.dart';
import 'package:cairn/src/sync/nextcloud_sync_service.dart';
import 'package:cairn/src/sync/nextcloud_sync_target.dart';
import 'package:cairn/src/sync/sync_journal.dart';
import 'package:cairn/src/sync/webdav_nextcloud_sync_target.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

/// WebDAV path of the synced profile, relative to the account root. Matches the
/// sync service's remote root (`Cairn`) + the profile file name.
const String _profileRemotePath = 'Cairn/profile.json';

/// The outcome of a [CairnServices.refresh], for the UI to localise.
enum RefreshStatus {
  /// Data was read and (if connected) synced successfully.
  ok,

  /// Reading from the OS health store failed — entirely, or for at least one
  /// metric, in which case everything else read was saved (and synced). A
  /// failed metric keeps its anchor, so the next refresh retries it.
  readFailed,

  /// The OS health store is not available at all (Android: Health Connect is
  /// missing or its provider needs an update), so nothing could be read.
  healthUnavailable,

  /// Data was saved locally but the upload to Nextcloud failed.
  syncFailed,
}

/// The result of a refresh: a [status], the typed [cause] when the push failed,
/// and the [report] of the push when one ran.
@immutable
class RefreshResult {
  /// Creates a refresh result.
  const RefreshResult(this.status, {this.cause, this.report});

  /// The high-level outcome.
  final RefreshStatus status;

  /// The typed sync failure, when [status] is [RefreshStatus.syncFailed] and
  /// the cause was a recognised one. The UI translates its
  /// `NextcloudSyncException.kind`; the English `message` is for logs only.
  /// `null` for an unexpected error, which is reported generically.
  final NextcloudSyncException? cause;

  /// The push report when a sync ran — [status] [RefreshStatus.ok], or
  /// [RefreshStatus.readFailed] after a partial read failure; `null` when not
  /// connected to Nextcloud (read happened, nothing uploaded) or nothing ran.
  final SyncReport? report;
}

/// The app's shared, app-lifetime services, built once and owned by the shell.
///
/// Holds the single [http.Client] used by auth + WebDAV (closed in [dispose]),
/// the local cache, the profile store, the read-path query service, the sync
/// coordinator, and the health-store reader.
final class CairnServices {
  /// Creates a services holder. Prefer [create].
  CairnServices({
    required this.client,
    required this.store,
    required this.profileStore,
    required this.profile,
    required this.query,
    required this.coordinator,
    required this.profileSync,
    required this.repository,
    required this.backgroundReadPrompt,
    CrossIsolateLock? refreshLock,
  }) : _refreshLock = refreshLock ?? CrossIsolateLock('cairn.refresh');

  /// Resolves the on-device stores and wires the services together.
  static Future<CairnServices> create() async {
    final client = http.Client();
    final store = await JsonlOmhFileStore.appDocuments();
    final journalStore = await JsonSyncJournalStore.appSupport();
    // Clear temp files a crashed write left behind; best-effort, off the path.
    unawaited(sweepStaleTempFiles(store.root));
    unawaited(
      sweepStaleTempFiles(journalStore.file.parent, recursive: false),
    );
    final profileStore = JsonProfileStore(root: store.root);
    final coordinator = NextcloudSyncCoordinator(
      auth: HttpNextcloudAuth(client: client),
      tokenStore: FlutterSecureTokenStore(),
      localRoot: store.root,
      journalStore: journalStore,
      targetFactory: (credentials) =>
          WebDavNextcloudSyncTarget(credentials: credentials, client: client),
    );
    return CairnServices(
      client: client,
      store: store,
      profileStore: profileStore,
      profile: ValueNotifier(await profileStore.read()),
      query: OmhHealthQueryService(store: store),
      coordinator: coordinator,
      profileSync: ProfileSyncService(
        store: profileStore,
        download: () => coordinator.downloadFile(
          _profileRemotePath,
          maxBytes: kMaxProfileBytes,
        ),
      ),
      repository: HealthPackageRepository(),
      backgroundReadPrompt: await BackgroundReadPrompt.appSupport(),
    );
  }

  /// One HTTP client shared by auth + WebDAV.
  final http.Client client;

  /// The local OMH cache.
  final JsonlOmhFileStore store;

  /// The synced user-profile store.
  final JsonProfileStore profileStore;

  /// The current user profile, app-wide reactive source of truth. Settings
  /// updates it on save so the Home BMI card recomputes without a refresh.
  final ValueNotifier<Profile> profile;

  /// The read-path query service over [store].
  final HealthQueryService query;

  /// The Nextcloud connect + sync coordinator.
  final NextcloudSyncCoordinator coordinator;

  /// Pulls `profile.json` back down from Nextcloud (last-write-wins).
  final ProfileSyncService profileSync;

  /// The OS health-store reader (for manual refresh/ingest).
  final HealthRepository repository;

  /// Remembers whether this device was already asked for background reads.
  final BackgroundReadPrompt backgroundReadPrompt;

  /// Bumped after every ingest so all data screens reload immediately when new
  /// readings land in the cache (the read-path analogue of [profile]).
  final ValueNotifier<int> dataRevision = ValueNotifier(0);

  /// Whether background sync may read the health store; `null` until first
  /// checked. Foreground refreshes, [checkBackgroundRead] and
  /// [askForBackgroundRead] keep it current; Settings shows it.
  final ValueNotifier<BackgroundReadStatus?> backgroundRead = ValueNotifier(
    null,
  );

  Future<RefreshResult>? _refreshInFlight;

  /// Serialises refreshes across the isolates of the process (UI and
  /// background sync), which would otherwise interleave their writes to the
  /// manifest, shards and sync journal.
  final CrossIsolateLock _refreshLock;

  /// Reads new data from the OS health store into the cache, bumps
  /// [dataRevision] so screens reload, then pushes to Nextcloud if connected.
  /// Returns a typed [RefreshResult] the UI localises.
  ///
  /// Concurrent calls in this isolate (e.g. the Home button and a Sleep
  /// pull-to-refresh) are coalesced into a single run; a refresh in another
  /// isolate of the process (background sync) is waited out first — the
  /// foreground path; background sync uses [refreshInBackground]. Either way,
  /// ingest/sync never overlap.
  Future<RefreshResult> refresh() {
    return _refreshInFlight ??= _refreshLock.run(_runForeground).whenComplete(
      () {
        _refreshInFlight = null;
        // Only now — data read and uploaded, the lock released, this refresh's
        // caller answered — so an open permission sheet holds up nothing.
        if (_readsGranted && !_disposed) {
          unawaited(_checkBackgroundRead(askOnce: true));
        }
      },
    );
  }

  /// The background sync's refresh (WorkManager / BGTaskScheduler): runs only
  /// if no other isolate is refreshing right now, and returns `null` (having
  /// done nothing) if one is — background sync is opportunistic, and its OS
  /// budget short. Reads only where background reads are allowed; otherwise
  /// it just uploads.
  Future<RefreshResult?> refreshInBackground() =>
      _refreshLock.tryRun(() => _runRefresh(background: true));

  Future<RefreshResult> _runForeground() async {
    // A refresh that waited for the lock may find the services torn down by
    // then (the shell disposed meanwhile); it must not touch them.
    if (_disposed) return const RefreshResult(RefreshStatus.ok);
    return _runRefresh(background: false);
  }

  bool _disposed = false;

  /// Whether the last refresh had any read permission granted.
  bool _readsGranted = false;

  /// Re-reads [backgroundRead] (Settings: on open and on resume). Completes
  /// after any check or ask already under way.
  Future<void> checkBackgroundRead() => _checkBackgroundRead();

  /// Asks for background reads on demand (the Settings button) and returns
  /// the status afterwards — also published on [backgroundRead] — or `null`
  /// if the request failed.
  Future<BackgroundReadStatus?> askForBackgroundRead() =>
      _oneCheckAtATime(() async {
        try {
          final status = await repository.requestBackgroundRead();
          if (!_disposed) backgroundRead.value = status;
          return status;
        } on Object catch (error, stack) {
          debugPrint('Background-read request failed: $error');
          reportIfBug(error, stack, whileDoing: 'asking for background reads');
          return null;
        }
      });

  // Checks and asks run one at a time: overlapping, a slower earlier one could
  // publish a stale status over a newer one, or two could both ask before
  // either had recorded it.
  Future<void> _checks = Future<void>.value();

  Future<T> _oneCheckAtATime<T>(Future<T> Function() check) {
    final next = _checks.then((_) => check());
    _checks = next.then<void>((_) {}, onError: (Object _) {});
    return next;
  }

  /// Pulls a newer `profile.json` down from Nextcloud (if any) and adopts it,
  /// updating [profile] so the dashboard reflects it without a manual reload.
  /// Called after connecting, so a fresh install / second device recovers the
  /// synced height + date of birth. Best-effort: a failed pull (offline, etc.)
  /// is logged, never thrown, so it can't block the connect flow.
  Future<void> pullProfile() async {
    try {
      final pulled = await profileSync.pull();
      if (pulled != null) profile.value = pulled;
    } on Object catch (error, stack) {
      debugPrint('Profile pull failed: $error');
      reportIfBug(error, stack, whileDoing: 'pulling profile.json');
    }
  }

  Future<RefreshResult> _runRefresh({required bool background}) async {
    // Both catch blocks below are `on Object`, not `on Exception`: the health
    // plugin signals a missing Health Connect with an UnsupportedError, which
    // is an Error. Letting one escape would complete this future with an error,
    // so every caller's `await refresh()` would throw before it could clear its
    // spinner — the UI would hang with no message at all.
    final List<IngestResult> ingested;
    try {
      ingested = await _ingest(background: background);
    } on HealthStoreUnavailableException {
      return const RefreshResult(RefreshStatus.healthUnavailable);
    } on Object catch (error, stack) {
      // Don't surface a raw exception string to the UI — it could, in
      // principle, carry sensitive data. Log it for diagnosis instead.
      debugPrint('Health read failed: $error');
      reportIfBug(error, stack, whileDoing: 'reading the OS health store');
      return const RefreshResult(RefreshStatus.readFailed);
    }
    // New local data is on disk → refresh the screens even if the upload fails
    // (unless the shell was torn down mid-refresh: no screens, no notifier).
    if (!_disposed) dataRevision.value++;
    SyncReport? report;
    try {
      if (await coordinator.isConnected()) report = await coordinator.syncNow();
    } on NextcloudSyncException catch (error) {
      // The typed kind travels to the UI, which translates it; the English
      // message stays in the log.
      debugPrint('Sync failed: ${error.message}');
      return RefreshResult(RefreshStatus.syncFailed, cause: error);
    } on Object catch (error, stack) {
      // Unexpected/untyped error → generic message; never echo the raw cause.
      debugPrint('Sync failed: $error');
      reportIfBug(error, stack, whileDoing: 'pushing to Nextcloud');
      return const RefreshResult(RefreshStatus.syncFailed);
    }
    // A metric whose read failed kept its anchor, so the next refresh retries
    // it; everything else is saved (and synced) — but the user should know.
    if (ingested.any((result) => result.readFailed)) {
      // Keep the push report: its conflict warning still matters.
      return RefreshResult(RefreshStatus.readFailed, report: report);
    }
    // report == null → not connected (read succeeded, nothing uploaded).
    return RefreshResult(RefreshStatus.ok, report: report);
  }

  // The read half of a refresh. A background run that may not read the health
  // store (Android's separate background permission — without it a read may
  // fail) skips it and only uploads.
  Future<List<IngestResult>> _ingest({required bool background}) async {
    _readsGranted = false;
    if (background &&
        !(await repository.backgroundReadStatus()).allowsBackgroundReads) {
      return const [];
    }
    final granted = await repository.requestAuthorization(
      HealthMetric.values.toSet(),
    );
    _readsGranted = granted.isNotEmpty;
    return HealthIngestService(
      repository: repository,
      store: store,
    ).ingest(granted);
  }

  // Updates [backgroundRead]. With [askOnce], also asks on its own — at most
  // once per device, and only while background reads are missing; Settings
  // can ask again. A grant found already in place is remembered too, so that
  // revoking it later on purpose isn't answered with a prompt. Optional, so a
  // failure never fails anything: the status just stays as it was.
  Future<void> _checkBackgroundRead({bool askOnce = false}) =>
      _oneCheckAtATime(() => _checkBackgroundReadNow(askOnce: askOnce));

  Future<void> _checkBackgroundReadNow({required bool askOnce}) async {
    try {
      var status = await repository.backgroundReadStatus();
      if (askOnce && !await backgroundReadPrompt.wasAsked()) {
        if (status == BackgroundReadStatus.granted) {
          await backgroundReadPrompt.markAsked();
        } else if (status == BackgroundReadStatus.missing) {
          // Recorded first, so a crash during the sheet can't become a loop.
          await backgroundReadPrompt.markAsked();
          status = await repository.requestBackgroundRead();
        }
      }
      if (!_disposed) backgroundRead.value = status;
    } on Object catch (error, stack) {
      debugPrint('Background-read check failed: $error');
      reportIfBug(error, stack, whileDoing: 'checking background reads');
    }
  }

  /// Releases the shared HTTP client and the notifiers.
  void dispose() {
    _disposed = true;
    profile.dispose();
    dataRevision.dispose();
    backgroundRead.dispose();
    client.close();
  }
}
