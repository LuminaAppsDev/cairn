import 'dart:convert';
import 'dart:io';

import 'package:cairn/src/health/health_metric.dart';
import 'package:cairn/src/health/health_repository.dart';
import 'package:cairn/src/health/health_sample.dart';
import 'package:cairn/src/health/sleep_aggregator.dart';
import 'package:cairn/src/omh/default_omh_mapper.dart';
import 'package:cairn/src/omh/omh_mapper.dart';
import 'package:cairn/src/storage/omh_file_store.dart';
import 'package:flutter/foundation.dart';

/// How many datapoints were persisted for one metric in an ingest run, and
/// why it stopped early, if it did.
@immutable
class IngestResult {
  /// Creates an ingest result.
  const IngestResult({
    required this.metric,
    required this.dataPointCount,
    this.error,
    this.stackTrace,
  });

  /// The metric ingested.
  final HealthMetric metric;

  /// Number of OMH datapoints written by the spans that completed — a span
  /// that failed partway may have saved some points without counting them.
  final int dataPointCount;

  /// Why ingesting [metric] stopped early, if it did: a [HealthReadException]
  /// when the store failed a read, a [HealthStoreUnavailableException] or a
  /// [FileSystemException], or else some other local failure or a bug. For a
  /// metric the run never reached, it is the failure that ended the run. Its
  /// anchor stays at the last finished span, so a later run retries from
  /// there.
  final Object? error;

  /// Where [error] was thrown.
  final StackTrace? stackTrace;

  /// Whether ingesting [metric] stopped early.
  bool get failed => error != null;
}

/// The local write path (DESIGN.md §9, minus Nextcloud): read health for the
/// window, map to OMH, persist into the [OmhFileStore], and advance the
/// per-metric sync anchor.
///
/// Each run re-reads a trailing [reconcileLookback] window — not just
/// `[anchor, now]` — so **backdated or late-arriving** entries are still
/// imported (e.g. a workout logged this morning for an earlier time, after a
/// prior sync already advanced the anchor past it). The basic `health` API can
/// only query by *effective* time, so this overlap is how late writes are
/// caught; doing so reliably for backdating *beyond* the window needs
/// when-written change tokens (a native plugin — DESIGN.md §4.3, Phase 8).
///
/// Appends are **idempotent**: a datapoint already on disk — matched by schema
/// + provenance + body, ignoring its random header `id`/`creation_date_time`
/// (which differ on every re-ingest) — is not written again, so the reconcile
/// overlap never duplicates data.
///
/// A re-read whose *value* changed but whose schema + source + time-frame match
/// an existing line is a **supersession** — a cumulative daily total that grew
/// (e.g. Samsung Health reports the day's steps as one whole-day record that
/// climbs) or an in-place correction. Rather than pile up snapshots, the day's
/// shard is compacted: the stale lines are dropped and the shard rewritten
/// atomically (the one sanctioned exception to append-only — DESIGN.md §5.3).
/// A run that supersedes nothing still takes the plain-append fast path.
final class HealthIngestService {
  /// Creates an ingest service. [mapper], [aggregator], [clock],
  /// [initialLookback] and [reconcileLookback] are injectable for tests.
  HealthIngestService({
    required this.repository,
    required this.store,
    OmhMapper? mapper,
    this.aggregator = const SleepEpisodeAggregator(),
    DateTime Function()? clock,
    this.initialLookback = const Duration(days: 30),
    this.reconcileLookback = const Duration(days: 14),
  }) : assert(
         reconcileLookback <= initialLookback,
         'reconcileLookback must not exceed the first-run initialLookback',
       ),
       _mapper = mapper ?? DefaultOmhMapper(),
       _now = clock ?? DateTime.now;

  /// The health-store reader (Phase 1).
  final HealthRepository repository;

  /// The local file store datapoints are persisted into.
  final OmhFileStore store;

  /// Aggregates sleep-stage segments into nightly episodes.
  final SleepEpisodeAggregator aggregator;

  /// First-run look-back used when a metric has no sync anchor yet.
  final Duration initialLookback;

  /// Trailing window re-read on every run (in addition to anything past the
  /// anchor) so backdated/late entries whose effective time precedes the
  /// anchor are still imported.
  final Duration reconcileLookback;

  final OmhMapper _mapper;
  final DateTime Function() _now;

  /// Longest span read from the health store in one call during a catch-up.
  /// The plugin holds a whole read in memory several times over (records,
  /// maps, channel bytes), so an unbounded catch-up after a long gap — months
  /// of heart rate — runs the process out of memory. A week is half the
  /// default reconcile window every run reads in one go, so a slice fits
  /// unless that week is far denser than an ordinary fortnight (days of 1 Hz
  /// workout heart rate), in which case that one slice still would not.
  static const _maxSlice = Duration(days: 7);

