import 'package:cairn/src/format/duration_format.dart';
import 'package:cairn/src/health/health_source.dart';
import 'package:cairn/src/query/night_sleep.dart';
import 'package:cairn/src/sleep/sleep_visuals.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';

/// A donut of where the [night] went, by sleep stage, with a labelled legend.
class StageBreakdown extends StatelessWidget {
  /// Creates a stage breakdown for [night].
  const StageBreakdown({required this.night, super.key});

  /// The night to break down.
  final NightSleep night;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final entries =
        night.perStage.entries.where((e) => e.value > Duration.zero).toList()
          ..sort((a, b) => stageDepth(a.key).compareTo(stageDepth(b.key)));

    if (entries.isEmpty) {
      return Text(
        'No per-stage breakdown for this night.',
        style: theme.textTheme.bodyMedium,
      );
    }

    return Row(
      children: [
        SizedBox(
          height: 140,
          width: 140,
          child: PieChart(
            PieChartData(
              centerSpaceRadius: 38,
              sectionsSpace: 2,
              sections: [
                for (final entry in entries)
                  PieChartSectionData(
                    value: entry.value.inMinutes.toDouble(),
                    color: stageColor(entry.key),
                    showTitle: false,
                    radius: 22,
                  ),
              ],
            ),
          ),
        ),
        const SizedBox(width: 16),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              for (final entry in entries)
                _LegendRow(stage: entry.key, duration: entry.value),
            ],
          ),
        ),
      ],
    );
  }
}

class _LegendRow extends StatelessWidget {
  const _LegendRow({required this.stage, required this.duration});

  final SleepStage stage;
  final Duration duration;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        children: [
          Container(
            width: 12,
            height: 12,
            decoration: BoxDecoration(
              color: stageColor(stage),
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 8),
          Expanded(child: Text(stageLabel(stage))),
          Text(
            formatHoursMinutes(duration),
            style: theme.textTheme.bodyMedium,
          ),
        ],
      ),
    );
  }
}
