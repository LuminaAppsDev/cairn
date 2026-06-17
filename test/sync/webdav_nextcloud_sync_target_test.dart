import 'dart:convert';
import 'dart:typed_data';

import 'package:cairn/src/sync/nextcloud_credentials.dart';
import 'package:cairn/src/sync/nextcloud_sync_target.dart';
import 'package:cairn/src/sync/webdav_nextcloud_sync_target.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

/// A PROPFIND multistatus listing `Cairn/` with one collection and one file
/// child, plus the directory's own (self) entry that must be excluded.
const String _multistatus = '''
<?xml version="1.0"?>
<d:multistatus xmlns:d="DAV:">
  <d:response>
    <d:href>/remote.php/dav/files/alice/Cairn/</d:href>
    <d:propstat><d:prop>
      <d:resourcetype><d:collection/></d:resourcetype>
    </d:prop><d:status>HTTP/1.1 200 OK</d:status></d:propstat>
  </d:response>
  <d:response>
    <d:href>/remote.php/dav/files/alice/Cairn/steps/</d:href>
    <d:propstat><d:prop>
      <d:resourcetype><d:collection/></d:resourcetype>
    </d:prop><d:status>HTTP/1.1 200 OK</d:status></d:propstat>
  </d:response>
  <d:response>
    <d:href>/remote.php/dav/files/alice/Cairn/manifest.json</d:href>
    <d:propstat><d:prop>
      <d:resourcetype/>
      <d:getetag>"file-etag"</d:getetag>
      <d:getcontentlength>42</d:getcontentlength>
    </d:prop><d:status>HTTP/1.1 200 OK</d:status></d:propstat>
  </d:response>
</d:multistatus>''';

void main() {
  final credentials = NextcloudCredentials(
    server: Uri.parse('https://cloud.example.com'),
    loginName: 'alice',
    appPassword: 'secret',
  );

  String basicFor(String user, String pw) =>
      'Basic ${base64Encode(utf8.encode('$user:$pw'))}';

  test('putFile creates parents then PUTs, returning the ETag', () async {
    final calls = <String>[];
    String? authHeader;
    String? putContentType;
    final target = WebDavNextcloudSyncTarget(
      credentials: credentials,
      client: MockClient((request) async {
        calls.add('${request.method} ${request.url.path}');
        authHeader = request.headers['authorization'];
        if (request.method == 'PUT') {
          putContentType = request.headers['content-type'];
          return http.Response('', 201, headers: {'etag': '"put-etag"'});
        }
        return http.Response('', 201); // MKCOL created
      }),
    );

    final etag = await target.putFile(
      remotePath: 'Cairn/steps/2026/2026-06-14.jsonl',
      bytes: Uint8List.fromList(utf8.encode('{"x":1}\n')),
    );

    expect(etag, 'put-etag');
    expect(authHeader, basicFor('alice', 'secret'));
    expect(putContentType, startsWith('application/x-ndjson'));
    expect(calls, [
      'MKCOL /remote.php/dav/files/alice/Cairn',
      'MKCOL /remote.php/dav/files/alice/Cairn/steps',
      'MKCOL /remote.php/dav/files/alice/Cairn/steps/2026',
      'PUT /remote.php/dav/files/alice/Cairn/steps/2026/2026-06-14.jsonl',
    ]);
  });

  test('putFile tolerates 405 on already-existing collections', () async {
    final target = WebDavNextcloudSyncTarget(
      credentials: credentials,
      client: MockClient((request) async {
        if (request.method == 'MKCOL') return http.Response('', 405);
        return http.Response('', 204);
      }),
    );
    final etag = await target.putFile(
      remotePath: 'Cairn/manifest.json',
      bytes: Uint8List.fromList([1, 2, 3]),
    );
    expect(etag, isNull); // 204, no etag header
  });

  test('list parses the multistatus, excluding the self entry', () async {
    final target = WebDavNextcloudSyncTarget(
      credentials: credentials,
      client: MockClient((request) async {
        expect(request.method, 'PROPFIND');
        expect(request.headers['depth'], '1');
        return http.Response(_multistatus, 207);
      }),
    );

    final resources = await target.list('Cairn');

    expect(resources.map((r) => r.name), ['steps', 'manifest.json']);
    final steps = resources.firstWhere((r) => r.name == 'steps');
    final manifest = resources.firstWhere((r) => r.name == 'manifest.json');
    expect(steps.isCollection, isTrue);
    expect(manifest.isCollection, isFalse);
    expect(manifest.etag, 'file-etag');
    expect(manifest.size, 42);
  });

  test('list returns empty on 404', () async {
    final target = WebDavNextcloudSyncTarget(
      credentials: credentials,
      client: MockClient((_) async => http.Response('', 404)),
    );
    expect(await target.list('Cairn/missing'), isEmpty);
  });

  test('getFile returns bytes on 200', () async {
    final target = WebDavNextcloudSyncTarget(
      credentials: credentials,
      client: MockClient(
        (_) async => http.Response.bytes([7, 8, 9], 200),
      ),
    );
    expect(await target.getFile('Cairn/manifest.json'), [7, 8, 9]);
  });

  test('getFile throws NextcloudNotFoundException on 404', () async {
    final target = WebDavNextcloudSyncTarget(
      credentials: credentials,
      client: MockClient((_) async => http.Response('', 404)),
    );
    expect(
      () => target.getFile('Cairn/missing.jsonl'),
      throwsA(isA<NextcloudNotFoundException>()),
    );
  });

  test('getFile aborts an over-limit body instead of buffering it', () async {
    final target = WebDavNextcloudSyncTarget(
      credentials: credentials,
      client: MockClient(
        (_) async => http.Response.bytes(List.filled(100, 0), 200),
      ),
    );
    expect(
      () => target.getFile('Cairn/profile.json', maxBytes: 10),
      throwsA(isA<NextcloudSyncException>()),
    );
  });
}
