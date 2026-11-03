import 'dart:math' as math;

import 'package:cairn/src/format/locale_format.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';

/// One plotted point: a value at an instant.
typedef SeriesPoint = ({DateTime at, double value});

/// A "nice" axis step (1/2/5 x10^n) near [raw], so gridlines land on round
/// numbers instead of fl_chart's dense, full-precision defaults.
double _niceStep(double raw) {
  if (raw <= 0) return 1;
  final exponent = (math.log(raw) / math.ln10).floor();
  final magnitude = math.pow(10, exponent).toDouble();
  final norm = raw / magnitude;
  final nice = norm <= 1
      ? 1.0
      : norm <= 2
      ? 2.0
      : norm <= 5
      ? 5.0
      : 10.0;
  return nice * magnitude;
}

/// A simple time-ordered line chart for a scalar series (weight, daily-average
/// heart rate). Points are plotted by index (evenly spaced) with date labels at
/// the ends, which keeps sparse series readable. Degrades to a placeholder when
/// there is nothing meaningful to draw.
class SeriesLineChart extends StatelessWidget {
  /// Creates a line chart over [points] (assumed oldest-first). [emptyLabel] is
  /// shown when there are fewer than two points.
  const new({required this.points, required this.emptyLabel, super.key});

  /// The series to plot, oldest-first.
  final List<SeriesPoint> points;

  /// Placeholder text when the series cannot be charted.
  final String emptyLabel;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    if (points.length < 2) {
      return _placeholder(theme);
    }
    final locale = Localizations.localeOf(context).toLanguageTag();
    final values = points.map((p) => p.value).toList();
    var dataMin = values.first;
    var dataMax = values.first;
    for (final v in values) {
      if (v < dataMin) dataMin = v;
      if (v > dataMax) dataMax = v;
    }
    // Snap the Y range to a "nice" step (~5 ticks) so the axis shows round,
    // non-overlapping labels even when the spread is tiny (e.g. <1 kg). A flat
    // series still gets a one-step band so the line stays visible.
    final span = dataMax - dataMin;
    final step = _niceStep((span <= 0 ? 1.0 : span) / 5);
    final minY = (dataMin / step).floorToDouble() * step;
    final rawMaxY = (dataMax / step).ceilToDouble() * step;
    final maxY = rawMaxY <= minY ? minY + step : rawMaxY;
    final decimals = step >= 1
        ? 0
        : step >= 0.1
        ? 1
        : step >= 0.01
        ? 2
        : 3;
    final spots = <FlSpot>[
      for (var i = 0; i < points.length; i++)
        FlSpot(i.toDouble(), points[i].value),
    ];

    String label(DateTime t) =>
        '${t.month.toString().padLeft(2, '0')}-'
        '${t.day.toString().padLeft(2, '0')}';

    return SizedBox(
      height: 180,
      child: LineChart(
        LineChartData(
          minX: 0,
          maxX: (points.length - 1).toDouble(),
          minY: minY,
          maxY: maxY,
          gridData: const FlGridData(show: false),
          borderData: FlBorderData(show: false),
          lineTouchData: const LineTouchData(enabled: false),
          titlesData: FlTitlesData(
            topTitles: const AxisTitles(),
            rightTitles: const AxisTitles(),
            leftTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                reservedSize: 46,
                interval: step,
                getTitlesWidget: (value, meta) => Padding(
                  padding: const EdgeInsets.only(right: 6),
                  child: Text(
                    formatDecimal(
                      value,
                      locale: locale,
                      fractionDigits: decimals,
                    ),
                    style: theme.textTheme.bodySmall,
                    maxLines: 1,
                    softWrap: false,
                  ),
                ),
              ),
            ),
            bottomTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                reservedSize: 24,
                // Span the full range so fl_chart only auto-ticks the
                // endpoints; the guard below suppresses any others.
                interval: (points.length - 1).toDouble(),
                getTitlesWidget: (value, meta) {
                  final i = value.round();
                  if (i != 0 && i != points.length - 1) {
                    return const SizedBox.shrink();
                  }
                  return Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Text(
                      label(points[i].at),
                      style: theme.textTheme.bodySmall,
                    ),
                  );
                },
              ),
            ),
          ),
          lineBarsData: [
            LineChartBarData(
              spots: spots,
              color: theme.colorScheme.primary,
              dotData: FlDotData(show: points.length <= 14),
            ),
          ],
        ),
      ),
    );
  }

  Widget _placeholder(ThemeData theme) => SizedBox(
    height: 180,
    child: Center(child: Text(emptyLabel, style: theme.textTheme.bodyMedium)),
  );
}
