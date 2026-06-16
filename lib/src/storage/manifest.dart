import 'package:cairn/src/health/health_metric.dart';
import 'package:cairn/src/omh/omh_time.dart';
import 'package:flutter/foundation.dart';

/// The current on-disk format version. Bump on any breaking layout/schema
/// change and ship a migration — the format is every user's whole history
/// (DESIGN.md §5.4).
const int kFormatVersion = 1;

/// The `/Cairn/manifest.json` document: format version, per-metric last-sync
/// anchors, and a reserved device list (DESIGN.md §5.3–5.4).
@immutable
class Manifest {
  /// Creates a manifest.
  const Manifest({
    required this.formatVersion,
    required this.syncAnchors,
    this.devices = const [],
  });

  /// An empty manifest for a brand-new cache.
  factory Manifest.empty() =>
      const Manifest(formatVersion: kFormatVersion, syncAnchors: {});

  /// Parses a manifest map, tolerating missing, malformed, or unknown keys
  /// (e.g. anchors written by a newer format version).
  factory Manifest.fromJson(Map<String, Object?> json) {
    final anchors = <HealthMetric, DateTime>{};
    final rawAnchors = json['sync_anchors'];
    if (rawAnchors is Map<String, Object?>) {
      rawAnchors.forEach((slug, value) {
        final metric = HealthMetric.fromSlug(slug);
        // `DateTime.tryParse` of an offset timestamp yields a UTC DateTime;
        // convert to local so every anchor exposed by the API is local —
        // matching how callers produce them and how shards are date-named.
        final raw = value is String ? DateTime.tryParse(value) : null;
        final parsed = raw?.toLocal();
        if (metric != null && parsed != null) anchors[metric] = parsed;
      });
    }
    final version = json['format_version'];
    final rawDevices = json['devices'];
    return Manifest(
      formatVersion: version is int ? version : kFormatVersion,
      syncAnchors: anchors,
      devices: rawDevices is List
          ? rawDevices.whereType<String>().toList()
          : const [],
    );
  }

  /// On-disk format version this manifest was written with.
  final int formatVersion;

  /// Per-metric last-synced instant (high-watermark).
  final Map<HealthMetric, DateTime> syncAnchors;

  /// Reserved device list (unused until device tracking lands).
  final List<String> devices;

  /// Returns a copy with [metric]'s anchor set to [anchor].
  Manifest withAnchor(HealthMetric metric, DateTime anchor) => Manifest(
    formatVersion: formatVersion,
    syncAnchors: {...syncAnchors, metric: anchor},
    devices: devices,
  );

  /// Serialises to the manifest JSON object, stamping `updated_date_time` with
  /// [updatedAt] (local-offset ISO-8601).
  Map<String, Object?> toJson({required DateTime updatedAt}) => {
    'format_version': formatVersion,
    'generator': 'cairn',
    'updated_date_time': omhDateTime(updatedAt),
    'sync_anchors': {
      for (final entry in syncAnchors.entries)
        entry.key.slug: omhDateTime(entry.value),
    },
    'devices': devices,
  };
}
