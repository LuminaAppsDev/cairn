import 'dart:convert';
import 'dart:io';

import 'package:json_schema/json_schema.dart';
import 'package:path/path.dart' as p;

/// Loads the vendored OMH / IEEE 1752.1 JSON Schemas (and the Cairn-authored
/// `cairn:sleep-stage` schema) so tests can validate emitted datapoints
/// offline (DESIGN.md §13).
///
/// Each schema is *bundled* first: every `$ref` (external file or internal
/// pointer) is recursively inlined into a single ref-free document. The OMH /
/// IEEE schemas are acyclic, so full inlining is safe, and it sidesteps
/// `json_schema`'s sync ordering limitation with `definitions`-aliased external
/// refs. OMH and IEEE `$ref` pools are kept separate because their utility
/// filenames overlap (e.g. `descriptive-statistic-1.0.json`).
class OmhSchemas {
  new _(this._omhRefs, this._ieeeRefs);

  /// Loads every schema fixture from disk.
  factory load() => OmhSchemas._(
    _loadDir('test/fixtures/schemas/omh'),
    _loadDir('test/fixtures/schemas/ieee'),
  );

  final Map<String, Map<String, dynamic>> _omhRefs;
  final Map<String, Map<String, dynamic>> _ieeeRefs;

  /// `omh:heart-rate:1.0` body schema.
  late final JsonSchema heartRate = _fromFile(
    'test/fixtures/schemas/omh/heart-rate-1.0.json',
    _omhRefs,
  );

  /// `omh:step-count:3.0` body schema.
  late final JsonSchema stepCount = _fromFile(
    'test/fixtures/schemas/omh/step-count-3.0.json',
    _omhRefs,
  );

  /// `omh:body-weight:2.0` body schema.
  late final JsonSchema bodyWeight = _fromFile(
    'test/fixtures/schemas/omh/body-weight-2.0.json',
    _omhRefs,
  );

  /// IEEE 1752.1 `physical-activity:1.0` body schema.
  late final JsonSchema physicalActivity = _fromFile(
    'test/fixtures/schemas/ieee/physical-activity-1.0.json',
    _ieeeRefs,
  );

  /// IEEE 1752.1 `sleep-episode:1.0` body schema.
  late final JsonSchema sleepEpisode = _fromFile(
    'test/fixtures/schemas/ieee/sleep-episode-1.0.json',
    _ieeeRefs,
  );

  /// Cairn-authored `cairn:sleep-stage:1.0` body schema (self-contained).
  late final JsonSchema sleepStage = _fromFile(
    'lib/src/omh/schemas/cairn/sleep-stage-1.0.json',
    const {},
  );

  /// OMH datapoint header schema.
  late final JsonSchema header = _fromFile(
    'test/fixtures/schemas/omh/header-1.x.json',
    _omhRefs,
  );

  static Map<String, Map<String, dynamic>> _loadDir(String dir) {
    final out = <String, Map<String, dynamic>>{};
    for (final entity in Directory(dir).listSync()) {
      if (entity is File && entity.path.endsWith('.json')) {
        out[p.basename(entity.path)] =
            json.decode(entity.readAsStringSync()) as Map<String, dynamic>;
      }
    }
    return out;
  }

  static JsonSchema _fromFile(
    String path,
    Map<String, Map<String, dynamic>> refs,
  ) {
    final root =
        json.decode(File(path).readAsStringSync()) as Map<String, dynamic>;
    return JsonSchema.create(_bundle(root, refs));
  }

  /// Recursively inlines every `$ref` in [root] using [refs] (basename →
  /// schema), returning a ref-free schema document.
  static Map<String, dynamic> _bundle(
    Map<String, dynamic> root,
    Map<String, Map<String, dynamic>> refs,
  ) {
    Object? resolve(Object? node, Map<String, dynamic> doc, int depth) {
      if (depth > 96) {
        throw StateError(r'schema $ref nesting too deep (possible cycle)');
      }
      if (node is List<dynamic>) {
        return [for (final e in node) resolve(e, doc, depth + 1)];
      }
      if (node is Map<String, dynamic>) {
        final ref = node[r'$ref'];
        if (ref is String) {
          // A `$ref` object replaces its whole node (no siblings) in the OMH /
          // IEEE schemas, so sibling keys are intentionally not merged here.
          final hash = ref.indexOf('#');
          final file = hash < 0 ? ref : ref.substring(0, hash);
          final pointer = hash < 0 ? '' : ref.substring(hash + 1);
          final targetDoc = file.isEmpty
              ? doc
              : (refs[file.split('/').last] ??
                    (throw StateError('unresolved \$ref: $ref')));
          return resolve(_navigate(targetDoc, pointer), targetDoc, depth + 1);
        }
        return {
          for (final entry in node.entries)
            entry.key: resolve(entry.value, doc, depth + 1),
        };
      }
      return node;
    }

    return resolve(root, root, 0)! as Map<String, dynamic>;
  }

  /// Resolves a JSON Pointer [pointer] within [doc].
  static Object? _navigate(Map<String, dynamic> doc, String pointer) {
    Object? current = doc;
    for (final raw in pointer.split('/')) {
      if (raw.isEmpty) continue;
      final token = raw.replaceAll('~1', '/').replaceAll('~0', '~');
      if (current is Map<String, dynamic>) {
        current = current[token];
      } else if (current is List<dynamic>) {
        final index = int.tryParse(token);
        if (index == null || index < 0 || index >= current.length) return null;
        current = current[index];
      } else {
        return null;
      }
    }
    return current;
  }
}
