import 'package:cairn/l10n/app_localizations.dart';
import 'package:cairn/src/health/health_metric.dart';
import 'package:cairn/src/metrics/widgets/series_line_chart.dart';
import 'package:cairn/src/metrics/widgets/stat_tiles.dart';
import 'package:cairn/src/query/display_readings.dart';
import 'package:cairn/src/query/health_query_service.dart';
import 'package:cairn/src/query/metric_series.dart';
import 'package:flutter/material.dart';

/// How many days of heart-rate history the screen shows.
const int _heartRateDays = 14;

/// Heart-rate detail screen: a daily-average trend over the last
/// [_heartRateDays] days plus the latest reading, window average and range.
class HeartRatePage extends StatefulWidget {
  /// Creates the heart-rate page reading from [query].
  const new({required this.query, super.key});

  /// The query service over the local OMH cache.
  final HealthQueryService query;

  @override
  State<HeartRatePage> createState() => _HeartRatePageState();
}

class _HeartRatePageState extends State<HeartRatePage> {
  late final Future<({ScalarReading? latest, List<DailyStat> stats})> _data =
      _load();

  Future<({ScalarReading? latest, List<DailyStat> stats})> _load() async {
    final latest = await widget.query.latestScalar(HealthMetric.heartRate);
    final stats = await widget.query.dailyHeartRate(days: _heartRateDays);
    return (latest: latest, stats: stats);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Scaffold(
      appBar: AppBar(title: Text(l10n.heartRateTitle)),
      body: FutureBuilder<({ScalarReading? latest, List<DailyStat> stats})>(
        future: _data,
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return Center(child: Text(l10n.metricLoadError));
          }
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          final stats = snapshot.data!.stats;
          if (stats.isEmpty) {
            return Center(child: Text(l10n.heartRateEmpty));
          }
          return _content(context, snapshot.data!.latest, stats);
        },
      ),
    );
  }

  Widget _content(
    BuildContext context,
    ScalarReading? latest,
    List<DailyStat> stats,
  ) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    var min = stats.first.min;
    var max = stats.first.max;
    var weightedSum = 0.0;
    var count = 0;
    for (final s in stats) {
      if (s.min < min) min = s.min;
      if (s.max > max) max = s.max;
      weightedSum += s.mean * s.count;
      count += s.count;
    }
    final mean = count == 0 ? 0.0 : weightedSum / count;
    String bpm(double v) => l10n.homeHeartRateValue(v.round().toString());
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Text(
          l10n.metricLastDays(_heartRateDays),
          style: theme.textTheme.bodySmall,
        ),
        const SizedBox(height: 12),
        StatTiles(
          tiles: [
            (
              label: l10n.heartRateLatest,
              value: latest == null ? '—' : bpm(latest.value),
            ),
            (label: l10n.heartRateAverage, value: bpm(mean)),
            (
              label: l10n.heartRateRange,
              value: l10n.heartRateRangeValue(
                min.round().toString(),
                max.round().toString(),
              ),
            ),
          ],
        ),
        const SizedBox(height: 24),
        Text(l10n.heartRateDailyAverage, style: theme.textTheme.titleMedium),
        const SizedBox(height: 8),
        SeriesLineChart(
          points: [for (final s in stats) (at: s.day, value: s.mean)],
          emptyLabel: l10n.heartRateEmpty,
        ),
      ],
    );
  }
}
