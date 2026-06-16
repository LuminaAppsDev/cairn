import 'dart:io';

import 'package:cairn/src/sync/http_nextcloud_auth.dart';
import 'package:cairn/src/sync/nextcloud_auth.dart';
import 'package:cairn/src/sync/nextcloud_sync_target.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  final host = Uri.parse('https://cloud.example.com');

  LoginFlowSession session() => LoginFlowSession(
    loginUrl: Uri.parse('https://cloud.example.com/login/flow/abc'),
    pollToken: 'PT',
    pollEndpoint: Uri.parse('https://cloud.example.com/login/v2/poll'),
  );

  test('begin posts to login/v2 and parses the session', () async {
    late http.Request seen;
    final auth = HttpNextcloudAuth(
      client: MockClient((request) async {
        seen = request;
        return http.Response(
          '{"poll":{"token":"PT","endpoint":'
          '"https://cloud.example.com/login/v2/poll"},'
          '"login":"https://cloud.example.com/login/flow/abc"}',
          200,
        );
      }),
    );

    final result = await auth.begin(host);

    expect(seen.method, 'POST');
    expect(seen.url.path, '/index.php/login/v2');
    expect(seen.headers['User-Agent'], 'Cairn');
    expect(result.pollToken, 'PT');
    expect(
      result.pollEndpoint,
      Uri.parse('https://cloud.example.com/login/v2/poll'),
    );
    expect(result.loginUrl.path, '/login/flow/abc');
  });

  test('begin rejects a non-https host', () async {
    final auth = HttpNextcloudAuth(
      client: MockClient((_) async => http.Response('', 200)),
    );
    expect(
      () => auth.begin(Uri.parse('http://cloud.example.com')),
      throwsA(isA<NextcloudSyncException>()),
    );
  });

  test('begin rejects a poll endpoint on a foreign host', () async {
    final auth = HttpNextcloudAuth(
      client: MockClient(
        (_) async => http.Response(
          '{"poll":{"token":"PT","endpoint":'
          '"https://evil.example.net/poll"},'
          '"login":"https://cloud.example.com/flow/abc"}',
          200,
        ),
      ),
    );
    expect(() => auth.begin(host), throwsA(isA<NextcloudSyncException>()));
  });

  test('begin rejects a non-https login URL', () async {
    final auth = HttpNextcloudAuth(
      client: MockClient(
        (_) async => http.Response(
          '{"poll":{"token":"PT","endpoint":'
          '"https://cloud.example.com/poll"},'
          '"login":"javascript:alert(1)"}',
          200,
        ),
      ),
    );
    expect(() => auth.begin(host), throwsA(isA<NextcloudSyncException>()));
  });

  test('begin accepts a www sub-domain of the typed apex host', () async {
    final auth = HttpNextcloudAuth(
      client: MockClient(
        (_) async => http.Response(
          '{"poll":{"token":"PT","endpoint":'
          '"https://www.cloud.example.com/poll"},'
          '"login":"https://www.cloud.example.com/flow/abc"}',
          200,
        ),
      ),
    );
    final result = await auth.begin(host);
    expect(result.pollEndpoint.host, 'www.cloud.example.com');
  });

  test('begin rejects a parent domain of the typed host', () async {
    // Server tries to redirect the poll token up to example.com when the user
    // typed cloud.example.com — a possible attacker-controlled apex.
    final auth = HttpNextcloudAuth(
      client: MockClient(
        (_) async => http.Response(
          '{"poll":{"token":"PT","endpoint":'
          '"https://example.com/poll"},'
          '"login":"https://example.com/flow/abc"}',
          200,
        ),
      ),
    );
    expect(() => auth.begin(host), throwsA(isA<NextcloudSyncException>()));
  });

  test('poll wraps a network/DNS failure as a retryable error', () async {
    final auth = HttpNextcloudAuth(
      client: MockClient(
        (_) async => throw const SocketException('Failed host lookup'),
      ),
    );
    await expectLater(
      auth.poll(session()),
      throwsA(
        isA<NextcloudSyncException>().having(
          (e) => e.retryable,
          'retryable',
          isTrue,
        ),
      ),
    );
  });

  test('poll keeps polling on a 3xx redirect (reverse proxy)', () async {
    final auth = HttpNextcloudAuth(
      client: MockClient(
        (_) async =>
            http.Response('', 302, headers: {'location': '/elsewhere'}),
      ),
    );
    expect(await auth.poll(session()), isNull);
  });

  test('poll returns credentials on 200', () async {
    final auth = HttpNextcloudAuth(
      client: MockClient((request) async {
        expect(request.url.path, '/login/v2/poll');
        expect(request.body, 'token=PT');
        return http.Response(
          '{"server":"https://cloud.example.com",'
          '"loginName":"alice","appPassword":"app-pw"}',
          200,
        );
      }),
    );

    final creds = await auth.poll(session());

    expect(creds, isNotNull);
    expect(creds!.loginName, 'alice');
    expect(creds.appPassword, 'app-pw');
    expect(creds.server, Uri.parse('https://cloud.example.com'));
  });

  test('poll returns null while still pending (404)', () async {
    final auth = HttpNextcloudAuth(
      client: MockClient((_) async => http.Response('', 404)),
    );
    expect(await auth.poll(session()), isNull);
  });

  test('poll throws on an unexpected status', () async {
    final auth = HttpNextcloudAuth(
      client: MockClient((_) async => http.Response('', 500)),
    );
    expect(
      () => auth.poll(session()),
      throwsA(isA<NextcloudSyncException>()),
    );
  });
}
