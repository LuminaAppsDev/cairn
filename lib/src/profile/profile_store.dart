import 'dart:convert';
import 'dart:io';

import 'package:cairn/src/profile/profile.dart';
import 'package:path/path.dart' as p;

/// Reads and writes the user [Profile] as `/Cairn/profile.json`.
///
/// Lives under the synced cache [root] so the existing push engine carries it
/// to Nextcloud (DESIGN.md §6). Writes are atomic (temp file + rename), and a
/// missing or corrupt file reads back as an empty profile.
final class JsonProfileStore {
  /// Creates a store under [root] (the `/Cairn` directory — e.g.
  /// `JsonlOmhFileStore.root`). [clock] is injectable for deterministic tests.
  JsonProfileStore({required this.root, DateTime Function()? clock})
    : _now = clock ?? DateTime.now;

  /// The `/Cairn` directory the profile is stored under.
  final Directory root;
  final DateTime Function() _now;

  File get _file => File(p.join(root.path, 'profile.json'));

  /// Reads the profile, returning an empty one if it is missing or corrupt.
  Future<Profile> read() async {
    final file = _file;
    if (!file.existsSync()) return Profile.empty();
    try {
      final decoded = jsonDecode(await file.readAsString());
      if (decoded is Map<String, Object?>) return Profile.fromJson(decoded);
    } on FormatException {
      // Corrupt profile → treat as empty rather than crash.
    } on FileSystemException {
      // Vanished between the check and the read → treat as empty.
    }
    return Profile.empty();
  }

  /// The `updated_date_time` recorded in the local profile file, or `null` if
  /// it is missing, corrupt, or unstamped. Used to reconcile a pulled remote
  /// profile last-write-wins (a missing local file always loses).
  Future<DateTime?> updatedAt() async {
    final file = _file;
    if (!file.existsSync()) return null;
    try {
      final decoded = jsonDecode(await file.readAsString());
      if (decoded is Map<String, Object?>) {
        final value = decoded['updated_date_time'];
        if (value is String) return DateTime.tryParse(value);
      }
    } on FormatException {
      // Corrupt → treat as no timestamp (local loses to a valid remote).
    } on FileSystemException {
      // Vanished between the check and the read → no timestamp.
    }
    return null;
  }

  /// Writes [profile] atomically (temp file + rename).
  Future<void> write(Profile profile) async {
    await root.create(recursive: true);
    final tmp = File('${_file.path}.tmp');
    final json = const JsonEncoder.withIndent(
      '  ',
    ).convert(profile.toJson(updatedAt: _now()));
    await tmp.writeAsString(json, flush: true);
    await tmp.rename(_file.path);
  }

  /// Writes raw profile JSON [bytes] verbatim (atomic temp + rename), without
  /// re-stamping. Used to adopt a remote profile pulled from Nextcloud so that
  /// last-write-wins compares true edit times rather than the pull time.
  Future<void> writeRaw(List<int> bytes) async {
    await root.create(recursive: true);
    final tmp = File('${_file.path}.tmp');
    await tmp.writeAsBytes(bytes, flush: true);
    await tmp.rename(_file.path);
  }
}
