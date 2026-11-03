import 'dart:io';

import 'package:cairn/src/storage/atomic_file.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

void main() {
  late Directory dir;

  setUp(() => dir = Directory.systemTemp.createTempSync('cairn_atomic_test'));
  tearDown(() => dir.deleteSync(recursive: true));

  List<String> tempsIn(Directory d) => d
      .listSync()
      .map((e) => p.basename(e.path))
      .where((name) => name.endsWith('.tmp'))
      .toList();

  test('racing writers each land a whole file, never a torn one', () async {
    // The UI and background isolates writing the manifest at once: with a
    // shared temp path one could rename the other's half-written file.
    final target = File(p.join(dir.path, 'manifest.json'));
    final a = 'a' * 200000;
    final b = 'b' * 200000;

    await Future.wait([
      writeFileAtomically(target, a),
      writeFileAtomically(target, b),
    ]);

    expect(target.readAsStringSync(), anyOf(a, b));
    expect(tempsIn(dir), isEmpty);
  });

  test('a failed write leaves no temp file behind', () async {
    final target = File(p.join(dir.path, 'missing', 'manifest.json'));

    await expectLater(
      writeFileAtomically(target, '{}'),
      throwsA(isA<FileSystemException>()),
    );
    expect(tempsIn(dir), isEmpty);
  });

  test('the sweep removes only old temps of our own', () async {
    final old = DateTime.now().subtract(const Duration(hours: 2));
    File(p.join(dir.path, 'manifest.json.1700000000000000-ab12.tmp'))
      ..writeAsStringSync('x')
      ..setLastModifiedSync(old);
    File(p.join(dir.path, 'manifest.json.1700000000000001-cd34.tmp'))
        .writeAsStringSync('in flight');
    File(p.join(dir.path, 'someone-else.tmp'))
      ..writeAsStringSync('not ours')
      ..setLastModifiedSync(old);

    await sweepStaleTempFiles(dir);

    expect(
      tempsIn(dir),
      unorderedEquals([
        'manifest.json.1700000000000001-cd34.tmp',
        'someone-else.tmp',
      ]),
    );
  });
}
