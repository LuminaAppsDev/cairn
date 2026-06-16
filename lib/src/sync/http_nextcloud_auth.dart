import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:cairn/src/sync/nextcloud_auth.dart';
import 'package:cairn/src/sync/nextcloud_credentials.dart';
import 'package:cairn/src/sync/nextcloud_sync_target.dart';
import 'package:http/http.dart' as http;

/// User-Agent sent on the Login Flow v2 request. Nextcloud uses it as the
/// label for the generated app password in the user's security settings.
const String _userAgent = 'Cairn';

/// Per-request timeout, so an unresponsive server can't hang the flow forever.
const Duration _requestTimeout = Duration(seconds: 30);

/// [NextcloudAuth] over Nextcloud's Login Flow v2 endpoints, spoken on a
/// permissive [http.Client] (DESIGN.md §6).
///
/// Flow: [begin] POSTs `…/index.php/login/v2`; the user opens the returned
/// `login` URL in a browser and authorises; [poll] then exchanges the poll
/// token for a revocable app password. The user's main password never touches
/// the app.
final class HttpNextcloudAuth implements NextcloudAuth {
  /// Creates an auth client. [client] is injectable for tests; the default is
  /// owned elsewhere (callers reuse one client across the app).
  HttpNextcloudAuth({http.Client? client}) : _client = client ?? http.Client();

  final http.Client _client;

  @override
  Future<LoginFlowSession> begin(Uri host) async {
    if (host.scheme != 'https') {
      throw NextcloudSyncException(
        'Nextcloud host must be https, got "${host.scheme}"',
      );
    }
    final url = host.replace(
      pathSegments: [
        ...host.pathSegments.where((s) => s.isNotEmpty),
        'index.php',
        'login',
        'v2',
      ],
    );
    final response = await _post(url);
    if (response.statusCode != 200) {
      throw NextcloudSyncException(
        'Login Flow v2 init failed',
        statusCode: response.statusCode,
      );
    }
    return _parseSession(response.body, host);
  }

  @override
  Future<NextcloudCredentials?> poll(LoginFlowSession session) async {
    final response = await _post(
      session.pollEndpoint,
      body: {'token': session.pollToken},
    );
    // The flow is complete only on a 200. Anything else means "not yet": 404
    // is the documented pending status, and a 3xx can appear when Nextcloud
    // sits behind a reverse proxy or in a sub-path (the POST is not auto-
    // followed) — so keep polling rather than aborting a flow the browser
    // will finish.
    final code = response.statusCode;
    if (code == 404 || (code >= 300 && code < 400)) return null;
    if (code != 200) {
      throw NextcloudSyncException(
        'Login Flow v2 poll failed',
        statusCode: code,
      );
    }
    return _parseCredentials(response.body);
  }

  Future<http.Response> _post(Uri url, {Map<String, String>? body}) async {
    try {
      return await _client
          .post(
            url,
            headers: const {
              'User-Agent': _userAgent,
              'Accept': 'application/json',
            },
            body: body,
          )
          .timeout(_requestTimeout);
    } on TimeoutException {
      throw const NextcloudSyncException(
        'Login Flow v2 request timed out',
        retryable: true,
      );
    } on http.ClientException catch (error) {
      throw NextcloudSyncException(
        'network error: ${error.message}',
        retryable: true,
      );
    } on SocketException catch (error) {
      throw NextcloudSyncException(
        'network error: ${error.message}',
        retryable: true,
      );
    }
  }

  LoginFlowSession _parseSession(String body, Uri host) {
    final json = _decodeObject(body);
    final login = json['login'];
    final poll = json['poll'];
    if (login is! String || poll is! Map<String, Object?>) {
      throw const NextcloudSyncException('Malformed Login Flow v2 response');
    }
    final token = poll['token'];
    final endpoint = poll['endpoint'];
    final loginUrl = Uri.tryParse(login);
    final pollEndpoint = endpoint is String ? Uri.tryParse(endpoint) : null;
    if (token is! String || loginUrl == null || pollEndpoint == null) {
      throw const NextcloudSyncException('Malformed Login Flow v2 response');
    }
    // The server controls these URLs; pin them to the https host we contacted
    // so a malicious response can neither redirect the browser hand-off to a
    // hostile scheme (e.g. `file:`/`intent:`) nor leak the poll token to an
    // internal host (SSRF).
    _requireSameHttpsHost(loginUrl, host, 'login URL');
    _requireSameHttpsHost(pollEndpoint, host, 'poll endpoint');
    return LoginFlowSession(
      loginUrl: loginUrl,
      pollToken: token,
      pollEndpoint: pollEndpoint,
    );
  }

  void _requireSameHttpsHost(Uri url, Uri host, String label) {
    if (url.scheme != 'https' || !_serverHostAllowed(url.host, host.host)) {
      throw NextcloudSyncException(
        'Login Flow v2 $label must be https on ${host.host}',
      );
    }
  }

  /// Whether the server-returned [serverHost] is acceptable for the host the
  /// user [typedHost].
  ///
  /// Nextcloud generates the `login`/`poll` URLs from its configured base URL,
  /// which can legitimately be a sub-domain of what the user typed (e.g. they
  /// typed `example.com` and Nextcloud serves `www.example.com`). That single
  /// direction is allowed; everything else is refused so a malicious response
  /// cannot point the browser hand-off or the poll token at a foreign host.
  ///
  /// Constraints that preserve the SSRF intent:
  /// - exact match always passes;
  /// - the server host may be a *sub-domain* of the typed host, never a
  ///   *parent* (a parent could be an attacker-controlled apex);
  /// - the typed host must be multi-label, so a bare suffix like `com` cannot
  ///   act as the base and admit `evil.com`.
  static bool _serverHostAllowed(String serverHost, String typedHost) {
    if (serverHost.isEmpty || typedHost.isEmpty) return false;
    if (serverHost == typedHost) return true;
    return typedHost.contains('.') && serverHost.endsWith('.$typedHost');
  }

  NextcloudCredentials _parseCredentials(String body) {
    final json = _decodeObject(body);
    final server = json['server'];
    final loginName = json['loginName'];
    final appPassword = json['appPassword'];
    if (server is! String || loginName is! String || appPassword is! String) {
      throw const NextcloudSyncException('Malformed Login Flow v2 poll result');
    }
    final uri = Uri.tryParse(server);
    if (uri == null) {
      throw const NextcloudSyncException('Malformed server URL in poll result');
    }
    // Validate the scheme here so the (https-enforcing) credentials
    // constructor never has to throw.
    if (uri.scheme != 'https') {
      throw NextcloudSyncException(
        'Nextcloud server must be https, got "${uri.scheme}"',
      );
    }
    return NextcloudCredentials(
      server: uri,
      loginName: loginName,
      appPassword: appPassword,
    );
  }

  Map<String, Object?> _decodeObject(String body) {
    final Object? decoded;
    try {
      decoded = jsonDecode(body);
    } on FormatException {
      throw const NextcloudSyncException('Login Flow v2 response is not JSON');
    }
    if (decoded is! Map<String, Object?>) {
      throw const NextcloudSyncException(
        'Login Flow v2 response is not an '
        'object',
      );
    }
    return decoded;
  }
}
