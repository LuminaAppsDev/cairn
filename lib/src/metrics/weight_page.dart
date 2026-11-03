import 'package:cairn/l10n/app_localizations.dart';
import 'package:cairn/src/format/locale_format.dart';
import 'package:cairn/src/health/health_metric.dart';
import 'package:cairn/src/metrics/widgets/series_line_chart.dart';
import 'package:cairn/src/metrics/widgets/stat_tiles.dart';
import 'package:cairn/src/query/display_readings.dart';
import 'package:cairn/src/query/health_query_service.dart';
import 'package:flutter/material.dart';

/// How many days of weight history the screen shows.
const int _weightDays = 90;

/// Weight detail screen: a trend line over the last [_weightDays] days plus the
/// latest value and the net change across the window.
class WeightPage extends StatefulWidget {
  /// Creates the weight page reading from [query].
  const new({required this.query, super.key});

  /// The query service over the local OMH cache.
  final HealthQueryService query;

  @override
  State<WeightPage> createState() => _WeightPageState();
}

class _WeightPageState extends State<WeightPage> {
  late final Future<List<ScalarReading>> _series = widget.query.scalarSeries(
    HealthMetric.weight,
    days: _weightDays,
  );

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Scaffold(
      appBar: AppBar(title: Text(l10n.weightTitle)),
      body: FutureBuilder<List<ScalarReading>>(
        future: _series,
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return Center(child: Text(l10n.metricLoadError));
          }
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          final readings = snapshot.data!;
          if (readings.isEmpty) {
            return Center(child: Text(l10n.weightEmpty));
          }
          return _content(context, readings);
        },
      ),
    );
  }

  Widget _content(BuildContext context, List<ScalarReading> readings) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    final locale = Localizations.localeOf(context).toLanguageTag();
    final latest = readings.last.value;
    final delta = latest - readings.first.value;
    final deltaText =
        '${delta >= 0 ? '+' : ''}${formatDecimal(delta, locale: locale)} kg';
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Text(
          l10n.metricLastDays(_weightDays),
          style: theme.textTheme.bodySmall,
        ),
        const SizedBox(height: 12),
        StatTiles(
          tiles: [
            (
              label: l10n.weightLatest,
              value: '${formatDecimal(latest, locale: locale)} kg',
            ),
            (label: l10n.weightChange, value: deltaText),
          ],
        ),
        const SizedBox(height: 24),
        SeriesLineChart(
          points: [for (final r in readings) (at: r.at, value: r.value)],
          emptyLabel: l10n.weightEmpty,
        ),
      ],
    );
  }
}
