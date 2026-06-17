import 'dart:io';

import 'package:cairn/src/sync/nextcloud_sync_target.dart';
import 'package:cairn/src/sync/sync_journal.dart';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;

/// Substring Nextcloud puts in the name of a server-side conflict copy, e.g.
/// `steps (conflicted copy 2026-06-15 142601).jsonl`. Matched case-insensitive.
const String _conflictMarker = '(conflicted copy';

/// Recursion cap for the remote conflict scan. The Cairn tree is only
/// metric/year/day deep; this bounds a hostile or pathological server.
const int _maxScanDepth = 8;

/// Outcome of one [NextcloudSyncService.push] run (DESIGN.md §6).
@immutable
class SyncReport {
  /// Creates a sync report.
  const SyncReport({
    required this.pushed,
    required this.skipped,
    required this.conflicts,
    required this.errors,
  });

  /// Remote paths uploaded this run.
  final List<String> pushed;

  /// Number of local files already up to date (not re-uploaded).
  final int skipped;

  /// Remote paths of detected `(conflicted copy)` files — surfaced, never
  /// merged (DESIGN.md §6).
  final List<String> conflicts;

  /// Human-readable non-fatal problems (e.g. the conflict scan failed but the
  /// upload succeeded).
  final List<String> errors;

  /// Whether any conflict copies were found.
  bool get hasConflicts => conflicts.isNotEmpty;
}

/// Pushes the local `/Cairn/` tree to Nextcloud and surfaces conflict copies
/// (DESIGN.md §6, §9 write path).
///
/// Push only: offline appends accumulate locally and upload on the next run;
/// remote→local pull-merge is deferred to the multi-device phase (§8). A
/// device-local [SyncJournal] records the size+ETag of each pushed file, so
/// only changed shards are re-sent. Shards are append-only, so a size delta is
/// a sufficient change signal; `manifest.json` is rewritten in place and so is
/// always re-sent. Uploads are last-write-wins.
final class NextcloudSyncService {
  /// Creates a sync service. [localRoot] is the local `/Cairn` directory (e.g.
  /// `JsonlOmhFileStore.root`); [remoteRoot] is its path under the account's
  /// WebDAV root.
  NextcloudSyncService({
    required this.target,
    required this.localRoot,
    required this.journalStore,
    this.remoteRoot = 'Cairn',
  });

  /// The remote endpoint files are pushed to.
  final NextcloudSyncTarget target;

  /// The local `/Cairn` directory whose files are pushed.
  final Directory localRoot;

  /// Persists the per-file push journal (device-local, never synced).
  final JsonSyncJournalStore journalStore;

  /// The collection under the WebDAV root the tree is mirrored into.
  final String remoteRoot;

  /// Pushes every new or changed local file, then scans the remote tree for
  /// conflict copies. Throws if an upload fails (e.g. offline); files already
  /// uploaded stay recorded so the next run resumes.
  Future<SyncReport> push() async {
    var journal = await journalStore.read();
    final pushed = <String>[];
    var skipped = 0;

    try {
      for (final file in _localFiles()) {
        final remotePath = _remotePathFor(file);
        final size = file.lengthSync();
        if (!_needsPush(remotePath, size, journal)) {
          skipped++;
          continue;
        }
        final etag = await target.putFile(
          remotePath: remotePath,
          bytes: await file.readAsBytes(),
        );
        journal = journal.withEntry(
          remotePath,
          RemoteFileState(size: size, etag: etag),
        );
        pushed.add(remotePath);
      }
    } finally {
      // Persist progress even if an upload threw, so the next run resumes
      // instead of re-sending everything. A journal-write failure must not
      // mask the upload error that brought us here, so swallow it.
      try {
        await journalStore.write(journal);
      } on Object catch (_) {
        // Non-fatal: the original error (if any) propagates; a missing
        // journal just means the next run re-pushes (idempotent).
      }
    }

    final errors = <String>[];
    final conflicts = await _scanConflicts(errors);
    return SyncReport(
      pushed: pushed,
      skipped: skipped,
      conflicts: conflicts,
      errors: errors,
    );
  }

  /// `manifest.json` and `profile.json` are rewritten in place (size may not
  /// change on an edit) so they are always pushed; an append-only shard is
  /// pushed only when its size grew.
  bool _needsPush(String remotePath, int size, SyncJournal journal) {
    final name = p.basename(remotePath);
    if (name == 'manifest.json' || name == 'profile.json') return true;
    final state = journal.files[remotePath];
    return state == null || state.size != size;
  }

  Iterable<File> _localFiles() sync* {
    if (!localRoot.existsSync()) return;
    // followLinks: false so a planted symlink can't smuggle a file from
    // outside the cache into the upload set.
    final entities = localRoot.listSync(recursive: true, followLinks: false);
    for (final entity in entities) {
      if (entity is! File) continue;
      final name = p.basename(entity.path);
      if (name.endsWith('.jsonl') ||
          name == 'manifest.json' ||
          name == 'profile.json') {
        yield entity;
      }
    }
  }

  String _remotePathFor(File file) {
    final segments = p.split(p.relative(file.path, from: localRoot.path));
    // Defence in depth: a file resolving outside the root would produce `..`
    // segments and a traversing remote path — refuse rather than upload it.
    if (segments.contains('..')) {
      throw NextcloudSyncException(
        'Refusing to sync path outside the cache: '
        '${file.path}',
      );
    }
    return [remoteRoot, ...segments].join('/');
  }

  /// Recursively lists the remote tree and collects conflict copies. A failure
  /// here is non-fatal — the upload already succeeded — so it is reported in
  /// [errors] rather than thrown.
  Future<List<String>> _scanConflicts(List<String> errors) async {
    final conflicts = <String>[];
    try {
      await _scanDir(remoteRoot, conflicts);
    } on NextcloudSyncException catch (error) {
      errors.add('conflict scan: ${error.message}');
    }
    return conflicts;
  }

  Future<void> _scanDir(
    String remoteDir,
    List<String> conflicts, [
    int depth = 0,
  ]) async {
    // The Cairn tree is metric/year/day (depth 3); cap recursion so a
    // hostile server can't drive it into a stack overflow.
    if (depth > _maxScanDepth) {
      throw const NextcloudSyncException('Remote tree too deep to scan');
    }
    for (final child in await target.list(remoteDir)) {
      final childPath = '$remoteDir/${child.name}';
      if (child.isCollection) {
        await _scanDir(childPath, conflicts, depth + 1);
      } else if (child.name.toLowerCase().contains(_conflictMarker)) {
        conflicts.add(childPath);
      }
    }
  }
}
