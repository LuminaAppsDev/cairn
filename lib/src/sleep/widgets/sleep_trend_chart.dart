import 'package:cairn/l10n/app_localizations.dart';
import 'package:cairn/src/query/night_sleep.dart';
import 'package:cairn/src/sleep/sleep_visuals.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';

/// Width reserved for the left (hours) axis. The tap overlay is inset by the
/// same amount so its columns line up with the bars, which `spaceAround`
/// centres within the plot area.
const double _leftAxisWidth = 28;

/// A bar per night showing total hours asleep, oldest → newest. When [onSelect]
/// is given, each night's full-height column is tappable to select that night,
/// and [selected] is drawn at full strength while the rest are dimmed.
class SleepTrendChart extends StatelessWidget {
  /// Creates a trend chart from [nights] (any order; sorted internally).
  const new({required this.nights, this.selected, this.onSelect, super.key});

  /// The nights to plot.
  final List<NightSleep> nights;

  /// The night currently shown in the detail panels — its bar is highlighted
  /// and the rest are dimmed. When null, every bar is drawn at full strength.
  final NightSleep? selected;

  /// Called with the night whose column was tapped, so the page can select it.
  final ValueChanged<NightSleep>? onSelect;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context);
    final materialL10n = MaterialLocalizations.of(context);
    if (nights.isEmpty) {
      return Text(l10n.sleepTrendEmpty, style: theme.textTheme.bodyMedium);
    }
    final ordered = [...nights]..sort((a, b) => a.night.compareTo(b.night));
    final selectedNight = selected?.night;
    final maxHours = ordered
        .map((n) => n.totalSleep.inMinutes / 60.0)
        .fold<double>(0, (m, h) => h > m ? h : m);

    return SizedBox(
      height: 180,
      child: Stack(
        children: [
          Positioned.fill(
            child: BarChart(
              BarChartData(
                alignment: BarChartAlignment.spaceAround,
                maxY: (maxHours < 1 ? 1 : maxHours) + 1,
                gridData: const FlGridData(show: false),
                borderData: FlBorderData(show: false),
                // Selection is handled by the tap overlay below, not fl_chart.
                barTouchData: const BarTouchData(enabled: false),
                titlesData: FlTitlesData(
                  topTitles: const AxisTitles(),
                  rightTitles: const AxisTitles(),
                  leftTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      reservedSize: _leftAxisWidth,
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
                          weekdayShort(l10n, ordered[i].night.weekday),
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
                          // Highlight the selected night; dim the rest so the
                          // active bar ties visually to the detail panels.
                          color:
                              selectedNight == null ||
                                  ordered[i].night == selectedNight
                              ? theme.colorScheme.primary
                              : theme.colorScheme.primary.withValues(
                                  alpha: 0.3,
                                ),
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
          ),
          // Transparent full-height tap targets, one per night, inset to line
          // up with the bars. A full-column hit area beats tapping a thin bar
          // and still works when a bar is short. Only taps are claimed, so a
          // vertical drag still reaches the page's pull-to-refresh.
          if (onSelect != null)
            Positioned.fill(
              left: _leftAxisWidth,
              child: Row(
                children: [
                  for (var i = 0; i < ordered.length; i++)
                    Expanded(
                      // The tap target is transparent with no text of its own,
                      // so give a screen reader the night's date to announce.
                      child: Semantics(
                        button: true,
                        label: materialL10n.formatMediumDate(ordered[i].night),
                        child: GestureDetector(
                          key: ValueKey('sleepTrendTap-$i'),
                          behavior: HitTestBehavior.opaque,
                          onTap: () => onSelect!(ordered[i]),
                        ),
                      ),
                    ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}
