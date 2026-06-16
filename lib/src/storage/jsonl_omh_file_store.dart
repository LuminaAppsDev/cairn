import 'dart:convert';
import 'dart:io';

import 'package:cairn/src/health/health_metric.dart';
import 'package:cairn/src/storage/manifest.dart';
import 'package:cairn/src/storage/omh_file_store.dart';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

/// [OmhFileStore] backed by append-only JSON-Lines shards under [root] plus a
/// `manifest.json` (DESIGN.md §5.3–5.4).
///
/// Shards are append-only, so a crash can only ever leave a partial trailing
/// line (which [readRange] skips) — existing data is never corrupted. The
/// manifest is rewritten atomically (temp file + rename).
final class JsonlOmhFileStore implements OmhFileStore {
  /// Creates a store rooted at [root] (the `/Cairn` directory). [clock] is
  /// injectable for deterministic tests.
  JsonlOmhFileStore({required this.root, DateTime Function()? clock})
    : _now = clock ?? DateTime.now;

  /// Resolves the store under the app documents directory (`…/Cairn`).
  static Future<JsonlOmhFileStore> appDocuments({
    DateTime Function()? clock,
  }) async {
    final docs = await getApplicationDocumentsDirectory();
    return JsonlOmhFileStore(
      root: Directory(p.join(docs.path, 'Cairn')),
      clock: clock,
    );
  }

  /// The `/Cairn` directory this store reads and writes under.
  final Directory root;
  final DateTime Function() _now;
  Future<void> _manifestLock = Future<void>.value();

  /// Parse reads above this many characters on a background isolate
  /// (DESIGN.md §13).
  static const int _isolateParseThresholdChars = 32 * 1024;

  @override
  Future<void> append({
    required HealthMetric metric,
    required DateTime day,
    required List<Map<String, Object?>> dataPoints,
  }) async {
    if (dataPoints.isEmpty) return;
    final file = _shardFile(metric, day);
    await file.parent.create(recursive: true);
    final lines = dataPoints.map(jsonEncode).join('\n');
    await file.writeAsString('$lines\n', mode: FileMode.append, flush: true);
  }

  @override
  Future<List<Map<String, Object?>>> readRange({
    required HealthMetric metric,
    required DateTime from,
    required DateTime to,
  }) async {
    final buffer = StringBuffer();
    final last = _dateOnly(to);
    for (
      var day = _dateOnly(from);
      !day.isAfter(last);
      day = day.add(const Duration(days: 1))
    ) {
      final file = _shardFile(metric, day);
      if (!file.existsSync()) continue;
      try {
        buffer.writeln(await file.readAsString());
      } on FileSystemException {
        // Shard vanished between the check and the read (e.g. cache
        // eviction) → treat as absent.
      }
    }
    final content = buffer.toString();
    if (content.trim().isEmpty) return [];
    if (content.length >= _isolateParseThresholdChars) {
      return compute(_parseJsonl, content);
    }
    return _parseJsonl(content);
  }

  @override
  Future<DateTime?> lastSyncAnchor(HealthMetric metric) async {
    final manifest = await _readManifest();
    return manifest.syncAnchors[metric];
  }

  @override
  Future<void> setSyncAnchor(HealthMetric metric, DateTime anchor) {
    // Serialise manifest read-modify-write so concurrent anchor updates can't
    // clobber each other.
    final next = _manifestLock.then((_) async {
      final manifest = (await _readManifest()).withAnchor(metric, anchor);
      await _writeManifest(manifest);
    });
    _manifestLock = next.catchError((_) {});
    return next;
  }

  File _shardFile(HealthMetric metric, DateTime day) {
    final d = _dateOnly(day);
    final year = _pad(d.year, 4);
    final name = '$year-${_pad(d.month)}-${_pad(d.day)}.jsonl';
    return File(p.join(root.path, metric.slug, year, name));
  }

  File get _manifestFile => File(p.join(root.path, 'manifest.json'));

  Future<Manifest> _readManifest() async {
    final file = _manifestFile;
    if (!file.existsSync()) return Manifest.empty();
    try {
      final decoded = jsonDecode(await file.readAsString());
      if (decoded is Map<String, dynamic>) {
        return Manifest.fromJson(Map<String, Object?>.from(decoded));
      }
    } on FormatException {
      // Corrupt manifest → start fresh rather than crash.
    } on FileSystemException {
      // Vanished between the check and the read → treat as empty.
    }
    return Manifest.empty();
  }

  Future<void> _writeManifest(Manifest manifest) async {
    await root.create(recursive: true);
    final tmp = File('${_manifestFile.path}.tmp');
    final json = const JsonEncoder.withIndent(
      '  ',
    ).convert(manifest.toJson(updatedAt: _now()));
    await tmp.writeAsString(json, flush: true);
    await tmp.rename(_manifestFile.path);
  }

  static DateTime _dateOnly(DateTime t) => DateTime(t.year, t.month, t.day);
  static String _pad(int value, [int width = 2]) =>
      value.toString().padLeft(width, '0');
}

/// Parses JSON-Lines [content], skipping any line that fails to parse (e.g. a
/// partial trailing line from a crashed append). Top-level so it can run under
/// [compute].
List<Map<String, Object?>> _parseJsonl(String content) {
  final out = <Map<String, Object?>>[];
  for (final line in const LineSplitter().convert(content)) {
    if (line.trim().isEmpty) continue;
    try {
      final decoded = jsonDecode(line);
      if (decoded is Map<String, dynamic>) {
        out.add(Map<String, Object?>.from(decoded));
      }
    } on FormatException {
      // Skip a malformed line.
    }
  }
  return out;
}
