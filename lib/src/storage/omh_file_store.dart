import 'package:cairn/src/health/health_metric.dart';

/// Append-only local store for Open mHealth datapoints.
///
/// Datapoints are sharded one file per metric per day
/// (`/Cairn/<metric>/<year>/<date>.jsonl`) and written as appends, never
/// rewrites, to avoid Nextcloud conflict copies (DESIGN.md §5.3). The local
/// cache mirrors the tree that is synced to Nextcloud.
abstract interface class OmhFileStore {
  /// Appends [dataPoints] to the shard for [metric] on [day]. Only the local
  /// calendar date of [day] (year, month, day) selects the shard; any time
  /// component is ignored.
  Future<void> append({
    required HealthMetric metric,
    required DateTime day,
    required List<Map<String, Object?>> dataPoints,
  });

  /// Reads every datapoint stored for [metric] whose day falls within the
  /// inclusive calendar-date range `[from, to]`. Only the local-date
  /// components of [from] and [to] are significant.
  Future<List<Map<String, Object?>>> readRange({
    required HealthMetric metric,
    required DateTime from,
    required DateTime to,
  });

  /// Returns the last-synced anchor recorded in `manifest.json` for [metric],
  /// or `null` if it has never been synced (DESIGN.md §5.4).
  Future<DateTime?> lastSyncAnchor(HealthMetric metric);

  /// Records [anchor] as the last-synced instant for [metric] in
  /// `manifest.json` (the high-watermark that drives the next incremental read
  /// window). Persisted atomically.
  Future<void> setSyncAnchor(HealthMetric metric, DateTime anchor);
}
