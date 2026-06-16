import 'package:cairn/src/health/health_metric.dart';
import 'package:cairn/src/health/health_repository.dart';
import 'package:cairn/src/health/health_sample.dart';
import 'package:cairn/src/health/sleep_aggregator.dart';
import 'package:cairn/src/omh/default_omh_mapper.dart';
import 'package:cairn/src/omh/omh_mapper.dart';
import 'package:cairn/src/storage/omh_file_store.dart';
import 'package:flutter/foundation.dart';

/// How many datapoints were persisted for one metric in an ingest run.
@immutable
class IngestResult {
  /// Creates an ingest result.
  const IngestResult({required this.metric, required this.dataPointCount});

  /// The metric ingested.
  final HealthMetric metric;

  /// Number of OMH datapoints written to disk.
  final int dataPointCount;
}

/// The local write path (DESIGN.md §9, minus Nextcloud): read health for the
/// incremental window, map to OMH, persist into the [OmhFileStore], and advance
/// the per-metric sync anchor.
///
/// The anchor (DESIGN.md §5.4) makes each run incremental — `[lastSync, now]` —
/// replacing any fixed look-back window after the first run.
///
/// Delivery is **at-least-once**: the anchor advances only after a full batch
/// is appended, so a crash mid-append re-ingests that window on the next run.
/// Re-ingested datapoints get fresh UUIDs, so any later dedup (sync/query) must
/// compare body content + provenance, not the OMH header `id` (DESIGN.md §4.3).
final class HealthIngestService {
  /// Creates an ingest service. [mapper], [aggregator], [clock] and
  /// [initialLookback] are injectable for tests.
  HealthIngestService({
    required this.repository,
    required this.store,
    OmhMapper? mapper,
    this.aggregator = const SleepEpisodeAggregator(),
    DateTime Function()? clock,
    this.initialLookback = const Duration(days: 30),
  }) : _mapper = mapper ?? DefaultOmhMapper(),
       _now = clock ?? DateTime.now;

  /// The health-store reader (Phase 1).
  final HealthRepository repository;

  /// The local file store datapoints are persisted into.
  final OmhFileStore store;

  /// Aggregates sleep-stage segments into nightly episodes.
  final SleepEpisodeAggregator aggregator;

  /// First-run look-back used when a metric has no sync anchor yet.
  final Duration initialLookback;

  final OmhMapper _mapper;
  final DateTime Function() _now;

  /// Ingests each metric in [metrics] from its anchor (or `now -
  /// initialLookback` on first run) up to now, returning a per-metric result.
  Future<List<IngestResult>> ingest(Set<HealthMetric> metrics) async {
    final results = <IngestResult>[];
    final now = _now();
    for (final metric in metrics) {
      final anchor = await store.lastSyncAnchor(metric);
      final start = anchor ?? now.subtract(initialLookback);
      final samples = await repository.readSamples(
        metric: metric,
        start: start,
        end: now,
      );
      final count = await _persist(metric, samples);
      await store.setSyncAnchor(metric, now);
      results.add(IngestResult(metric: metric, dataPointCount: count));
    }
    return results;
  }

  Future<int> _persist(HealthMetric metric, List<HealthSample> samples) async {
    // Datapoints grouped by the local calendar day of the source reading, so
    // each lands in the right per-day shard (DESIGN.md §5.3).
    final byDay = <DateTime, List<Map<String, Object?>>>{};
    void add(DateTime day, Map<String, Object?> dataPoint) =>
        (byDay[_dateOnly(day)] ??= []).add(dataPoint);

    for (final sample in samples) {
      add(sample.start, _mapper.toDataPoint(sample));
    }
    // Sleep also gets the additive nightly episode rollup.
    if (metric == HealthMetric.sleep) {
      final segments = samples.whereType<SleepSegmentSample>().toList();
      for (final episode in aggregator.aggregate(segments)) {
        // Keyed on the episode's start (start-of-night) so it co-locates with
        // the night's stage segments in the same shard where possible.
        add(episode.start, _mapper.sleepEpisodeToDataPoint(episode));
      }
    }

    var count = 0;
    for (final entry in byDay.entries) {
      await store.append(
        metric: metric,
        day: entry.key,
        dataPoints: entry.value,
      );
      count += entry.value.length;
    }
    return count;
  }

  static DateTime _dateOnly(DateTime t) => DateTime(t.year, t.month, t.day);
}
