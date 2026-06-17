import 'package:cairn/src/format/duration_format.dart';
import 'package:cairn/src/query/night_sleep.dart';
import 'package:flutter/material.dart';

/// A row of headline numbers for a [night]: total sleep, awakenings, and
/// efficiency (when determinable).
class SleepSummaryTiles extends StatelessWidget {
  /// Creates the summary tiles for [night].
  const SleepSummaryTiles({required this.night, super.key});

  /// The night to summarise.
  final NightSleep night;

  @override
  Widget build(BuildContext context) {
    final efficiency = night.efficiency;
    return Row(
      children: [
        _Tile(
          label: 'Time asleep',
          value: formatHoursMinutes(night.totalSleep),
        ),
        _Tile(label: 'Awakenings', value: '${night.awakenings}'),
        _Tile(
          label: 'Efficiency',
          value: efficiency == null ? '—' : '${(efficiency * 100).round()}%',
        ),
      ],
    );
  }
}

class _Tile extends StatelessWidget {
  const _Tile({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Expanded(
      child: Card(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 8),
          child: Column(
            children: [
              Text(value, style: theme.textTheme.titleLarge),
              const SizedBox(height: 4),
              Text(
                label,
                style: theme.textTheme.bodySmall,
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
