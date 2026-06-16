import 'package:cairn/src/sync/flutter_secure_token_store.dart';
import 'package:cairn/src/sync/nextcloud_credentials.dart';
import 'package:cairn/src/sync/nextcloud_sync_target.dart';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';

/// Fake [FlutterSecureStorage] driven via `noSuchMethod` so the test does not
/// have to restate the plugin's full (option-laden) method signatures.
class _FakeStorage implements FlutterSecureStorage {
  _FakeStorage({this.corrupt = false, this.alwaysFail = false});

  final Map<String, String> store = {};

  /// One-shot corruption: the next write throws until a delete clears it.
  bool corrupt;

  /// Every read/write throws (an unrecoverable secure-store failure).
  final bool alwaysFail;

  int writes = 0;

  @override
  dynamic noSuchMethod(Invocation invocation) {
    final key = invocation.namedArguments[#key] as String?;
    switch (invocation.memberName) {
      case #write:
        writes++;
        if (alwaysFail || corrupt) {
          throw PlatformException(code: 'BadPaddingException');
        }
        final value = invocation.namedArguments[#value] as String?;
        if (value == null) {
          store.remove(key);
        } else {
          store[key!] = value;
        }
        return Future<void>.value();
      case #read:
        if (alwaysFail) throw PlatformException(code: 'KeyStoreException');
        return Future<String?>.value(store[key]);
      case #delete:
        if (alwaysFail) throw PlatformException(code: 'KeyStoreException');
        corrupt = false;
        store.remove(key);
        return Future<void>.value();
    }
    return super.noSuchMethod(invocation);
  }
}

void main() {
  final creds = NextcloudCredentials(
    server: Uri.parse('https://cloud.example.com'),
    loginName: 'alice',
    appPassword: 'pw',
  );

  test('write then read round-trips credentials', () async {
    final fake = _FakeStorage();
    final tokenStore = FlutterSecureTokenStore(storage: fake);

    await tokenStore.writeCredentials(creds);
    final read = await tokenStore.readCredentials();

    expect(read, isNotNull);
    expect(read!.loginName, 'alice');
    expect(read.server, Uri.parse('https://cloud.example.com'));
  });

  test('write recovers from a corrupt entry by delete + retry', () async {
    final fake = _FakeStorage(corrupt: true);
    final tokenStore = FlutterSecureTokenStore(storage: fake);

    await tokenStore.writeCredentials(creds); // must not throw

    expect(fake.writes, 2); // first throws, retry after delete succeeds
    expect(await tokenStore.readCredentials(), isNotNull);
  });

  test('an unrecoverable write surfaces a NextcloudSyncException', () async {
    final tokenStore = FlutterSecureTokenStore(
      storage: _FakeStorage(alwaysFail: true),
    );
    await expectLater(
      tokenStore.writeCredentials(creds),
      throwsA(isA<NextcloudSyncException>()),
    );
  });

  test('read returns null when the secure store is unreadable', () async {
    final tokenStore = FlutterSecureTokenStore(
      storage: _FakeStorage(alwaysFail: true),
    );
    expect(await tokenStore.readCredentials(), isNull);
  });

  test('delete swallows a secure-store failure', () async {
    final tokenStore = FlutterSecureTokenStore(
      storage: _FakeStorage(alwaysFail: true),
    );
    await expectLater(tokenStore.deleteCredentials(), completes);
  });
}
