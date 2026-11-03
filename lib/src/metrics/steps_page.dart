import 'package:cairn/l10n/app_localizations.dart';
import 'package:cairn/src/format/locale_format.dart';
import 'package:cairn/src/metrics/widgets/daily_bar_chart.dart';
import 'package:cairn/src/metrics/widgets/stat_tiles.dart';
import 'package:cairn/src/query/health_query_service.dart';
import 'package:cairn/src/query/metric_series.dart';
import 'package:flutter/material.dart';

/// How many days of step history the screen shows.
const int _stepDays = 14;

/// Steps detail screen: a daily bar chart over the last [_stepDays] days plus
/// today's total and the average over days that recorded data.
class StepsPage extends StatefulWidget {
  /// Creates the steps page reading from [query].
  const new({required this.query, super.key});

  /// The query service over the local OMH cache.
  final HealthQueryService query;

  @override
  State<StepsPage> createState() => _StepsPageState();
}

class _StepsPageState extends State<StepsPage> {
  late final Future<List<DailyValue>> _series = widget.query.dailySteps(
    days: _stepDays,
  );

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Scaffold(
      appBar: AppBar(title: Text(l10n.stepsTitle)),
      body: FutureBuilder<List<DailyValue>>(
        future: _series,
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return Center(child: Text(l10n.metricLoadError));
          }
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          final series = snapshot.data!;
          final hasData = series.any((d) => d.value > 0);
          if (!hasData) {
            return Center(child: Text(l10n.stepsEmpty));
          }
          return _content(context, series);
        },
      ),
    );
  }

  Widget _content(BuildContext context, List<DailyValue> series) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final locale = Localizations.localeOf(context).toLanguageTag();
    final today = series.last.value;
    // Average over days that actually recorded data, so missing days don't
    // drag the figure to zero.
    final active = series.where((d) => d.value > 0).toList();
    final average = active.isEmpty
        ? 0.0
        : active.fold<double>(0, (s, d) => s + d.value) / active.length;
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Text(l10n.metricLastDays(_stepDays), style: theme.textTheme.bodySmall),
        const SizedBox(height: 12),
        StatTiles(
          tiles: [
            (
              label: l10n.stepsToday,
              value: formatInteger(today, locale: locale),
            ),
            (
              label: l10n.stepsDailyAverage,
              value: formatInteger(average, locale: locale),
            ),
          ],
        ),
        const SizedBox(height: 24),
        DailyBarChart(data: series),
      ],
    );
  }
}
