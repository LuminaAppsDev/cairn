import 'dart:io';
import 'dart:typed_data';

import 'package:cairn/src/sync/nextcloud_auth.dart';
import 'package:cairn/src/sync/nextcloud_credentials.dart';
import 'package:cairn/src/sync/nextcloud_sync_service.dart';
import 'package:cairn/src/sync/nextcloud_sync_target.dart';
import 'package:cairn/src/sync/secure_token_store.dart';
import 'package:cairn/src/sync/sync_journal.dart';
import 'package:cairn/src/sync/webdav_nextcloud_sync_target.dart';

/// Builds the WebDAV target for a set of credentials. Injectable so tests can
/// substitute an in-memory target.
typedef SyncTargetFactory =
    NextcloudSyncTarget Function(NextcloudCredentials credentials);

/// Ties the sync pieces together: Login Flow v2 auth, secure credential
/// storage, and the WebDAV push (DESIGN.md §6). Pure Dart (no Flutter) so the
/// whole connect-and-sync flow is unit-testable with fakes.
///
/// The browser hand-off and poll loop live in the UI; this coordinator exposes
/// the steps it drives: [begin], [pollAndStore], and [syncNow].
final class NextcloudSyncCoordinator {
  /// Creates a coordinator. [targetFactory] defaults to the real WebDAV target.
  NextcloudSyncCoordinator({
    required this.auth,
    required this.tokenStore,
    required this.localRoot,
    required this.journalStore,
    SyncTargetFactory? targetFactory,
  }) : _targetFactory =
           targetFactory ??
           ((credentials) =>
               WebDavNextcloudSyncTarget(credentials: credentials));

  /// Login Flow v2 client.
  final NextcloudAuth auth;

  /// Secure storage for the resulting credentials.
  final SecureTokenStore tokenStore;

  /// The local `/Cairn` directory pushed by [syncNow].
  final Directory localRoot;

  /// Persists the device-local push journal.
  final JsonSyncJournalStore journalStore;

  final SyncTargetFactory _targetFactory;

  /// Begins Login Flow v2 against [host]; the caller opens
  /// `session.loginUrl` in the browser, then polls via [pollAndStore].
  Future<LoginFlowSession> begin(Uri host) => auth.begin(host);

  /// Polls [session] once. If the user has authorised, stores the returned
  /// credentials and returns them; otherwise returns `null` (still pending) so
  /// the caller can poll again.
  ///
  /// SECURITY: every failure here MUST surface as a [NextcloudSyncException]
  /// (a controlled message), never a raw error. The connect UI shows the raw
  /// text of any *other* exception type for diagnostics, so an unwrapped throw
  /// from `auth.poll` or `tokenStore.writeCredentials` could leak the app
  /// password into a visible message. Both collaborators uphold this today
  /// (network/parse/secure-storage errors are wrapped); preserve it on change.
  Future<NextcloudCredentials?> pollAndStore(LoginFlowSession session) async {
    final credentials = await auth.poll(session);
    if (credentials != null) {
      await tokenStore.writeCredentials(credentials);
    }
    return credentials;
  }

  /// Downloads [remotePath] (relative to the WebDAV root, e.g.
  /// `Cairn/profile.json`) with the stored credentials, aborting if the body
  /// would exceed [maxBytes]. Returns `null` if not connected or the file is
  /// absent (`404`); other failures surface as a [NextcloudSyncException]. A
  /// read-only primitive for the limited remote→local pull (profile today;
  /// more in the Phase 8 bidirectional work).
  Future<Uint8List?> downloadFile(String remotePath, {int? maxBytes}) async {
    final credentials = await tokenStore.readCredentials();
    if (credentials == null) return null;
    try {
      return await _targetFactory(
        credentials,
      ).getFile(remotePath, maxBytes: maxBytes);
    } on NextcloudNotFoundException {
      return null;
    }
  }

  /// The stored credentials, or `null` if not connected.
  Future<NextcloudCredentials?> currentCredentials() =>
      tokenStore.readCredentials();

  /// Whether credentials are stored.
  Future<bool> isConnected() async =>
      await tokenStore.readCredentials() != null;

  /// When this device last completed a push, or `null` if it never has. Read
  /// from the device-local journal so it survives restarts (for the Settings
  /// "last synced" line); independent of whether credentials are still stored.
  Future<DateTime?> lastSyncedAt() async =>
      (await journalStore.read()).syncedAt;

  /// Clears the stored credentials (disconnect).
  Future<void> disconnect() => tokenStore.deleteCredentials();

  /// Pushes the local cache to Nextcloud using the stored credentials.
  /// Throws [StateError] if not connected.
  Future<SyncReport> syncNow() async {
    final credentials = await tokenStore.readCredentials();
    if (credentials == null) {
      throw StateError('Not connected to Nextcloud');
    }
    final service = NextcloudSyncService(
      target: _targetFactory(credentials),
      localRoot: localRoot,
      journalStore: journalStore,
    );
    return service.push();
  }
}
