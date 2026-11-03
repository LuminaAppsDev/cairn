import 'package:flutter/foundation.dart';

/// The credential bundle obtained from Nextcloud Login Flow v2 and used for
/// every subsequent WebDAV request (DESIGN.md §6).
///
/// Login Flow v2 hands back all three fields together: the [server] base URL,
/// the [loginName], and a revocable [appPassword] (never the user's main
/// password). WebDAV needs all three, so they are stored and passed as one
/// atomic unit in OS secure storage (Keychain / Android Keystore).
@immutable
class NextcloudCredentials {
  /// Creates a credential bundle. [server] must be an `https` URL — Basic
  /// auth is only ever sent over TLS.
  new({
    required this.server,
    required this.loginName,
    required this.appPassword,
  }) {
    if (server.scheme != 'https') {
      throw ArgumentError.value(
        server.toString(),
        'server',
        'Nextcloud server must be https (Basic auth is sent in the clear over '
            'http)',
      );
    }
  }

  /// Restores credentials from the JSON map written by [toJson].
  ///
  /// Throws [FormatException] if any field is missing or malformed, or if the
  /// stored server is not `https` — so callers reading storage need only
  /// catch an [Exception].
  factory fromJson(Map<String, Object?> json) {
    final server = json['server'];
    final loginName = json['login_name'];
    final appPassword = json['app_password'];
    if (server is! String || loginName is! String || appPassword is! String) {
      throw const FormatException('Malformed Nextcloud credentials');
    }
    final uri = Uri.tryParse(server);
    if (uri == null) {
      throw FormatException('Malformed Nextcloud server URL', server);
    }
    if (uri.scheme != 'https') {
      throw FormatException('Nextcloud server must be https', server);
    }
    return NextcloudCredentials(
      server: uri,
      loginName: loginName,
      appPassword: appPassword,
    );
  }

  /// The Nextcloud base URL, e.g. `https://cloud.example.com`.
  final Uri server;

  /// The account login name the app password belongs to.
  final String loginName;

  /// The revocable Login Flow v2 app password (the secret).
  final String appPassword;

  /// The WebDAV files endpoint for this account:
  /// `<server>/remote.php/dav/files/<loginName>/`.
  Uri get webDavBase => server.replace(
    pathSegments: [
      ...server.pathSegments.where((s) => s.isNotEmpty),
      'remote.php',
      'dav',
      'files',
      loginName,
      '',
    ],
  );

  /// Serialises to a JSON map for secure storage.
  Map<String, Object?> toJson() => {
    'server': server.toString(),
    'login_name': loginName,
    'app_password': appPassword,
  };
}
