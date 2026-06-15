import 'package:cairn/src/health/health_sample.dart';
import 'package:cairn/src/health/health_source.dart';
import 'package:flutter/foundation.dart';

/// A nightly sleep episode aggregated from raw [SleepSegmentSample]s.
///
/// Maps to the standard `omh:sleep-episode` schema (DESIGN.md §5). The raw
/// per-stage segments are still emitted separately (`cairn:sleep-stage`), so
/// this rollup is additive, never lossy.
@immutable
class SleepEpisode {
  /// Creates a sleep episode.
  const SleepEpisode({
    required this.start,
    required this.end,
    required this.source,
    required this.totalSleep,
    required this.isMainSleep,
    required this.stageDurations,
    required this.awakenings,
  });

  /// Onset of the episode (earliest segment start).
  final DateTime start;

  /// Final awakening (latest segment end).
  final DateTime end;

  /// Provenance, taken from the episode's first segment.
  final HealthSource source;

  /// Total time spent asleep, as the duration of the union of asleep-stage
  /// intervals (so an overall session is not double-counted with its stages).
  final Duration totalSleep;

  /// Whether this is the night's main sleep (vs a nap).
  final bool isMainSleep;

  /// Total duration per sleep stage within the episode.
  final Map<SleepStage, Duration> stageDurations;

  /// Number of awake segments between onset and final awakening.
  final int awakenings;
}

/// Groups raw sleep-stage segments into nightly [SleepEpisode]s (DESIGN.md §5).
class SleepEpisodeAggregator {
  /// Creates an aggregator. [gapTolerance] is the longest gap between
  /// consecutive segments that still counts as the same episode.
  const SleepEpisodeAggregator({
    this.gapTolerance = const Duration(minutes: 60),
  });

  /// Maximum gap between consecutive segments within one episode; larger gaps
  /// start a new episode (e.g. a daytime nap).
  final Duration gapTolerance;

  /// Aggregates [segments] into episodes ordered by start. Within each local
  /// night, the episode with the most sleep is flagged as the main sleep.
  List<SleepEpisode> aggregate(List<SleepSegmentSample> segments) {
    if (segments.isEmpty) return const [];
    final sorted = [...segments]..sort((a, b) => a.start.compareTo(b.start));

    final groups = <List<SleepSegmentSample>>[];
    var current = <SleepSegmentSample>[sorted.first];
    var groupEnd = sorted.first.end;
    for (final segment in sorted.skip(1)) {
      if (segment.start.difference(groupEnd) > gapTolerance) {
        groups.add(current);
        current = <SleepSegmentSample>[];
      }
      current.add(segment);
      if (segment.end.isAfter(groupEnd)) groupEnd = segment.end;
    }
    groups.add(current);

    final stats = groups.map(_statsFor).toList();
    final bestPerNight = <DateTime, Duration>{};
    for (final s in stats) {
      final night = _night(s.start);
      final best = bestPerNight[night];
      if (best == null || s.totalSleep > best) {
        bestPerNight[night] = s.totalSleep;
      }
    }

    return [
      for (final s in stats)
        SleepEpisode(
          start: s.start,
          end: s.end,
          source: s.source,
          totalSleep: s.totalSleep,
          stageDurations: s.stageDurations,
          awakenings: s.awakenings,
          isMainSleep:
              s.totalSleep > Duration.zero &&
              s.totalSleep == bestPerNight[_night(s.start)],
        ),
    ];
  }

  _EpisodeStats _statsFor(List<SleepSegmentSample> group) {
    final start = group.first.start;
    var end = group.first.end;
    var awakenings = 0;
    final stageDurations = <SleepStage, Duration>{};
    for (final segment in group) {
      if (segment.end.isAfter(end)) end = segment.end;
      final duration = segment.end.difference(segment.start);
      stageDurations[segment.stage] =
          (stageDurations[segment.stage] ?? Duration.zero) + duration;
      if (segment.stage == SleepStage.awake) awakenings++;
    }
    return _EpisodeStats(
      start: start,
      end: end,
      source: group.first.source,
      totalSleep: _asleepUnion(group),
      stageDurations: stageDurations,
      awakenings: awakenings,
    );
  }

  /// Total time asleep as the duration of the *union* of asleep-stage
  /// intervals. Using the union (not a sum) means an overall session segment
  /// that overlaps its own stage segments is not double-counted.
  Duration _asleepUnion(List<SleepSegmentSample> group) {
    final intervals = [
      for (final s in group)
        if (s.stage.isAsleep) (start: s.start, end: s.end),
    ]..sort((a, b) => a.start.compareTo(b.start));

    var total = Duration.zero;
    DateTime? mergeStart;
    DateTime? mergeEnd;
    for (final interval in intervals) {
      if (mergeEnd == null || interval.start.isAfter(mergeEnd)) {
        if (mergeStart != null && mergeEnd != null) {
          total += mergeEnd.difference(mergeStart);
        }
        mergeStart = interval.start;
        mergeEnd = interval.end;
      } else if (interval.end.isAfter(mergeEnd)) {
        mergeEnd = interval.end;
      }
    }
    if (mergeStart != null && mergeEnd != null) {
      total += mergeEnd.difference(mergeStart);
    }
    return total;
  }

  DateTime _night(DateTime t) => DateTime(t.year, t.month, t.day);
}

/// Internal per-group aggregates, before the main-sleep flag is assigned.
@immutable
class _EpisodeStats {
  const _EpisodeStats({
    required this.start,
    required this.end,
    required this.source,
    required this.totalSleep,
    required this.stageDurations,
    required this.awakenings,
  });

  final DateTime start;
  final DateTime end;
  final HealthSource source;
  final Duration totalSleep;
  final Map<SleepStage, Duration> stageDurations;
  final int awakenings;
}
