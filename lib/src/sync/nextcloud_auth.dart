import 'package:cairn/src/sync/nextcloud_credentials.dart';
import 'package:flutter/foundation.dart';

/// A pending Nextcloud Login Flow v2 session (DESIGN.md §6).
@immutable
class LoginFlowSession {
  /// Creates a login-flow session.
  const new({
    required this.loginUrl,
    required this.pollToken,
    required this.pollEndpoint,
  });

  /// URL the user opens in the system browser to authorise Cairn.
  final Uri loginUrl;

  /// Opaque token used to poll for the resulting app password.
  final String pollToken;

  /// Endpoint to poll with [pollToken]. Returned verbatim by the server — not
  /// assembled from [loginUrl] — so we never assume the server's URL layout.
  final Uri pollEndpoint;
}

/// Obtains Nextcloud credentials via Login Flow v2, so Cairn never handles the
/// user's main password (DESIGN.md §6).
abstract interface class NextcloudAuth {
  /// Begins Login Flow v2 against [host] and returns the session used to drive
  /// the browser hand-off and polling.
  Future<LoginFlowSession> begin(Uri host);

  /// Polls [session]; completes with the [NextcloudCredentials] once the user
  /// has authorised in the browser, or `null` while the flow is still pending.
  Future<NextcloudCredentials?> poll(LoginFlowSession session);
}
