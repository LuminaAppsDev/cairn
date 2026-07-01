import 'dart:io';
import 'dart:typed_data';

import 'package:cairn/src/sync/nextcloud_auth.dart';
import 'package:cairn/src/sync/nextcloud_credentials.dart';
import 'package:cairn/src/sync/nextcloud_sync_coordinator.dart';
import 'package:cairn/src/sync/nextcloud_sync_target.dart';
import 'package:cairn/src/sync/secure_token_store.dart';
import 'package:cairn/src/sync/sync_journal.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

class _FakeAuth implements NextcloudAuth {
  NextcloudCredentials? result;

  @override
  Future<LoginFlowSession> begin(Uri host) async => LoginFlowSession(
    loginUrl: host,
    pollToken: 't',
    pollEndpoint: host,
  );

  @override
  Future<NextcloudCredentials?> poll(LoginFlowSession session) async => result;
}

class _MemoryTokenStore implements SecureTokenStore {
  NextcloudCredentials? stored;

  @override
  Future<void> writeCredentials(NextcloudCredentials credentials) async =>
      stored = credentials;

  @override
  Future<NextcloudCredentials?> readCredentials() async => stored;

  @override
  Future<void> deleteCredentials() async => stored = null;
}

class _RecordingTarget implements NextcloudSyncTarget {
  final List<String> puts = [];

  @override
  Future<String?> putFile({
    required String remotePath,
    required Uint8List bytes,
  }) async {
    puts.add(remotePath);
    return 'etag';
  }

  @override
  Future<List<RemoteResource>> list(String remoteDir) async => const [];

  @override
  Future<Uint8List> getFile(String remotePath, {int? maxBytes}) async =>
      throw NextcloudNotFoundException(remotePath);
}

void main() {
  late Directory cairnDir;
  late Directory journalDir;
  late JsonSyncJournalStore journalStore;
  late _FakeAuth auth;
  late _MemoryTokenStore tokenStore;

  final creds = NextcloudCredentials(
    server: Uri.parse('https://cloud.example.com'),
    loginName: 'alice',
    appPassword: 'pw',
  );

  setUp(() {
    cairnDir = Directory.systemTemp.createTempSync('cairn_coord_test');
    journalDir = Directory.systemTemp.createTempSync('cairn_coord_journal');
    journalStore = JsonSyncJournalStore(
      file: File(p.join(journalDir.path, 'journal.json')),
    );
    auth = _FakeAuth();
    tokenStore = _MemoryTokenStore();
  });
  tearDown(() {
    cairnDir.deleteSync(recursive: true);
    journalDir.deleteSync(recursive: true);
  });

  NextcloudSyncCoordinator coordinator({SyncTargetFactory? factory}) =>
      NextcloudSyncCoordinator(
        auth: auth,
        tokenStore: tokenStore,
        localRoot: cairnDir,
        journalStore: journalStore,
        targetFactory: factory,
      );

  test('pollAndStore stores credentials once authorised', () async {
    auth.result = creds;
    final c = coordinator();

    final returned = await c.pollAndStore(await c.begin(creds.server));

    expect(returned, isNotNull);
    expect(tokenStore.stored, same(creds));
    expect(await c.isConnected(), isTrue);
  });

  test('pollAndStore returns null and stores nothing while pending', () async {
    auth.result = null;
    final c = coordinator();

    final returned = await c.pollAndStore(await c.begin(creds.server));

    expect(returned, isNull);
    expect(tokenStore.stored, isNull);
    expect(await c.isConnected(), isFalse);
  });

  test('syncNow builds a target from stored creds and pushes', () async {
    tokenStore.stored = creds;
    File(p.join(cairnDir.path, 'manifest.json')).writeAsStringSync('{}');
    final target = _RecordingTarget();
    final c = coordinator(factory: (_) => target);

    final report = await c.syncNow();

    expect(report.pushed, ['Cairn/manifest.json']);
    expect(target.puts, ['Cairn/manifest.json']);
  });

  test('syncNow throws a StateError when not connected', () async {
    final c = coordinator();
    await expectLater(c.syncNow(), throwsStateError);
  });

  test('disconnect clears stored credentials', () async {
    tokenStore.stored = creds;
    final c = coordinator();

    await c.disconnect();

    expect(tokenStore.stored, isNull);
    expect(await c.isConnected(), isFalse);
  });

  test('lastSyncedAt reads the instant from the journal', () async {
    final at = DateTime.utc(2026, 7, 1, 8);
    await journalStore.write(SyncJournal.empty().withSyncedAt(at));

    expect((await coordinator().lastSyncedAt())!.toUtc(), at);
  });

  test('lastSyncedAt is null when the device has never synced', () async {
    expect(await coordinator().lastSyncedAt(), isNull);
  });
}
