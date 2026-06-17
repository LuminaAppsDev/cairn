import 'dart:io';
import 'dart:typed_data';

import 'package:cairn/src/sync/nextcloud_sync_service.dart';
import 'package:cairn/src/sync/nextcloud_sync_target.dart';
import 'package:cairn/src/sync/sync_journal.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

/// In-memory [NextcloudSyncTarget]: records uploads and synthesises a WebDAV
/// listing from the set of known remote paths so the conflict scan can walk it.
class _FakeTarget implements NextcloudSyncTarget {
  final Map<String, Uint8List> puts = {};
  final Set<String> extraRemote = {};
  bool failPut = false;

  Set<String> get _all => {...puts.keys, ...extraRemote};

  @override
  Future<String?> putFile({
    required String remotePath,
    required Uint8List bytes,
  }) async {
    if (failPut) throw const NextcloudSyncException('offline');
    puts[remotePath] = bytes;
    return 'etag-${puts.length}';
  }

  @override
  Future<List<RemoteResource>> list(String remoteDir) async {
    final prefix = '$remoteDir/';
    final collections = <String>{};
    final files = <String>{};
    for (final path in _all) {
      if (!path.startsWith(prefix)) continue;
      final rest = path.substring(prefix.length);
      final slash = rest.indexOf('/');
      if (slash < 0) {
        files.add(rest);
      } else {
        collections.add(rest.substring(0, slash));
      }
    }
    return [
      for (final c in collections)
        RemoteResource(path: '$remoteDir/$c', isCollection: true),
      for (final f in files)
        RemoteResource(path: '$remoteDir/$f', isCollection: false),
    ];
  }

  @override
  Future<Uint8List> getFile(String remotePath, {int? maxBytes}) async {
    final bytes = puts[remotePath];
    if (bytes == null) throw NextcloudNotFoundException(remotePath);
    return bytes;
  }
}

void main() {
  late Directory cairnDir;
  late Directory journalDir;
  late JsonSyncJournalStore journalStore;
  late _FakeTarget target;

  setUp(() {
    cairnDir = Directory.systemTemp.createTempSync('cairn_sync_test');
    journalDir = Directory.systemTemp.createTempSync('cairn_sync_journal');
    journalStore = JsonSyncJournalStore(
      file: File(p.join(journalDir.path, 'journal.json')),
    );
    target = _FakeTarget();
  });
  tearDown(() {
    cairnDir.deleteSync(recursive: true);
    journalDir.deleteSync(recursive: true);
  });

  void writeFile(String relative, String content) {
    final file = File(
      p.join(cairnDir.path, relative.replaceAll('/', p.separator)),
    );
    file.parent.createSync(recursive: true);
    file.writeAsStringSync(content);
  }

  NextcloudSyncService service() => NextcloudSyncService(
    target: target,
    localRoot: cairnDir,
    journalStore: journalStore,
  );

  test('first push uploads every shard and the manifest', () async {
    writeFile('manifest.json', '{}');
    writeFile('steps/2026/2026-06-14.jsonl', '{"a":1}\n');
    writeFile('heart-rate/2026/2026-06-14.jsonl', '{"b":2}\n');

    final report = await service().push();

    expect(report.pushed, hasLength(3));
    expect(
      target.puts.keys,
      containsAll(<String>[
        'Cairn/manifest.json',
        'Cairn/steps/2026/2026-06-14.jsonl',
        'Cairn/heart-rate/2026/2026-06-14.jsonl',
      ]),
    );
    expect(report.skipped, 0);
  });

  test('second push re-sends only the grown shard plus the manifest', () async {
    writeFile('manifest.json', '{}');
    writeFile('steps/2026/2026-06-14.jsonl', '{"a":1}\n');
    writeFile('heart-rate/2026/2026-06-14.jsonl', '{"b":2}\n');
    await service().push();

    // Append a line to the steps shard (size grows); leave heart-rate alone.
    writeFile('steps/2026/2026-06-14.jsonl', '{"a":1}\n{"a":2}\n');
    final report = await service().push();

    expect(
      report.pushed,
      containsAll(<String>[
        'Cairn/manifest.json',
        'Cairn/steps/2026/2026-06-14.jsonl',
      ]),
    );
    expect(
      report.pushed,
      isNot(contains('Cairn/heart-rate/2026/2026-06-14.jsonl')),
    );
    expect(report.skipped, 1);
  });

  test('profile.json is always pushed (additive synced file)', () async {
    writeFile('manifest.json', '{}');
    writeFile('profile.json', '{"height":{"value":178}}');
    final first = await service().push();
    expect(first.pushed, contains('Cairn/profile.json'));

    // Re-edit to the same byte length; it must still re-push (rewritten in
    // place, like the manifest), not be size-skipped.
    writeFile('profile.json', '{"height":{"value":179}}');
    final second = await service().push();
    expect(second.pushed, contains('Cairn/profile.json'));
  });

  test('a non-allowlisted file is not pushed', () async {
    writeFile('manifest.json', '{}');
    writeFile('notes.txt', 'scratch');
    final report = await service().push();
    expect(report.pushed, isNot(contains('Cairn/notes.txt')));
  });

  test('journal persists pushed state across runs', () async {
    writeFile('manifest.json', '{}');
    writeFile('steps/2026/2026-06-14.jsonl', '{"a":1}\n');
    await service().push();

    final journal = await journalStore.read();
    expect(journal.files['Cairn/steps/2026/2026-06-14.jsonl'], isNotNull);
    expect(journal.files['Cairn/steps/2026/2026-06-14.jsonl']!.etag, isNotNull);
  });

  test('conflict copies are surfaced, not merged', () async {
    writeFile('manifest.json', '{}');
    writeFile('steps/2026/2026-06-14.jsonl', '{"a":1}\n');
    const conflict =
        'Cairn/steps/2026/2026-06-14 (conflicted copy 2026-06-15).jsonl';
    target.extraRemote.add(conflict);

    final report = await service().push();

    expect(report.conflicts, [conflict]);
    expect(report.hasConflicts, isTrue);
  });

  test('an upload failure throws, leaving files unrecorded', () async {
    writeFile('manifest.json', '{}');
    writeFile('steps/2026/2026-06-14.jsonl', '{"a":1}\n');
    target.failPut = true;

    await expectLater(
      service().push(),
      throwsA(isA<NextcloudSyncException>()),
    );

    final journal = await journalStore.read();
    expect(journal.files, isEmpty);
  });
}
