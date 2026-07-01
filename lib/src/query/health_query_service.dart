import 'package:cairn/src/health/health_metric.dart';
import 'package:cairn/src/health/health_source.dart';
import 'package:cairn/src/health/source_dedup.dart';
import 'package:cairn/src/query/display_readings.dart';
import 'package:cairn/src/query/metric_series.dart';
import 'package:cairn/src/query/night_sleep.dart';
import 'package:cairn/src/query/omh_reading_parser.dart';
import 'package:cairn/src/storage/omh_file_store.dart';

/// Read-path query API the dashboard uses over the local OMH cache
/// (DESIGN.md §9, read path A). An interface so screens can be tested with a
/// fake (real file I/O can't complete under the widget tester's fake-async).
abstract interface class HealthQueryService {
  /// The most recent scalar reading for [metric], or `null`.
  Future<ScalarReading?> latestScalar(HealthMetric metric);

  /// Today's total step count (source-deduplicated), or `null`.
  Future<double?> todayStepTotal();

  /// The most recent night of sleep, or `null`.
  Future<NightSleep?> lastNight();

  /// The last [n] nights of sleep, most-recent first.
  Future<List<NightSleep>> lastNNights(int n);

  /// Raw scalar readings for [metric] over the last [days], oldest-first.
  Future<List<ScalarReading>> scalarSeries(HealthMetric metric, {int days});

  /// Per-day total step counts over the last [days], oldest-first. Days with
  /// no data are included with a zero value so charts show the gap.
  Future<List<DailyValue>> dailySteps({int days});

  /// Per-day min / mean / max heart rate over the last [days], oldest-first.
  /// Days with no readings are omitted.
  Future<List<DailyStat>> dailyHeartRate({int days});

  /// Recent workouts over the last [days], most-recent-first.
  Future<List<WorkoutReading>> recentWorkouts({int days});
}

/// [HealthQueryService] backed by an [OmhFileStore]. Pure over the injected
/// store, so it is fully testable with a temp-dir store.
final class OmhHealthQueryService implements HealthQueryService {
  /// Creates a query service. [clock] and [lookback] are injectable; [lookback]
  /// bounds how far "latest"-style queries scan before giving up.
  OmhHealthQueryService({
    required this.store,
    DateTime Function()? clock,
    this.lookback = const Duration(days: 90),
  }) : _now = clock ?? DateTime.now;

  /// The cache this service reads.
  final OmhFileStore store;

  /// Maximum look-back for "latest" queries.
  final Duration lookback;

  final DateTime Function() _now;

  @override
  Future<ScalarReading?> latestScalar(HealthMetric metric) async {
    final today = _dateOnly(_now());
    for (var i = 0; i <= lookback.inDays; i++) {
      final day = today.subtract(Duration(days: i));
      final maps = await store.readRange(metric: metric, from: day, to: day);
      final readings = maps
          .map(parseScalar)
          .whereType<ScalarReading>()
          .toList();
      if (readings.isNotEmpty) {
        final resolved = _latestWins(readings)
          ..sort((a, b) => b.at.compareTo(a.at));
        return resolved.first;
      }
    }
    return null;
  }

  @override
  Future<double?> todayStepTotal() async {
    final today = _dateOnly(_now());
    final readings = (await store.readRange(
      metric: HealthMetric.steps,
      from: today,
      to: today,
    )).map(parseInterval).whereType<IntervalReading>().toList();
    if (readings.isEmpty) return null;
    return _dedupIntervals(
      readings,
    ).fold<double>(0, (sum, r) => sum + r.value);
  }

  @override
  Future<NightSleep?> lastNight() async {
    final nights = await lastNNights(1);
    return nights.isEmpty ? null : nights.first;
  }

