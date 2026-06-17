import 'package:cairn/src/query/health_query_service.dart';
import 'package:cairn/src/query/night_sleep.dart';
import 'package:cairn/src/sleep/widgets/hypnogram_chart.dart';
import 'package:cairn/src/sleep/widgets/sleep_summary_tiles.dart';
import 'package:cairn/src/sleep/widgets/sleep_trend_chart.dart';
import 'package:cairn/src/sleep/widgets/stage_breakdown.dart';
import 'package:flutter/material.dart';

/// How many recent nights the trend chart covers.
const int _trendNights = 7;

/// The sleep deep-dive: last night's hypnogram + stage breakdown + headline
/// numbers, and a multi-night trend (DESIGN.md §9, read path A).
class SleepPage extends StatefulWidget {
  /// Creates the sleep page reading from [query].
  const SleepPage({required this.query, super.key});

  /// The query service over the local OMH cache.
  final HealthQueryService query;

  @override
  State<SleepPage> createState() => _SleepPageState();
}

class _SleepPageState extends State<SleepPage> {
  late Future<List<NightSleep>> _nights;

  @override
  void initState() {
    super.initState();
    _nights = widget.query.lastNNights(_trendNights);
  }

  Future<void> _refresh() async {
    final nights = widget.query.lastNNights(_trendNights);
    setState(() => _nights = nights);
    await nights;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Sleep')),
      body: RefreshIndicator(
        onRefresh: _refresh,
        child: FutureBuilder<List<NightSleep>>(
          future: _nights,
          builder: (context, snapshot) {
            if (snapshot.connectionState != ConnectionState.done) {
              return const Center(child: CircularProgressIndicator());
            }
            final nights = snapshot.data ?? const [];
            if (nights.isEmpty) {
              return _empty(context);
            }
            return _content(context, nights);
          },
        ),
      ),
    );
  }

  Widget _empty(BuildContext context) => ListView(
    padding: const EdgeInsets.all(24),
    children: [
      const SizedBox(height: 80),
      Icon(
        Icons.bedtime_outlined,
        size: 48,
        color: Theme.of(context).colorScheme.primary,
      ),
      const SizedBox(height: 16),
      Text(
        'No sleep data yet',
        textAlign: TextAlign.center,
        style: Theme.of(context).textTheme.titleMedium,
      ),
      const SizedBox(height: 8),
      const Text(
        'Track a night with a wearable or your health app, then refresh.',
        textAlign: TextAlign.center,
      ),
    ],
  );

  Widget _content(BuildContext context, List<NightSleep> nights) {
    final last = nights.first;
    final theme = Theme.of(context);
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Text('Last night', style: theme.textTheme.titleLarge),
        const SizedBox(height: 4),
        Text(
          _dateLabel(last),
          style: theme.textTheme.bodySmall,
        ),
        const SizedBox(height: 12),
        SleepSummaryTiles(night: last),
        if (last.sources.length > 1)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text(
              'Multiple sources tracked this night; totals may overlap.',
              style: theme.textTheme.bodySmall,
            ),
          ),
        const SizedBox(height: 24),
        _SectionTitle('Stages through the night', theme),
        HypnogramChart(night: last),
        const SizedBox(height: 24),
        _SectionTitle('Where the night went', theme),
        StageBreakdown(night: last),
        const SizedBox(height: 24),
        _SectionTitle('Last $_trendNights nights', theme),
        SleepTrendChart(nights: nights),
        const SizedBox(height: 24),
      ],
    );
  }

  String _dateLabel(NightSleep night) {
    final start = night.start;
    final end = night.end;
    String hm(DateTime t) =>
        '${t.hour.toString().padLeft(2, '0')}:'
        '${t.minute.toString().padLeft(2, '0')}';
    return '${start.year}-${_two(start.month)}-${_two(start.day)} · '
        '${hm(start)}–${hm(end)}';
  }

  static String _two(int v) => v.toString().padLeft(2, '0');
}

class _SectionTitle extends StatelessWidget {
  const _SectionTitle(this.text, this.theme);

  final String text;
  final ThemeData theme;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 8),
    child: Text(text, style: theme.textTheme.titleMedium),
  );
}
