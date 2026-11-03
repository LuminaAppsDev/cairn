import 'dart:io';
import 'dart:math';

final Random _random = Random();

/// Matches only the temp files [writeFileAtomically] creates, so a sweep never
/// touches anyone else's `.tmp`.
final RegExp _ownTemp = RegExp(r'\.\d+-[0-9a-f]+\.tmp$');

/// Writes [contents] to [target] atomically: into a temp file next to it, then
/// renamed over it, so a reader — or a crash — never sees a partial file.
///
/// The temp name is unique per write, not a fixed `<name>.tmp`: two writers
/// racing on one target (the UI and the background-sync isolate) then each
/// rename a complete file of their own, instead of one renaming the other's
/// half-written temp into place — the last rename wins, whole. Temp files are
/// never uploaded (sync only takes `*.jsonl`, `manifest.json`, `profile.json`);
/// one a crash leaves behind is removed by [sweepStaleTempFiles].
Future<void> writeFileAtomically(File target, String contents) =>
    _atomically(target, (tmp) => tmp.writeAsString(contents, flush: true));

/// [writeFileAtomically] for raw [bytes].
Future<void> writeBytesAtomically(File target, List<int> bytes) =>
    _atomically(target, (tmp) => tmp.writeAsBytes(bytes, flush: true));

Future<void> _atomically(
  File target,
  Future<File> Function(File tmp) write,
) async {
  final suffix =
      '${DateTime.now().microsecondsSinceEpoch}-'
      '${_random.nextInt(1 << 32).toRadixString(16)}';
  final tmp = File('${target.path}.$suffix.tmp');
  try {
    await write(tmp);
    await tmp.rename(target.path);
  } on Object {
    try {
      await tmp.delete();
    } on FileSystemException {
      // Never created, or already gone — nothing to clean up.
    }
    rethrow;
  }
}

/// Deletes the temp files [writeFileAtomically] left in [dir] (and below, if
/// [recursive]) when the process died mid-write. Only those older than
/// [olderThan]: a young one may be a write in flight in the other isolate.
/// Best-effort — a failure here never matters, so it is swallowed.
Future<void> sweepStaleTempFiles(
  Directory dir, {
  bool recursive = true,
  Duration olderThan = const Duration(hours: 1),
}) async {
  final cutoff = DateTime.now().subtract(olderThan);
  try {
    // Never follow a link out of the directory.
    await for (final entity in dir.list(
      recursive: recursive,
      followLinks: false,
    )) {
      if (entity is! File || !_ownTemp.hasMatch(entity.path)) continue;
      try {
        if (entity.lastModifiedSync().isBefore(cutoff)) {
          await entity.delete();
        }
      } on FileSystemException {
        // Vanished meanwhile — fine.
      }
    }
  } on FileSystemException {
    // Directory missing or unreadable — nothing to sweep.
  }
}