  /// Ingests each metric in [metrics] over `[start, now)`, where `start` is
  /// the earlier of the sync anchor and `now - reconcileLookback` (or `now -
  /// initialLookback` on first run). The trailing reconcile window is one
  /// read, as on every run; only a catch-up span before it (a long sync gap,
  /// or the first run) is read in slices of at most [_maxSlice], advancing the
  /// anchor after each, so a run killed mid catch-up resumes from the last
  /// finished slice instead of re-reading (and re-crashing on) the whole gap.
  ///
  /// Slice boundaries lose and double nothing: Health Connect matches reads on
  /// a record's start time alone, `start <= t < end` (the platform's
  /// `RecordHelper.getReadTableWhereClause`), so a record crossing a boundary
  /// is read exactly once, by the slice holding its start.
  ///
  /// A metric that fails — a read the store failed, a bug — is reported with
  /// [IngestResult.error] and keeps its anchor at the last finished span; the
  /// remaining metrics still run. Three failures end the run after their
  /// metric, as they aren't that metric's own: the store gone
  /// ([HealthStoreUnavailableException]), its read quota spent (a
  /// [HealthReadFailure.rateLimited] read, where each further read would only
  /// spend more), and local storage failing ([FileSystemException], e.g. a
  /// full disk), where every further write would only leave another torn
  /// shard. The metrics the run never reached fail with the same error, their
  /// anchors untouched. Never throws.
  /// Returns one result per metric, with its count of **newly written**
  /// datapoints.
  Future<List<IngestResult>> ingest(Set<HealthMetric> metrics) async {
    // Whole seconds: source dedup keys competing readings on whole seconds,
    // so a boundary mid-second could split a pair across two reads.
    final now = _wholeSeconds(_now());
    final reconcileStart = now.subtract(reconcileLookback);
    final results = <IngestResult>[];
    IngestResult? ended;
    for (final metric in metrics) {
      if (ended != null) {
        results.add(
          IngestResult(
            metric: metric,
            dataPointCount: 0,
            error: ended.error,
            stackTrace: ended.stackTrace,
          ),
        );
        continue;
      }
      final result = await _ingestMetric(metric, now, reconcileStart);
      results.add(result);
      if (_endsRun(result.error)) ended = result;
    }
    return results;
  }

  static bool _endsRun(Object? error) =>
      error is HealthStoreUnavailableException ||
      error is FileSystemException ||
      (error is HealthReadException &&
          error.failure == HealthReadFailure.rateLimited);

  Future<IngestResult> _ingestMetric(
    HealthMetric metric,
    DateTime now,
    DateTime reconcileStart,
  ) async {
    var count = 0;
    try {
      final anchor = await store.lastSyncAnchor(metric);
      // Older anchors may carry sub-second parts; boundaries must not.
      var start = _wholeSeconds(_windowStart(anchor, now, reconcileStart));
      // First run: pin the window start, so a read failing before any span
      // lands retries from here rather than from a start that slides forward
      // with now.
      if (anchor == null) await store.setSyncAnchor(metric, start);
      // Sleep is never sliced: its nightly episodes are aggregated per read,
      // so a boundary mid-night would persist two partial episodes — and a few
      // segments a night never needs slicing.
      while (metric != HealthMetric.sleep && start.isBefore(reconcileStart)) {
        final sliceEnd = start.add(_maxSlice);
        final end = sliceEnd.isBefore(reconcileStart)
            ? sliceEnd
            : reconcileStart;
        count += await _ingestSpan(metric, start, end);
        start = end;
      }
      count += await _ingestSpan(metric, start, now);
    } on Object catch (error, stack) {
      // The failure stops this metric. The span it was on never advanced the
      // anchor, so the next run retries it. Logged by type only: an arbitrary
      // error's text could quote record contents (a HealthReadException's is
      // the platform's own, and carries none).
      final what = error is HealthReadException ? '$error' : error.runtimeType;
      debugPrint('Ingesting ${metric.name} failed: $what');
      return IngestResult(
        metric: metric,
        dataPointCount: count,
        error: error,
        stackTrace: stack,
      );
    }
    return IngestResult(metric: metric, dataPointCount: count);
  }

  /// Reads `[start, end)`, persists it and advances the anchor to [end].
  /// Returns the count of newly written datapoints.
  Future<int> _ingestSpan(
    HealthMetric metric,
    DateTime start,
    DateTime end,
  ) async {
    final samples = await repository.readSamples(
      metric: metric,
      start: start,
      end: end,
    );
    final count = await _persist(metric, samples);
    await store.setSyncAnchor(metric, end);
    return count;
  }

  /// First run (no anchor) reads the full [initialLookback]; later runs read
  /// from the earlier of the anchor and `now - reconcileLookback`, so a
  /// sync gap is covered by the anchor and recent backdating by the window.
  DateTime _windowStart(
    DateTime? anchor,
    DateTime now,
    DateTime reconcileStart,
  ) {
    if (anchor == null) return now.subtract(initialLookback);
    return anchor.isBefore(reconcileStart) ? anchor : reconcileStart;
  }

