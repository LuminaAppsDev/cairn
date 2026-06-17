import 'package:cairn/src/health/health_metric.dart';
import 'package:cairn/src/health/health_sample.dart';
import 'package:cairn/src/health/health_source.dart';
import 'package:cairn/src/health/sleep_aggregator.dart';
import 'package:cairn/src/health/source_dedup.dart';
import 'package:cairn/src/query/display_readings.dart';
import 'package:flutter/foundation.dart';

/// One reconciled night of sleep for the dashboard: the (deduplicated) stage
/// segments plus the rolled-up statistics the sleep screen renders.
@immutable
class NightSleep {
  /// Creates a reconciled night.
  const NightSleep({
    required this.night,
    required this.start,
    required this.end,
    required this.stages,
    required this.totalSleep,
    required this.awakenings,
    required this.perStage,
    required this.isMainSleep,
    required this.sources,
    this.timeInBed,
    this.efficiency,
    this.storedEpisode,
  });

  /// The local calendar date the night is filed under (start-of-night).
  final DateTime night;

  /// Sleep onset (earliest segment start).
  final DateTime start;

  /// Final awakening (latest segment end).
  final DateTime end;

  /// The night's stage segments, single-source and ordered by start.
  final List<SleepStageReading> stages;

  /// Total time asleep (union of asleep-stage intervals).
  final Duration totalSleep;

  /// Number of awakenings (awake segments) within the night.
  final int awakenings;

  /// Total duration per sleep stage.
  final Map<SleepStage, Duration> perStage;

  /// Whether this is the night's main sleep (vs a nap).
  final bool isMainSleep;

  /// Distinct source names that contributed segments for this night. More than
  /// one means data overlapped from several apps/devices (see reconciliation
  /// note) — surfaced so the UI can flag it.
  final Set<String> sources;

  /// Time in bed (onset→final-awakening), only when the night has explicit
  /// awake/in-bed markers; otherwise `null` (efficiency then undeterminable).
  final Duration? timeInBed;

  /// Sleep efficiency in `0..1` (total sleep / time in bed), or `null` when not
  /// determinable (no awake markers) — never faked to 100%.
  final double? efficiency;

  /// The source's own `omh:sleep-episode` rollup for this night, if one was
  /// stored, for cross-reference. The displayed stats above are recomputed.
  final SleepEpisodeReading? storedEpisode;

  /// Whether the night has real per-stage data (not just a `session` block).
  bool get hasStageBreakdown =>
      perStage.keys.any((stage) => stage != SleepStage.session);
}

/// Reconciles raw parsed sleep readings into per-night [NightSleep]s
/// (DESIGN.md §4.3, §5).
///
/// Steps: drop exact-duplicate segments (crash-replay writes fresh UUIDs, so
/// dedup is by content+window, never the OMH `header.id`); pick the preferred
/// source on an exact-window collision via [SourcePriorityPolicy]; gap-group
/// and compute union-based statistics by reusing [SleepEpisodeAggregator].
///
/// Known limitation (v1): two sources that track the *same* night with
/// *different* segmentation are not merged into one — both contribute and
/// per-stage durations may overlap. [NightSleep.sources] exposes this so the UI
/// can warn; full per-night source selection lands with the Phase 8 work.
List<NightSleep> reconcileNights(
  List<SleepStageReading> stages,
  List<SleepEpisodeReading> storedEpisodes, {
  SleepEpisodeAggregator aggregator = const SleepEpisodeAggregator(),
}) {
  if (stages.isEmpty) return const [];
  final unique = _dedupStages(stages);
  final episodes = aggregator.aggregate(unique.map(_toSegment).toList());
  return [
    for (final episode in episodes)
      _buildNight(episode, unique, storedEpisodes),
  ];
}

NightSleep _buildNight(
  SleepEpisode episode,
  List<SleepStageReading> all,
  List<SleepEpisodeReading> stored,
) {
  final members =
      all
          .where(
            (r) =>
                !r.start.isBefore(episode.start) &&
                !r.start.isAfter(episode.end),
          )
          .toList()
        ..sort((a, b) => a.start.compareTo(b.start));
  final sources = {for (final r in members) r.source?.name ?? 'unknown'};
  final hasWakeMarkers = members.any((r) => !r.stage.isAsleep);
  final inBed = episode.end.difference(episode.start);
  final efficiency = (hasWakeMarkers && inBed > Duration.zero)
      ? episode.totalSleep.inSeconds / inBed.inSeconds
      : null;
  return NightSleep(
    night: DateTime(episode.start.year, episode.start.month, episode.start.day),
    start: episode.start,
    end: episode.end,
    stages: members,
    totalSleep: episode.totalSleep,
    awakenings: episode.awakenings,
    perStage: episode.stageDurations,
    isMainSleep: episode.isMainSleep,
    sources: sources,
    timeInBed: hasWakeMarkers ? inBed : null,
    efficiency: efficiency,
    storedEpisode: _matchStored(stored, episode),
  );
}

/// Drops exact-duplicate segments (same window) and, on an exact-window
/// collision from different sources, keeps the preferred source. The result is
/// in map-iteration order; callers that need ordering must sort (the aggregator
/// and [_buildNight] both do).
List<SleepStageReading> _dedupStages(List<SleepStageReading> readings) {
  const policy = SourcePriorityPolicy.defaults();
  int rank(SleepStageReading r) =>
      policy.rank(HealthMetric.sleep, _toHealthSource(r.source));
  int manualPenalty(SleepStageReading r) =>
      r.source?.modality == 'self-reported' ? 1 : 0;

  final best = <String, SleepStageReading>{};
  for (final r in readings) {
    final key = '${_seconds(r.start)}|${_seconds(r.end)}';
    final current = best[key];
    final better =
        current == null ||
        rank(r) < rank(current) ||
        (rank(r) == rank(current) && manualPenalty(r) < manualPenalty(current));
    if (better) best[key] = r;
  }
  return best.values.toList();
}

SleepEpisodeReading? _matchStored(
  List<SleepEpisodeReading> stored,
  SleepEpisode episode,
) {
  for (final s in stored) {
    if (s.start.isBefore(episode.end) && s.end.isAfter(episode.start)) {
      return s;
    }
  }
  return null;
}

SleepSegmentSample _toSegment(SleepStageReading r) => SleepSegmentSample(
  start: r.start,
  end: r.end,
  source: _toHealthSource(r.source),
  stage: r.stage,
);

HealthSource _toHealthSource(ReadingSource? source) => HealthSource(
  name: source?.name ?? 'unknown',
  // Platform is unused on the read path (not stored in OMH); the dedup policy
  // only looks at the name + recording method.
  platform: HealthPlatform.googleHealthConnect,
  recordingMethod: source?.modality == 'self-reported'
      ? RecordingMethodKind.manual
      : RecordingMethodKind.automatic,
);

int _seconds(DateTime t) => t.toUtc().millisecondsSinceEpoch ~/ 1000;
