import 'package:cairn/l10n/app_localizations.dart';
import 'package:cairn/src/query/metric_series.dart';
import 'package:cairn/src/sleep/sleep_visuals.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';

/// A bar per day for a daily series (e.g. steps), oldest → newest, with
/// localized weekday labels and a compact "k" thousands axis.
class DailyBarChart extends StatelessWidget {
  /// Creates a bar chart over [data] (oldest-first).
  const new({required this.data, super.key});

  /// The daily values to plot, oldest-first.
  final List<DailyValue> data;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context);
    final maxValue = data.fold<double>(0, (m, d) => d.value > m ? d.value : m);

    return SizedBox(
      height: 180,
      child: BarChart(
        BarChartData(
          alignment: BarChartAlignment.spaceAround,
          maxY: maxValue <= 0 ? 1 : maxValue * 1.15,
          gridData: const FlGridData(show: false),
          borderData: FlBorderData(show: false),
          barTouchData: const BarTouchData(enabled: false),
          titlesData: FlTitlesData(
            topTitles: const AxisTitles(),
            rightTitles: const AxisTitles(),
            leftTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                reservedSize: 32,
                getTitlesWidget: (value, meta) {
                  if (value <= 0 || value >= meta.max) {
                    return const SizedBox.shrink();
                  }
                  final k = value / 1000;
                  final text = k >= 1
                      ? '${k.toStringAsFixed(0)}k'
                      : value.toStringAsFixed(0);
                  return Text(text, style: theme.textTheme.bodySmall);
                },
              ),
            ),
            bottomTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                getTitlesWidget: (value, meta) {
                  final i = value.round();
                  if (i < 0 || i >= data.length) {
                    return const SizedBox.shrink();
                  }
                  return Text(
                    weekdayShort(l10n, data[i].day.weekday),
                    style: theme.textTheme.bodySmall,
                  );
                },
              ),
            ),
          ),
          barGroups: [
            for (var i = 0; i < data.length; i++)
              BarChartGroupData(
                x: i,
                barRods: [
                  BarChartRodData(
                    toY: data[i].value,
                    color: theme.colorScheme.primary,
                    width: 12,
                    borderRadius: const BorderRadius.vertical(
                      top: Radius.circular(3),
                    ),
                  ),
                ],
              ),
          ],
        ),
      ),
    );
  }
}