  static DateTime _wholeSeconds(DateTime t) => t.subtract(
    Duration(milliseconds: t.millisecond, microseconds: t.microsecond),
  );

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
      final existing = await store.readRange(
        metric: metric,
        from: entry.key,
        to: entry.key,
      );
      // Drop exact re-reads (idempotent — the reconcile-window overlap re-reads
      // unchanged data), and collapse the batch to one record per supersede-key
      // so a single run can't write two conflicting values for one window.
      final seenContent = {for (final dp in existing) _contentKey(dp)};
      final freshByKey = <String, Map<String, Object?>>{};
      for (final dataPoint in entry.value) {
        if (!seenContent.add(_contentKey(dataPoint))) continue;
        freshByKey[_supersedeKey(dataPoint)] = dataPoint;
      }
      if (freshByKey.isEmpty) continue;
      final fresh = freshByKey.values.toList();

      // A fresh record supersedes any on-disk record with the same schema,
      // source and time-frame — the same logical measurement re-reported with a
      // new value (a cumulative daily total that grew, or a correction). The
      // fresh record is newer *by construction* (this run reads after the
      // last), so it wins. Single-writer-safe only: it assumes this device is
      // the sole writer of the shard. Cross-device recency can't be told from
      // the health store's data (Samsung's `source_creation_date_time` is just
      // the day key), so recency-aware merge waits on the Phase 8 sync work
      // (DESIGN.md §5.3). If a fresh record supersedes anything, rewrite the
      // shard without the stale lines; otherwise a plain append keeps the
      // append-only fast path (DESIGN.md §4.3, §5.3).
      final freshKeys = freshByKey.keys.toSet();
      final kept = existing
          .where((dp) => !freshKeys.contains(_supersedeKey(dp)))
          .toList();
      // Never rewrite a shard holding a line readRange couldn't parse (a torn
      // append): the rewrite builds from the parsed lines alone and would erase
      // it. Fall back to a plain append — the stale snapshots linger for this
      // shard, but nothing is lost and the read path still shows the latest.
      final compacts =
          kept.length != existing.length &&
          await store.isShardIntact(metric: metric, day: entry.key);
      if (compacts) {
        await store.replaceDay(
          metric: metric,
          day: entry.key,
          dataPoints: [...kept, ...fresh],
        );
      } else {
        await store.append(metric: metric, day: entry.key, dataPoints: fresh);
      }
      count += fresh.length;
    }
    return count;
  }

  static DateTime _dateOnly(DateTime t) => DateTime(t.year, t.month, t.day);
}

/// A stable identity for a datapoint that ignores the random header `id` and
/// the ingest-time `creation_date_time`, so the same reading re-read from the
/// health store matches what is already on disk (DESIGN.md §4.3).
///
/// Correctness depends on the kept fields being stable across re-reads: the
/// body (values + `effective_time_frame`) and `acquisition_provenance`
/// (`source_name`, `modality`, and `source_creation_date_time`, which is the
/// reading's effective time, not a wall-clock). The same health-store record
/// re-read yields identical JSON, so its key matches and it is not re-written.
String _contentKey(Map<String, Object?> dataPoint) {
  final header = dataPoint['header'];
  final headerMap = header is Map<String, Object?>
      ? header
      : const <String, Object?>{};
  return jsonEncode({
    'schema': headerMap['schema_id'],
    'provenance': headerMap['acquisition_provenance'],
    'body': dataPoint['body'],
  });
}

/// A coarser identity than [_contentKey] that ignores the datapoint's *value*:
/// its schema, source, and effective time-frame. Two datapoints sharing this
/// key are the **same logical measurement** re-reported with a new value — a
/// cumulative total that grew (Samsung Health reports the day's steps as one
/// whole-day record that climbs), or an in-place correction. The later one
/// supersedes the earlier, so the shard is compacted to keep just it (the
/// write-side of the read path's last-ingested-wins, DESIGN.md §4.3).
///
/// `source_name` (not the whole provenance) keys the source, matching the read
/// path — a re-reported total keeps the same source but its `modality` /
/// `source_creation_date_time` could differ, and those must not split the key.
String _supersedeKey(Map<String, Object?> dataPoint) {
  final header = dataPoint['header'];
  final headerMap = header is Map<String, Object?>
      ? header
      : const <String, Object?>{};
  final provenance = headerMap['acquisition_provenance'];
  final provMap = provenance is Map<String, Object?>
      ? provenance
      : const <String, Object?>{};
  final body = dataPoint['body'];
  final bodyMap = body is Map<String, Object?>
      ? body
      : const <String, Object?>{};
  return jsonEncode({
    'schema': headerMap['schema_id'],
    'source': provMap['source_name'],
    'frame': bodyMap['effective_time_frame'],
  });
}
