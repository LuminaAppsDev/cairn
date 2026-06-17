import 'package:cairn/src/query/night_sleep.dart';
import 'package:cairn/src/sleep/sleep_visuals.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';

/// A hypnogram: the night's sleep stage over time as a stepped line, deep at
/// the bottom and awake at the top.
class HypnogramChart extends StatelessWidget {
  /// Creates a hypnogram for [night].
  const HypnogramChart({required this.night, super.key});

  /// The night to plot.
  final NightSleep night;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final spots = <FlSpot>[];
    for (final segment in night.stages) {
      final x0 = segment.start.difference(night.start).inMinutes.toDouble();
      final x1 = segment.end.difference(night.start).inMinutes.toDouble();
      final y = stageDepth(segment.stage);
      spots
        ..add(FlSpot(x0, y))
        ..add(FlSpot(x1, y));
    }

    // fl_chart needs at least two points spanning a non-zero range; degrade
    // gracefully for empty or all-zero-duration nights.
    final maxX = spots.isEmpty ? 0.0 : spots.last.x;
    if (spots.length < 2 || maxX <= 0) {
      return _Placeholder(
        text: 'No per-stage detail for this night.',
        theme: theme,
      );
    }

    return SizedBox(
      height: 180,
      child: LineChart(
        LineChartData(
          minX: 0,
          maxX: maxX,
          minY: -0.5,
          maxY: 3.5,
          gridData: const FlGridData(show: false),
          borderData: FlBorderData(show: false),
          titlesData: FlTitlesData(
            topTitles: const AxisTitles(),
            rightTitles: const AxisTitles(),
            bottomTitles: const AxisTitles(),
            leftTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                reservedSize: 52,
                interval: 1,
                getTitlesWidget: (value, meta) {
                  final label = kHypnogramAxis[value.round()];
                  if (label == null) return const SizedBox.shrink();
                  return Padding(
                    padding: const EdgeInsets.only(right: 6),
                    child: Text(label, style: theme.textTheme.bodySmall),
                  );
                },
              ),
            ),
          ),
          lineTouchData: const LineTouchData(enabled: false),
          lineBarsData: [
            LineChartBarData(
              spots: spots,
              isStepLineChart: true,
              color: theme.colorScheme.primary,
              dotData: const FlDotData(show: false),
            ),
          ],
        ),
      ),
    );
  }
}

class _Placeholder extends StatelessWidget {
  const _Placeholder({required this.text, required this.theme});

  final String text;
  final ThemeData theme;

  @override
  Widget build(BuildContext context) => SizedBox(
    height: 180,
    child: Center(
      child: Text(text, style: theme.textTheme.bodyMedium),
    ),
  );
}
