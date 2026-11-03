import 'dart:convert';
import 'dart:io';

import 'package:cairn/src/storage/atomic_file.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

/// Persists the user's chosen app language as a device-local preference.
///
/// This is UI state, **not** health data: it lives under the app-support
/// directory, outside the synced `/Cairn/` tree, and is never uploaded to
/// Nextcloud. A missing or corrupt file means "follow the system locale".
/// Writes are atomic (temp file + rename).
final class LocaleStore {
  /// Creates a store backed by [file].
  LocaleStore({required this.file});

  /// Resolves the prefs file at `<app-support>/cairn/preferences.json`.
  static Future<LocaleStore> appSupport() async {
    final support = await getApplicationSupportDirectory();
    return LocaleStore(
      file: File(p.join(support.path, 'cairn', 'preferences.json')),
    );
  }

  /// The preferences file (kept out of the synced `/Cairn/` tree).
  final File file;

  /// Reads the stored language code (e.g. `de`), or `null` to follow the
  /// system locale (also returned for a missing or corrupt file).
  Future<String?> read() async {
    try {
      final decoded = jsonDecode(await file.readAsString());
      if (decoded is Map<String, Object?>) {
        final code = decoded['locale'];
        if (code is String && code.isNotEmpty) return code;
      }
    } on FormatException {
      // Corrupt prefs → follow the system locale.
    } on FileSystemException {
      // Missing file (or it vanished mid-read) → follow the system locale.
    }
    return null;
  }

  /// Writes [languageCode] atomically; `null` clears it (follow the system).
  Future<void> write(String? languageCode) async {
    await file.parent.create(recursive: true);
    final json = const JsonEncoder.withIndent('  ').convert(<String, Object?>{
      'locale': ?languageCode,
    });
    await writeFileAtomically(file, json);
  }
}
