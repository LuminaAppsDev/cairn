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
    for (final segment in group) {
      if (segment.end.isAfter(end)) end = segment.end;
      // Counted per segment, not per merged interval: two adjacent awake
      // spans are two awakenings. And specifically `awake` — in-bed and
      // out-of-bed are position, not waking up.
      if (segment.stage == SleepStage.awake) awakenings++;
    }
    return _EpisodeStats(
      start: start,
      end: end,
      source: group.first.source,
      totalSleep: _asleepTime(group),
      stageDurations: _perStage(group),
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
  Duration _asleepTime(List<SleepSegmentSample> group) => _total(
    _subtract(
      _mergeWhere(group, (stage) => stage.isAsleep),
      _mergeWhere(group, (stage) => stage.isAwake),
    ),
  );

  /// How the night divides between stages, as a **partition**: every instant is
  /// attributed to exactly one of them.
  ///
  /// A plain sum per stage double-counts, because a whole-night `session`
  /// covers the very minutes the light/deep/rem segments describe — the parts
  /// would add up to more than the night. Each stage claims only time no more
  /// specific stage has already claimed ([SleepStage.bySpecificity]), which
  /// leaves `session` meaning what it honestly is: asleep, stage unrecorded.
  ///
  /// Two properties follow, both asserted in the tests: the sleep stages sum to
  /// exactly [_asleepTime], because wakefulness is claimed first and cannot be
  /// claimed twice; and every stage together sums to the covered time, so a
  /// breakdown chart adds up.
  Map<SleepStage, Duration> _perStage(List<SleepSegmentSample> group) {
    var claimed = <({DateTime start, DateTime end})>[];
    final out = <SleepStage, Duration>{};

    for (final stage in SleepStage.bySpecificity) {
      final intervals = _mergeWhere(group, (candidate) => candidate == stage);
      if (intervals.isEmpty) continue;
      final free = _total(_subtract(intervals, claimed));
      if (free > Duration.zero) out[stage] = free;
      claimed = _merge([...claimed, ...intervals]);
    }
    return out;
  }

  /// Merged intervals of every segment whose stage passes [matches].
  List<({DateTime start, DateTime end})> _mergeWhere(
    List<SleepSegmentSample> group,
    bool Function(SleepStage stage) matches,
  ) => _merge([
    for (final s in group)
      if (matches(s.stage)) (start: s.start, end: s.end),
  ]);

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

  /// [from] with every part of [remove] cut out. Both must already be merged.
  List<({DateTime start, DateTime end})> _subtract(
    List<({DateTime start, DateTime end})> from,
    List<({DateTime start, DateTime end})> remove,
  ) {
    if (remove.isEmpty) return from;

    final out = <({DateTime start, DateTime end})>[];
    for (final span in from) {
      var cursor = span.start;
      for (final cut in remove) {
        if (!cut.end.isAfter(cursor)) continue;
        if (!cut.start.isBefore(span.end)) break;
        if (cut.start.isAfter(cursor)) {
          out.add((start: cursor, end: cut.start));
        }
        if (cut.end.isAfter(cursor)) cursor = cut.end;
        if (!cursor.isBefore(span.end)) break;
      }
      if (cursor.isBefore(span.end)) {
        out.add((start: cursor, end: span.end));
      }
    }
    return out;
  }

  Duration _total(List<({DateTime start, DateTime end})> intervals) {
    var total = Duration.zero;
    for (final interval in intervals) {
      total += interval.end.difference(interval.start);
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
