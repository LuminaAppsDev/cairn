import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:cairn/src/profile/profile.dart';
import 'package:cairn/src/profile/profile_store.dart';
import 'package:cairn/src/profile/profile_sync.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late Directory dir;

  setUp(() => dir = Directory.systemTemp.createTempSync('cairn_profilesync'));
  tearDown(() => dir.deleteSync(recursive: true));

  JsonProfileStore storeStampedAt(DateTime when) =>
      JsonProfileStore(root: dir, clock: () => when);

  Uint8List remoteBytes(Profile profile, DateTime updatedAt) =>
      Uint8List.fromList(
        utf8.encode(jsonEncode(profile.toJson(updatedAt: updatedAt))),
      );

  ProfileSyncService service(JsonProfileStore store, Uint8List? remote) =>
      ProfileSyncService(store: store, download: () async => remote);

  test(
    'adopts the remote profile on a fresh install (no local file)',
    () async {
      final store = storeStampedAt(DateTime(2026, 6, 17));
      final remote = remoteBytes(
        Profile(heightCm: 178, dateOfBirth: DateTime(1988, 3, 14)),
        DateTime(2026, 6, 10),
      );
      final pulled = await service(store, remote).pull();
      expect(pulled?.heightCm, 178);
      expect(pulled?.dateOfBirth, DateTime(1988, 3, 14));
      expect((await store.read()).heightCm, 178); // written to disk
    },
  );

  test('adopts when the remote is newer than the local profile', () async {
    await storeStampedAt(
      DateTime(2026, 6, 2),
    ).write(const Profile(heightCm: 80));
    final remote = remoteBytes(
      const Profile(heightCm: 178),
      DateTime(2026, 6, 10),
    );
    final pulled = await service(
      storeStampedAt(DateTime(2026, 6, 2)),
      remote,
    ).pull();
    expect(pulled?.heightCm, 178);
  });

  test('keeps the local profile when it is newer than the remote', () async {
    await storeStampedAt(
      DateTime(2026, 6, 17),
    ).write(const Profile(heightCm: 80));
    final remote = remoteBytes(
      const Profile(heightCm: 178),
      DateTime(2026, 6, 10),
    );
    final store = storeStampedAt(DateTime(2026, 6, 17));
    expect(await service(store, remote).pull(), isNull);
    expect((await store.read()).heightCm, 80); // local untouched
  });

  test('does nothing when no remote profile exists', () async {
    final store = storeStampedAt(DateTime(2026, 6, 17));
    expect(await service(store, null).pull(), isNull);
  });

  test('ignores a malformed remote, keeping the local profile', () async {
    await storeStampedAt(
      DateTime(2026, 6, 2),
    ).write(const Profile(heightCm: 80));
    final store = storeStampedAt(DateTime(2026, 6, 2));
    final garbage = Uint8List.fromList(utf8.encode('not json{'));
    expect(await service(store, garbage).pull(), isNull);
    expect((await store.read()).heightCm, 80);
  });

  test(
    'a remote without a timestamp cannot displace a local profile',
    () async {
      await storeStampedAt(
        DateTime(2026, 6, 2),
      ).write(const Profile(heightCm: 80));
      final store = storeStampedAt(DateTime(2026, 6, 2));
      final noTimestamp = Uint8List.fromList(
        utf8.encode(
          jsonEncode({
            'height': {'value': 200, 'unit': 'cm'},
          }),
        ),
      );
      expect(await service(store, noTimestamp).pull(), isNull);
      expect((await store.read()).heightCm, 80);
    },
  );
}
