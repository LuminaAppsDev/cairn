import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:cairn/src/sync/nextcloud_credentials.dart';
import 'package:cairn/src/sync/nextcloud_sync_target.dart';
import 'package:http/http.dart' as http;
import 'package:xml/xml.dart';

/// Default per-request timeout, so an unresponsive server can't hang a sync
/// forever.
const Duration _defaultRequestTimeout = Duration(seconds: 30);

/// Body of the `PROPFIND` request: ask only for the properties the sync engine
/// uses (type, ETag, size). Insignificant whitespace keeps each line short.
const String _propfindBody = '''
<?xml version="1.0" encoding="utf-8"?>
<d:propfind xmlns:d="DAV:">
  <d:prop><d:resourcetype/><d:getetag/><d:getcontentlength/></d:prop>
</d:propfind>''';

/// [NextcloudSyncTarget] speaking WebDAV over a permissive [http.Client]
/// against `<server>/remote.php/dav/files/<user>/` (DESIGN.md §6).
///
/// Authentication is HTTP Basic with the Login Flow v2 app password, only ever
/// sent over the `https` URL the credentials enforce.
final class WebDavNextcloudSyncTarget implements NextcloudSyncTarget {
  /// Creates a target for [credentials]. [client] and `requestTimeout` are
  /// injectable for tests.
  WebDavNextcloudSyncTarget({
    required NextcloudCredentials credentials,
    http.Client? client,
    this._requestTimeout = _defaultRequestTimeout,
  }) : _base = credentials.webDavBase,
       _authHeader = _basicAuth(credentials),
       _client = client ?? http.Client();

  final Uri _base;
  final String _authHeader;
  final http.Client _client;

  /// Limit for a response's headers to arrive, and for each gap between body
  /// chunks — an idle timeout, so a slow but flowing download isn't cut off.
  final Duration _requestTimeout;

  static String _basicAuth(NextcloudCredentials credentials) {
    final raw = utf8.encode(
      '${credentials.loginName}:${credentials.appPassword}',
    );
    return 'Basic ${base64Encode(raw)}';
  }

  Map<String, String> get _headers => {'Authorization': _authHeader};

  @override
  Future<String?> putFile({
    required String remotePath,
    required Uint8List bytes,
  }) async {
    await _ensureParents(remotePath);
    final response = await _send(
      'PUT',
      _url(remotePath),
      headers: {'Content-Type': _contentTypeFor(remotePath)},
      bodyBytes: bytes,
    );
    if (response.statusCode != 201 && response.statusCode != 204) {
      throw NextcloudSyncException(
        'PUT $remotePath failed',
        kind: SyncErrorKind.serverRejected,
        statusCode: response.statusCode,
      );
    }
    return _normaliseEtag(response.headers['etag']);
  }

  @override
  Future<List<RemoteResource>> list(String remoteDir) async {
    final url = _url(remoteDir);
    final response = await _send(
      'PROPFIND',
      url,
      headers: {'Depth': '1', 'Content-Type': 'application/xml'},
      body: _propfindBody,
    );
    if (response.statusCode == 404) return const [];
    if (response.statusCode != 207) {
      throw NextcloudSyncException(
        'PROPFIND $remoteDir failed',
        kind: SyncErrorKind.serverRejected,
        statusCode: response.statusCode,
      );
    }
    return _parseMultistatus(response.body, selfPath: url.path);
  }

  @override
  Future<Uint8List> getFile(String remotePath, {int? maxBytes}) async {
    final request = http.Request('GET', _url(remotePath))
      ..headers.addAll(_headers);
    final http.StreamedResponse streamed;
    try {
      streamed = await _client.send(request).timeout(_requestTimeout);
    } on TimeoutException {
      throw _timedOut('GET $remotePath');
    }
    // Read the body with a hard ceiling so a hostile or misconfigured response
    // (even on an error status) can't exhaust memory before a size check runs.
    // Reading to completion — or aborting, which cancels the subscription —
    // releases the connection, so the status is checked only afterwards.
    final body = await _readBody(
      streamed,
      'GET $remotePath',
      maxBytes: maxBytes,
    );
    if (streamed.statusCode == 404) {
      throw NextcloudNotFoundException(remotePath);
    }
    if (streamed.statusCode != 200) {
      throw NextcloudSyncException(
        'GET $remotePath failed',
        kind: SyncErrorKind.serverRejected,
        statusCode: streamed.statusCode,
      );
    }
    return body;
  }

  /// Creates each missing parent collection of [remotePath], top-down. An
  /// already-existing collection answers `405`, which is expected and ignored.
  Future<void> _ensureParents(String remotePath) async {
    final segments = _split(remotePath);
    for (var i = 1; i < segments.length; i++) {
      final dir = segments.take(i).join('/');
      final response = await _send('MKCOL', _url(dir));
      final code = response.statusCode;
      if (code != 201 && code != 405 && code != 301) {
        throw NextcloudSyncException(
          'MKCOL $dir failed',
          kind: SyncErrorKind.serverRejected,
          statusCode: code,
        );
      }
    }
  }