  @override
  Future<List<NightSleep>> lastNNights(int n) async {
    final to = _dateOnly(_now());
    final from = to.subtract(Duration(days: n + 1));
    final maps = await store.readRange(
      metric: HealthMetric.sleep,
      from: from,
      to: to,
    );
    final stages = <SleepStageReading>[];
    final episodes = <SleepEpisodeReading>[];
    for (final map in maps) {
      switch (omhSchemaName(map)) {
        case 'sleep-stage':
          final reading = parseSleepStage(map);
          if (reading != null) stages.add(reading);
        case 'sleep-episode':
          final reading = parseSleepEpisode(map);
          if (reading != null) episodes.add(reading);
      }
    }
    final nights = reconcileNights(stages, episodes)
      ..sort((a, b) => b.start.compareTo(a.start));
    return nights.take(n).toList();
  }

  @override
  Future<List<ScalarReading>> scalarSeries(
    HealthMetric metric, {
    int days = 90,
  }) async {
    final to = _dateOnly(_now());
    // `days - 1`: the window is inclusive of today, so N days spans
    // [today-(N-1), today] (matches dailyHeartRate / dailySteps).
    final from = to.subtract(Duration(days: days - 1));
    final maps = await store.readRange(metric: metric, from: from, to: to);
    final readings = maps.map(parseScalar).whereType<ScalarReading>().toList();
    return _latestWins(readings)..sort((a, b) => a.at.compareTo(b.at));
  }

  @override
  Future<List<DailyValue>> dailySteps({int days = 14}) async {
    final to = _dateOnly(_now());
    final series = <DailyValue>[];
    // Read per day so deduplication is within-day (matching todayStepTotal),
    // and include empty days as zero so the trend chart shows the gap.
    for (var i = days - 1; i >= 0; i--) {
      final day = to.subtract(Duration(days: i));
      final readings = (await store.readRange(
        metric: HealthMetric.steps,
        from: day,
        to: day,
      )).map(parseInterval).whereType<IntervalReading>().toList();
      final total = readings.isEmpty
          ? 0.0
          : _dedupIntervals(readings).fold<double>(0, (s, r) => s + r.value);
      series.add(DailyValue(day: day, value: total));
    }
    return series;
  }

  @override
  Future<List<DailyStat>> dailyHeartRate({int days = 14}) async {
    final to = _dateOnly(_now());
    final from = to.subtract(Duration(days: days - 1));
    final maps = await store.readRange(
      metric: HealthMetric.heartRate,
      from: from,
      to: to,
    );
    final readings = maps.map(parseScalar).whereType<ScalarReading>().toList();
    final byDay = <DateTime, List<double>>{};
    for (final reading in _latestWins(readings)) {
      (byDay[_dateOnly(reading.at)] ??= []).add(reading.value);
    }
    final stats = byDay.entries.map((entry) {
      final values = entry.value;
      return DailyStat(
        day: entry.key,
        min: values.reduce((a, b) => a < b ? a : b),
        max: values.reduce((a, b) => a > b ? a : b),
        mean: values.reduce((a, b) => a + b) / values.length,
        count: values.length,
      );
    }).toList()..sort((a, b) => a.day.compareTo(b.day));
    return stats;
  }

  @override
  Future<List<WorkoutReading>> recentWorkouts({int days = 30}) async {
    final to = _dateOnly(_now());
    // `days - 1`: inclusive of today (see scalarSeries).
    final from = to.subtract(Duration(days: days - 1));
    final maps = await store.readRange(
      metric: HealthMetric.activity,
      from: from,
      to: to,
    );
    return maps.map(parseWorkout).whereType<WorkoutReading>().toList()
      ..sort((a, b) => b.start.compareTo(a.start));
  }

