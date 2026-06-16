import 'dart:convert';

import 'package:cairn/src/sync/nextcloud_credentials.dart';
import 'package:cairn/src/sync/nextcloud_sync_target.dart';
import 'package:cairn/src/sync/secure_token_store.dart';
import 'package:flutter/services.dart' show PlatformException;
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// Secure-storage key the credential bundle is stored under.
const String _credentialsKey = 'nextcloud_credentials';

/// [SecureTokenStore] backed by `flutter_secure_storage` (Keychain on iOS,
/// Keystore-backed encrypted storage on Android) (DESIGN.md §6).
///
/// The platform Keystore/Keychain can throw [PlatformException] — most often
/// a decrypt failure (`BadPaddingException`) after an OS reinstall, a restored
/// backup, or an emulator snapshot/wipe loses the master key. Those are handled
/// rather than left to escape: a failed read is treated as "not connected", and
/// a failed write deletes the stale entry and retries once before surfacing a
/// typed [NextcloudSyncException] the UI can show.
final class FlutterSecureTokenStore implements SecureTokenStore {
  /// Creates a store. [storage] is injectable for tests; the default uses the
  /// platform-secure backend (Keychain / Android Keystore-backed ciphers).
  FlutterSecureTokenStore({FlutterSecureStorage? storage})
    : _storage = storage ?? const FlutterSecureStorage();

  final FlutterSecureStorage _storage;

  @override
  Future<void> writeCredentials(NextcloudCredentials credentials) async {
    final value = jsonEncode(credentials.toJson());
    try {
      await _storage.write(key: _credentialsKey, value: value);
    } on PlatformException {
      // A corrupt/un-decryptable entry can wedge writes; clearing it and
      // retrying once is the upstream-recommended recovery.
      try {
        await _storage.delete(key: _credentialsKey);
        await _storage.write(key: _credentialsKey, value: value);
      } on PlatformException catch (retryError) {
        throw NextcloudSyncException(
          'Could not save credentials to secure storage: '
          '${retryError.message ?? retryError.code}',
        );
      }
    }
  }

  @override
  Future<NextcloudCredentials?> readCredentials() async {
    final String? raw;
    try {
      raw = await _storage.read(key: _credentialsKey);
    } on PlatformException {
      // Secure store unreadable (e.g. lost master key) → treat as not
      // connected so startup/sync degrade gracefully instead of crashing.
      return null;
    }
    if (raw == null) return null;
    try {
      final decoded = jsonDecode(raw);
      if (decoded is Map<String, Object?>) {
        return NextcloudCredentials.fromJson(decoded);
      }
    } on FormatException {
      // Corrupt or non-https stored value → treat as not connected.
    }
    return null;
  }

  @override
  Future<void> deleteCredentials() async {
    try {
      await _storage.delete(key: _credentialsKey);
    } on PlatformException {
      // Already gone / store unavailable → nothing to clear.
    }
  }
}
