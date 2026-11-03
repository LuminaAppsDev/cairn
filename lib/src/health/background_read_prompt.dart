import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

/// Remembers, per device, that Cairn already asked for background reads — so
/// it asks once on its own and never nags; Settings can ask again on demand.
///
/// A marker file outside the synced `/Cairn/` tree (a permission is a property
/// of this device, not of the user's data), kept apart from the preferences
/// file, which its own store rewrites whole.
final class BackgroundReadPrompt {
  /// Creates a prompt memory backed by [marker].
  new({required this.marker});

  /// Resolves the marker at `<app-support>/cairn/background_read_asked`.
  static Future<BackgroundReadPrompt> appSupport() async {
    final support = await getApplicationSupportDirectory();
    return BackgroundReadPrompt(
      marker: File(p.join(support.path, 'cairn', 'background_read_asked')),
    );
  }

  /// The marker file; its presence means "already asked".
  final File marker;

  /// Whether Cairn has already asked on this device.
  Future<bool> wasAsked() async => marker.existsSync();

  /// Records that Cairn has asked (an empty file — its presence is the record).
  Future<void> markAsked() => marker.create(recursive: true);
}
