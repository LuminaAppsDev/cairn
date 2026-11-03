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
  const new({required this.night, super.key});

  /// The night to plot.
  final NightSleep night;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context);
    final materialL10n = MaterialLocalizations.of(context);
    final use24h = MediaQuery.of(context).alwaysUse24HourFormat;
    String clock(DateTime t) => materialL10n.formatTimeOfDay(
      TimeOfDay.fromDateTime(t),
      alwaysUse24HourFormat: use24h,
    );

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
          spots: _segmentSpots(x0, x1, y),
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

    final tooltipStyle = (theme.textTheme.bodySmall ?? const TextStyle())
        .copyWith(
          color: theme.colorScheme.onInverseSurface,
          fontWeight: FontWeight.w600,
        );

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
          lineTouchData: LineTouchData(
            touchTooltipData: LineTouchTooltipData(
              getTooltipColor: (_) => theme.colorScheme.inverseSurface,
              // Tap a bar to see its stage and the clock time it spanned. Bars
              // map 1:1 to night.stages by index; show one line per bar so a
              // tap near a transition doesn't stack duplicate entries.
              getTooltipItems: (touchedSpots) {
                final shown = <int>{};
                return touchedSpots.map((spot) {
                  if (!shown.add(spot.barIndex)) return null;
                  final segment = night.stages[spot.barIndex];
                  return LineTooltipItem(
                    '${stageLabel(l10n, segment.stage)}\n'
                    '${clock(segment.start)} – ${clock(segment.end)}',
                    tooltipStyle,
                  );
                }).toList();
              },
            ),
            // A thin time-marker at the touch, no dot.
            getTouchedSpotIndicator: (barData, indexes) => [
              for (final _ in indexes)
                TouchedSpotIndicatorData(
                  FlLine(color: theme.colorScheme.outline, strokeWidth: 1),
                  const FlDotData(show: false),
                ),
            ],
          ),
          lineBarsData: bars,
        ),
      ),
    );
  }
}

/// Spots for one flat stage bar at depth [y], sampled every few minutes across
/// `[x0, x1]` rather than just the two ends. fl_chart's line touch snaps to the
/// nearest spot, so endpoints alone would leave the middle of a long bar
/// untappable; the intermediate spots make a tap anywhere on the bar register.
List<FlSpot> _segmentSpots(double x0, double x1, double y) {
  const stepMinutes = 10.0;
  final spots = <FlSpot>[FlSpot(x0, y)];
  for (var x = x0 + stepMinutes; x < x1; x += stepMinutes) {
    spots.add(FlSpot(x, y));
  }
  spots.add(FlSpot(x1, y));
  return spots;
}

class _Placeholder extends StatelessWidget {
  const new({required this.text, required this.theme});

  final String text;
  final ThemeData theme;

  @override
  Widget build(BuildContext context) => SizedBox(
    height: 180,
    child: Center(child: Text(text, style: theme.textTheme.bodyMedium)),
  );
}
