import 'package:cairn/src/health/health_metric.dart';
import 'package:cairn/src/health/health_sample.dart';
import 'package:cairn/src/health/sleep_aggregator.dart';

/// Maps raw [HealthSample]s to Open mHealth / IEEE 1752.1 datapoints.
///
/// A datapoint is represented as a JSON-serialisable map (one object per line
/// in the `.jsonl` shards). Emitted datapoints must validate against the OMH
/// schema library in tests — the format is the product's durability guarantee
/// (DESIGN.md §5, §13).
abstract interface class OmhMapper {
  /// Converts [sample] into an Open mHealth datapoint object.
  Map<String, Object?> toDataPoint(HealthSample sample);

  /// Maps an aggregated nightly [episode] to an `omh:sleep-episode` datapoint —
  /// the additive standard rollup over the raw `cairn:sleep-stage` segments.
  Map<String, Object?> sleepEpisodeToDataPoint(SleepEpisode episode);

  /// The schema id of the **per-sample** datapoint Cairn emits for [metric]
  /// (e.g. `omh:heart-rate`). Measures without a standard schema use the
  /// `cairn` namespace (DESIGN.md §5.2). For `sleep` this is the raw
  /// per-segment schema (`cairn:sleep-stage`); the additive nightly rollup is a
  /// separate datapoint that carries `omh:sleep-episode` in its own header.
  String schemaIdFor(HealthMetric metric);
}
