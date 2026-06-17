import 'dart:convert';
import 'dart:typed_data';

import 'package:cairn/src/profile/profile.dart';
import 'package:cairn/src/profile/profile_store.dart';

/// Fetches the raw `profile.json` bytes from Nextcloud, or `null` when not
/// connected or no remote profile exists.
typedef ProfileDownloader = Future<Uint8List?> Function();

/// Upper bound on a sane `profile.json` (it holds only height + date of birth,
/// ~200 bytes; the 64 KiB cap is generous headroom). Larger responses are
/// rejected rather than buffered/written. Also passed to the download layer so
/// the abort happens before the body is fully held in memory.
const int kMaxProfileBytes = 64 * 1024;

/// Pulls `profile.json` down from Nextcloud and adopts it locally when the
/// remote copy is newer than (or absent on) this device.
///
/// A single-file, last-write-wins precursor to the Phase 8 bidirectional
/// sync. The profile is user-entered and can't be re-derived from the health
/// store, so it is the one thing worth pulling back on a fresh install or a
/// second device. The append-only health shards stay push-only for now (§8).
final class ProfileSyncService {
  /// Creates a profile-pull service over [store], fetching bytes via
  /// [download].
  ProfileSyncService({required this.store, required this.download});

  /// The local profile store to reconcile into.
  final JsonProfileStore store;

  /// Fetches the remote `profile.json` bytes (or `null`).
  final ProfileDownloader download;

  /// Pulls the remote profile and, when it is newer than the local one (or no
  /// local profile exists), adopts it verbatim and returns it. Returns `null`
  /// when nothing changes: not connected, no remote profile, a malformed
  /// remote, or the local profile is already current.
  Future<Profile?> pull() async {
    final bytes = await download();
    if (bytes == null) return null;
    // A real profile.json is a few hundred bytes; refuse an implausibly large
    // response rather than write it verbatim to disk.
    if (bytes.length > kMaxProfileBytes) return null;
    Map<String, Object?>? remoteJson;
    try {
      final decoded = jsonDecode(utf8.decode(bytes));
      if (decoded is Map<String, Object?>) remoteJson = decoded;
    } on FormatException {
      return null; // malformed remote (bad UTF-8 or JSON) → keep local
    }
    final json = remoteJson;
    if (json == null) return null;

    final remoteUpdated = _updatedAt(json);
    final localUpdated = await store.updatedAt();
    // Adopt when there is no local profile, or the remote was edited more
    // recently. A remote without a timestamp can't displace an existing local.
    final adopt =
        localUpdated == null ||
        (remoteUpdated != null && remoteUpdated.isAfter(localUpdated));
    if (!adopt) return null;

    await store.writeRaw(bytes); // verbatim → preserves the remote edit time
    return Profile.fromJson(json);
  }
}

DateTime? _updatedAt(Map<String, Object?> json) {
  final value = json['updated_date_time'];
  return value is String ? DateTime.tryParse(value) : null;
}
