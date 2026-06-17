import 'package:cairn/src/health/health_metric.dart';
import 'package:cairn/src/health/health_package_repository.dart';
import 'package:cairn/src/health/health_repository.dart';
import 'package:cairn/src/profile/profile.dart';
import 'package:cairn/src/profile/profile_store.dart';
import 'package:cairn/src/profile/profile_sync.dart';
import 'package:cairn/src/query/health_query_service.dart';
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

  /// Reading from the OS health store failed; nothing was saved.
  readFailed,

  /// Data was saved locally but the upload to Nextcloud failed.
  syncFailed,
}

/// The result of a refresh: a [status], an optional raw [detail] (a technical
/// cause, not localised), and the [report] of the push when one ran.
@immutable
class RefreshResult {
  /// Creates a refresh result.
  const RefreshResult(this.status, {this.detail, this.report});

  /// The high-level outcome.
  final RefreshStatus status;

  /// The raw error cause, when [status] is a failure.
  final String? detail;

  /// The push report when [status] is [RefreshStatus.ok] and a sync ran;
  /// `null` when not connected to Nextcloud (read happened, nothing uploaded).
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
    } on Exception catch (error) {
      debugPrint('Profile pull failed: $error');
    }
  }

  Future<RefreshResult> _runRefresh() async {
    try {
      final granted = await repository.requestAuthorization(
        HealthMetric.values.toSet(),
      );
      await HealthIngestService(
        repository: repository,
        store: store,
      ).ingest(granted);
    } on Exception catch (error) {
      // Don't surface a raw exception string to the UI — it could, in
      // principle, carry sensitive data. Log it for diagnosis instead.
      debugPrint('Health read failed: $error');
      return const RefreshResult(RefreshStatus.readFailed);
    }
    // New local data is on disk → refresh the screens even if the upload fails.
    dataRevision.value++;
    SyncReport? report;
    try {
      if (await coordinator.isConnected()) report = await coordinator.syncNow();
    } on NextcloudSyncException catch (error) {
      // NextcloudSyncException.message is a controlled, non-sensitive string.
      return RefreshResult(RefreshStatus.syncFailed, detail: error.message);
    } on Exception catch (error) {
      // Unexpected/untyped error → generic message; never echo the raw cause.
      debugPrint('Sync failed: $error');
      return const RefreshResult(RefreshStatus.syncFailed);
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
