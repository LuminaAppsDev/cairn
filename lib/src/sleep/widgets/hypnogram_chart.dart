import 'package:cairn/l10n/app_localizations.dart';
import 'package:cairn/src/query/night_sleep.dart';
import 'package:cairn/src/sleep/sleep_visuals.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';

/// A hypnogram: the night's sleep stage over time as one coloured bar per
/// stage segment, deep at the bottom and awake at the top. Each phase is drawn
/// in its own colour (matching the donut legend) so the stages stand apart,
/// rather than as a single stepped line.
class HypnogramChart extends StatelessWidget {
  /// Creates a hypnogram for [night].
  const HypnogramChart({required this.night, super.key});

  /// The night to plot.
  final NightSleep night;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context);
    // One coloured horizontal bar per stage segment — no connecting line — so
    // each phase stands out by colour and depth instead of a single stepped
    // line weaving through the middle "Light" band. Colours match the donut.
    final bars = <LineChartBarData>[];
    var maxX = 0.0;
    for (final segment in night.stages) {
      final x0 = segment.start.difference(night.start).inMinutes.toDouble();
      final x1 = segment.end.difference(night.start).inMinutes.toDouble();
      if (x1 > maxX) maxX = x1;
      final y = stageDepth(segment.stage);
      bars.add(
        LineChartBarData(
          spots: [FlSpot(x0, y), FlSpot(x1, y)],
          color: stageColor(segment.stage),
          barWidth: 14,
          isStrokeCapRound: true,
          dotData: const FlDotData(show: false),
        ),
      );
    }

    // fl_chart needs a non-zero X range; degrade gracefully for an empty night
    // or one whose segments all have zero duration.
    if (bars.isEmpty || maxX <= 0) {
      return _Placeholder(text: l10n.sleepNoStageDetail, theme: theme);
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
                  final label = hypnogramAxisLabel(l10n, value.round());
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
          lineBarsData: bars,
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