  List<RemoteResource> _parseMultistatus(
    String body, {
    required String selfPath,
  }) {
    final XmlDocument doc;
    try {
      doc = XmlDocument.parse(body);
    } on XmlException {
      throw const NextcloudSyncException(
        'Malformed PROPFIND response',
        kind: SyncErrorKind.malformedResponse,
      );
    }
    final self = _trimSlash(Uri.decodeFull(selfPath));
    final resources = <RemoteResource>[];
    for (final node in doc.findAllElements('response', namespace: '*')) {
      final hrefRaw = _firstText(node, 'href');
      if (hrefRaw == null) continue;
      final href = Uri.parse(hrefRaw).path;
      // Skip the directory's own entry — callers want only its children.
      if (_trimSlash(Uri.decodeFull(href)) == self) continue;
      final isCollection = node
          .findAllElements('collection', namespace: '*')
          .isNotEmpty;
      final size = int.tryParse(_firstText(node, 'getcontentlength') ?? '');
      resources.add(
        RemoteResource(
          path: href,
          isCollection: isCollection,
          etag: _normaliseEtag(_firstText(node, 'getetag')),
          size: isCollection ? null : size,
        ),
      );
    }
    return resources;
  }

  Uri _url(String remotePath) => _base.replace(
    pathSegments: [
      ..._base.pathSegments.where((s) => s.isNotEmpty),
      ..._split(remotePath),
    ],
  );

  Future<http.Response> _send(
    String method,
    Uri url, {
    Map<String, String>? headers,
    String? body,
    Uint8List? bodyBytes,
  }) async {
    final request = http.Request(method, url)
      ..headers.addAll(_headers)
      ..headers.addAll(headers ?? const {});
    if (bodyBytes != null) {
      request.bodyBytes = bodyBytes;
    } else if (body != null) {
      request.body = body;
    }
    final http.StreamedResponse streamed;
    try {
      streamed = await _client.send(request).timeout(_requestTimeout);
    } on TimeoutException {
      throw _timedOut('$method ${url.path}');
    }
    // The body too: a connection that stalls after the headers would
    // otherwise hang the sync — and every refresh queued behind it.
    final responseBody = await _readBody(streamed, '$method ${url.path}');
    return http.Response.bytes(
      responseBody,
      streamed.statusCode,
      request: streamed.request,
      headers: streamed.headers,
      isRedirect: streamed.isRedirect,
      persistentConnection: streamed.persistentConnection,
      reasonPhrase: streamed.reasonPhrase,
    );
  }

  /// Reads [streamed]'s body, failing with a timeout when no chunk arrives
  /// for [_requestTimeout] — which also cancels the stalled subscription, so
  /// the connection is released rather than left buffering. [maxBytes] caps
  /// the size; [what] names the request in errors.
  Future<Uint8List> _readBody(
    http.StreamedResponse streamed,
    String what, {
    int? maxBytes,
  }) async {
    final builder = BytesBuilder(copy: false);
    try {
      await for (final chunk in streamed.stream.timeout(_requestTimeout)) {
        builder.add(chunk);
        if (maxBytes != null && builder.length > maxBytes) {
          throw NextcloudSyncException(
            '$what too large',
            kind: SyncErrorKind.tooLarge,
          );
        }
      }
    } on TimeoutException {
      throw _timedOut(what);
    }
    return builder.takeBytes();
  }

  static NextcloudSyncException _timedOut(String what) =>
      NextcloudSyncException(
        '$what timed out',
        kind: SyncErrorKind.timedOut,
        retryable: true,
      );

  /// MIME type for an uploaded file, so the server doesn't have to guess.
  static String _contentTypeFor(String remotePath) {
    if (remotePath.endsWith('.jsonl')) return 'application/x-ndjson';
    if (remotePath.endsWith('.json')) return 'application/json';
    return 'application/octet-stream';
  }

  static List<String> _split(String path) =>
      path.split('/').where((s) => s.isNotEmpty).toList();

  static String? _firstText(XmlElement node, String localName) {
    final matches = node.findAllElements(localName, namespace: '*');
    return matches.isEmpty ? null : matches.first.innerText.trim();
  }

  static String? _normaliseEtag(String? etag) {
    if (etag == null) return null;
    final stripped = etag.replaceAll('"', '').trim();
    return stripped.isEmpty ? null : stripped;
  }

  static String _trimSlash(String path) =>
      path.endsWith('/') ? path.substring(0, path.length - 1) : path;
}
