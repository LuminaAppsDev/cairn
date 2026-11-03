import 'package:cairn/src/health/health_metric.dart';
import 'package:cairn/src/health/health_package_repository.dart';
import 'package:cairn/src/health/health_repository.dart';
import 'package:cairn/src/profile/profile.dart';
import 'package:cairn/src/profile/profile_store.dart';
import 'package:cairn/src/profile/profile_sync.dart';
import 'package:cairn/src/query/health_query_service.dart';
import 'package:cairn/src/shell/error_reporting.dart';
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
  });

  /// Resolves the on-device stores and wires the services together.
  static Future<CairnServices> create() async {
    final client = http.Client();
    final store = await JsonlOmhFileStore.appDocuments();
    final journalStore = await JsonSyncJournalStore.appSupport();
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

  /// Bumped after every ingest so all data screens reload immediately when new
  /// readings land in the cache (the read-path analogue of [profile]).
  final ValueNotifier<int> dataRevision = ValueNotifier(0);

  Future<RefreshResult>? _refreshInFlight;

  /// Reads new data from the OS health store into the cache, bumps
  /// [dataRevision] so screens reload, then pushes to Nextcloud if connected.
  /// Returns a typed [RefreshResult] the UI localises.
  ///
  /// Concurrent calls (e.g. the Home button and a Sleep pull-to-refresh) are
  /// coalesced into a single run, so ingest/sync never overlap.
  Future<RefreshResult> refresh() {
    return _refreshInFlight ??= _runRefresh().whenComplete(() {
      _refreshInFlight = null;
    });
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

  Future<RefreshResult> _runRefresh() async {
    // Both catch blocks below are `on Object`, not `on Exception`: the health
    // plugin signals a missing Health Connect with an UnsupportedError, which
    // is an Error. Letting one escape would complete this future with an error,
    // so every caller's `await refresh()` would throw before it could clear its
    // spinner — the UI would hang with no message at all.
    final List<IngestResult> ingested;
    try {
      final granted = await repository.requestAuthorization(
        HealthMetric.values.toSet(),
      );
      ingested = await HealthIngestService(
        repository: repository,
        store: store,
      ).ingest(granted);
    } on HealthStoreUnavailableException {
      return const RefreshResult(RefreshStatus.healthUnavailable);
    } on Object catch (error, stack) {
      // Don't surface a raw exception string to the UI — it could, in
      // principle, carry sensitive data. Log it for diagnosis instead.
      debugPrint('Health read failed: $error');
      reportIfBug(error, stack, whileDoing: 'reading the OS health store');
      return const RefreshResult(RefreshStatus.readFailed);
    }
    // New local data is on disk → refresh the screens even if the upload fails.
    dataRevision.value++;
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

  /// Releases the shared HTTP client and the notifiers.
  void dispose() {
    profile.dispose();
    dataRevision.dispose();
    client.close();
  }
}
