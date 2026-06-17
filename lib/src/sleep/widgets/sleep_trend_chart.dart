import 'package:cairn/src/query/night_sleep.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';

const List<String> _weekdays = [
  'Mon',
  'Tue',
  'Wed',
  'Thu',
  'Fri',
  'Sat',
  'Sun',
];

/// A bar per night showing total hours asleep, oldest → newest.
class SleepTrendChart extends StatelessWidget {
  /// Creates a trend chart from [nights] (any order; sorted internally).
  const SleepTrendChart({required this.nights, super.key});

  /// The nights to plot.
  final List<NightSleep> nights;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    if (nights.isEmpty) {
      return Text(
        'Not enough nights yet for a trend.',
        style: theme.textTheme.bodyMedium,
      );
    }
    final ordered = [...nights]..sort((a, b) => a.night.compareTo(b.night));
    final maxHours = ordered
        .map((n) => n.totalSleep.inMinutes / 60.0)
        .fold<double>(0, (m, h) => h > m ? h : m);

    return SizedBox(
      height: 180,
      child: BarChart(
        BarChartData(
          alignment: BarChartAlignment.spaceAround,
          maxY: (maxHours < 1 ? 1 : maxHours) + 1,
          gridData: const FlGridData(show: false),
          borderData: FlBorderData(show: false),
          barTouchData: const BarTouchData(enabled: false),
          titlesData: FlTitlesData(
            topTitles: const AxisTitles(),
            rightTitles: const AxisTitles(),
            leftTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                reservedSize: 28,
                interval: 2,
                getTitlesWidget: (value, meta) => Text(
                  '${value.round()}h',
                  style: theme.textTheme.bodySmall,
                ),
              ),
            ),
            bottomTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                getTitlesWidget: (value, meta) {
                  final i = value.round();
                  if (i < 0 || i >= ordered.length) {
                    return const SizedBox.shrink();
                  }
                  return Text(
                    _weekdays[ordered[i].night.weekday - 1],
                    style: theme.textTheme.bodySmall,
                  );
                },
              ),
            ),
          ),
          barGroups: [
            for (var i = 0; i < ordered.length; i++)
              BarChartGroupData(
                x: i,
                barRods: [
                  BarChartRodData(
                    toY: ordered[i].totalSleep.inMinutes / 60.0,
                    color: theme.colorScheme.primary,
                    width: 14,
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
