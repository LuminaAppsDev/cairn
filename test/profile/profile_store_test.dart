import 'dart:io';

import 'package:cairn/src/profile/profile.dart';
import 'package:cairn/src/profile/profile_store.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

void main() {
  late Directory root;
  late JsonProfileStore store;

  setUp(() {
    root = Directory.systemTemp.createTempSync('cairn_profile_test');
    store = JsonProfileStore(root: root, clock: () => DateTime(2026, 6, 17));
  });
  tearDown(() => root.deleteSync(recursive: true));

  test('read returns an empty profile when the file is missing', () async {
    final profile = await store.read();
    expect(profile.isEmpty, isTrue);
  });

  test('write then read round-trips height and date of birth', () async {
    await store.write(
      Profile(heightCm: 178, dateOfBirth: DateTime(1988, 3, 14)),
    );
    final profile = await store.read();
    expect(profile.heightCm, 178);
    expect(profile.dateOfBirth, DateTime(1988, 3, 14));
  });

  test('serialises DoB as a bare calendar date', () async {
    await store.write(Profile(dateOfBirth: DateTime(1988, 3, 14)));
    final raw = File(p.join(root.path, 'profile.json')).readAsStringSync();
    expect(raw, contains('"date_of_birth": "1988-03-14"'));
  });

  test('a partial profile (height only) round-trips', () async {
    await store.write(const Profile(heightCm: 180));
    final profile = await store.read();
    expect(profile.heightCm, 180);
    expect(profile.dateOfBirth, isNull);
  });

  test('writing a null height clears a previously stored one', () async {
    await store.write(const Profile(heightCm: 178));
    await store.write(const Profile()); // height cleared
    expect((await store.read()).heightCm, isNull);
  });

  test('a corrupt file reads back as empty', () async {
    File(p.join(root.path, 'profile.json'))
      ..createSync(recursive: true)
      ..writeAsStringSync('{not json');
    expect((await store.read()).isEmpty, isTrue);
  });

  test('write leaves no temp file behind', () async {
    await store.write(const Profile(heightCm: 178));
    final leftovers = root.listSync().whereType<File>().where(
      (f) => f.path.endsWith('.tmp'),
    );
    expect(leftovers, isEmpty);
  });

  group('ageYears', () {
    final profile = Profile(dateOfBirth: DateTime(1988, 3, 14));

    test('counts a birthday already passed this year', () {
      expect(profile.ageYears(DateTime(2026, 6, 17)), 38);
    });

    test('does not count a birthday still to come', () {
      expect(profile.ageYears(DateTime(2026, 2, 10)), 37); // before Mar 14
    });

    test('is null without a date of birth', () {
      expect(
        const Profile(heightCm: 178).ageYears(DateTime(2026, 6, 17)),
        isNull,
      );
    });
  });
}
