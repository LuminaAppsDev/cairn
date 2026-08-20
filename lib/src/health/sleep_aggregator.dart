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
      totalSleep: _asleepTime(group),
      stageDurations: stageDurations,
      awakenings: awakenings,
    );
  }

  /// Total time actually asleep: sleep intervals, minus any wakefulness inside
  /// them (DESIGN.md §4.3).
  ///
  /// A *union* rather than a sum, because sources overlap their own segments —
  /// Samsung Health emits a whole-night `session` alongside the light/deep/rem
  /// breakdown of the same minutes, and summing those reports eleven hours of
  /// sleep for a seven-hour night.
  ///
  /// And a *difference* rather than only a union, because that same whole-night
  /// `session` also spans the awake stretches inside it. Counting the union
  /// alone reported a real night with twenty-six awakenings as 6 h 16 min of
  /// unbroken sleep at 100 % efficiency; subtracting the wake intervals gives
  /// 5 h 30 min at 88 %, which is what the stage segments actually say.
  ///
  /// The rule is a set operation rather than a heuristic about which stages to
  /// ignore: time asleep is time inside a sleep interval and not inside a wake
  /// interval. That needs no special case for sources emitting a session marker
  /// and none for sources that do not.
  Duration _asleepTime(List<SleepSegmentSample> group) {
    final asleep = _merge([
      for (final s in group)
        if (s.stage.isAsleep) (start: s.start, end: s.end),
    ]);
    final awake = _merge([
      for (final s in group)
        if (s.stage.isAwake) (start: s.start, end: s.end),
    ]);

    var total = Duration.zero;
    for (final sleep in asleep) {
      var cursor = sleep.start;
      for (final wake in awake) {
        if (!wake.end.isAfter(cursor)) continue;
        if (!wake.start.isBefore(sleep.end)) break;
        if (wake.start.isAfter(cursor)) {
          total += wake.start.difference(cursor);
        }
        if (wake.end.isAfter(cursor)) cursor = wake.end;
        if (!cursor.isBefore(sleep.end)) break;
      }
      if (cursor.isBefore(sleep.end)) total += sleep.end.difference(cursor);
    }
    return total;
  }

  /// Collapses intervals into non-overlapping, ascending spans. Touching
  /// intervals merge: 01:00–02:00 then 02:00–03:00 is one two-hour stretch.
  List<({DateTime start, DateTime end})> _merge(
    List<({DateTime start, DateTime end})> intervals,
  ) {
    if (intervals.isEmpty) return const [];
    final sorted = [...intervals]..sort((a, b) => a.start.compareTo(b.start));

    final merged = <({DateTime start, DateTime end})>[];
    var start = sorted.first.start;
    var end = sorted.first.end;
    for (final interval in sorted.skip(1)) {
      if (!interval.start.isAfter(end)) {
        if (interval.end.isAfter(end)) end = interval.end;
        continue;
      }
      merged.add((start: start, end: end));
      start = interval.start;
      end = interval.end;
    }
    merged.add((start: start, end: end));
    return merged;
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