  /// Collapses readings describing the **same measurement** — same source and
  /// same effective instant — down to the one Cairn ingested most recently, so
  /// an in-place correction in the health app (e.g. a re-typed manual weight)
  /// supersedes the stale value on the read path without rewriting any
  /// append-only file (DESIGN.md §4.3). Readings from different sources, or at
  /// different instants, are all kept.
  ///
  /// Note: this resolves *value* corrections at an unchanged timestamp. Edits
  /// that move the timestamp, and deletions, still need the Phase 8
  /// change-token path (DESIGN.md §4, §15). Result order is unspecified —
  /// callers sort.
  List<ScalarReading> _latestWins(List<ScalarReading> readings) {
    // Key on a `(name, second)` record — structural equality — not a delimited
    // string, so a source name containing the delimiter can't collide two
    // distinct measurements. Readings with no parseable source share the ''
    // name and collapse by instant, which is acceptable: provenance is the only
    // identity available, so two unattributed same-instant readings are treated
    // as one (the later-ingested, or first-seen if neither is stamped).
    final best = <(String, int), ScalarReading>{};
    for (final r in readings) {
      final key = (r.source?.name ?? '', _seconds(r.at));
      final current = best[key];
      if (current == null || _ingestedAfter(r, current)) best[key] = r;
    }
    return best.values.toList();
  }

  /// Whether [a] was ingested strictly after [b] (scalar last-write-wins).
  static bool _ingestedAfter(ScalarReading a, ScalarReading b) =>
      _laterIngest(a.ingestedAt, b.ingestedAt);

  /// Whether ingest time [a] is strictly later than [b]. An unknown (null) time
  /// never supersedes — a missing header field degrades to "keep what we
  /// already have", so an undated reading never displaces a dated one (and two
  /// undated ones keep the first seen).
  static bool _laterIngest(DateTime? a, DateTime? b) {
    if (a == null) return false;
    return b == null || a.isAfter(b);
  }

  /// Collapses step readings to one per `(start,end)` window: the highest
  /// source priority wins, and on a tie the latest-ingested reading wins.
  ///
  /// The tie-break matters for a source that re-reports a **cumulative total**
  /// in a fixed window rather than per-interval deltas — Samsung Health, for
  /// one, exposes the day's steps as a single whole-day record whose value
  /// grows through the day, so each refresh appends a fresh snapshot with the
  /// same window. Keeping the newest snapshot yields the current total; keeping
  /// the first (the old behaviour) pins it to a stale value, and summing the
  /// window's snapshots would wildly over-count (DESIGN.md §4.3). Genuine
  /// per-interval deltas keep distinct windows and are still summed by callers.
  List<IntervalReading> _dedupIntervals(List<IntervalReading> readings) {
    const policy = SourcePriorityPolicy.defaults();
    final best = <String, IntervalReading>{};
    for (final r in readings) {
      final key = '${_seconds(r.start)}|${_seconds(r.end)}';
      final current = best[key];
      if (current == null || _preferInterval(policy, r, current)) {
        best[key] = r;
      }
    }
    return best.values.toList();
  }

  /// Whether step interval [r] should win its window over [current]: a
  /// higher-priority source, else — for the same source — the later-ingested
  /// snapshot.
  bool _preferInterval(
    SourcePriorityPolicy policy,
    IntervalReading r,
    IntervalReading current,
  ) {
    final rankR = _rank(policy, r);
    final rankCurrent = _rank(policy, current);
    if (rankR != rankCurrent) return rankR < rankCurrent;
    return _laterIngest(r.ingestedAt, current.ingestedAt);
  }

  int _rank(SourcePriorityPolicy policy, IntervalReading r) => policy.rank(
    HealthMetric.steps,
    _readingHealthSource(r.source),
  );

  // Recording method is all the steps policy needs beyond the name; platform is
  // unused on the read path (not stored in OMH).
  HealthSource _readingHealthSource(ReadingSource? source) => HealthSource(
    name: source?.name ?? 'unknown',
    platform: HealthPlatform.googleHealthConnect,
    recordingMethod: source?.modality == 'self-reported'
        ? RecordingMethodKind.manual
        : RecordingMethodKind.automatic,
  );

  static DateTime _dateOnly(DateTime t) => DateTime(t.year, t.month, t.day);
  static int _seconds(DateTime t) => t.toUtc().millisecondsSinceEpoch ~/ 1000;
}
