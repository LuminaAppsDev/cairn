import 'package:cairn/l10n/app_localizations.dart';
import 'package:cairn/src/onboarding/setup_guide_page.dart';
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
  /// Creates the sleep page reading from [query]. [revision] fires when new
  /// data lands in the cache (reload trigger); [onRefresh] ingests + syncs.
  const new({
    required this.query,
    required this.revision,
    required this.onRefresh,
    super.key,
  });

  /// The query service over the local OMH cache.
  final HealthQueryService query;

  /// Bumped when new data is ingested, so the page reloads from the cache.
  final Listenable revision;

  /// Pulls new data from the health store and syncs (pull-to-refresh).
  final Future<void> Function() onRefresh;

  @override
  State<SleepPage> createState() => _SleepPageState();
}

class _SleepPageState extends State<SleepPage> {
  late Future<List<NightSleep>> _nights;

  /// Index into the loaded nights (most-recent-first) for the detail panels;
  /// 0 is last night. The prev/next controls move it; a data reload resets it.
  int _selected = 0;

  @override
  void initState() {
    super.initState();
    _nights = widget.query.lastNNights(_trendNights);
    widget.revision.addListener(_reload);
  }

  @override
  void dispose() {
    widget.revision.removeListener(_reload);
    super.dispose();
  }

  void _reload() {
    if (!mounted) return;
    setState(() {
      _nights = widget.query.lastNNights(_trendNights);
      // New data → jump back to the most recent night.
      _selected = 0;
    });
  }

  Future<void> _refresh() async {
    // Ingest + sync; the revision bump reloads the nights via _reload.
    await widget.onRefresh();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(AppLocalizations.of(context).sleepTitle)),
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

  Widget _empty(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return ListView(
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
          l10n.sleepEmptyTitle,
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.titleMedium,
        ),
        const SizedBox(height: 8),
        Text(l10n.sleepEmptyBody, textAlign: TextAlign.center),
        const SizedBox(height: 16),
        Center(
          child: TextButton.icon(
            onPressed: () => Navigator.of(context).push<void>(
              MaterialPageRoute<void>(builder: (_) => const SetupGuidePage()),
            ),
            icon: const Icon(Icons.help_outline),
            label: Text(l10n.sleepHowToSetUp),
          ),
        ),
      ],
    );
  }

  Widget _content(BuildContext context, List<NightSleep> nights) {
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context);
    // build() routes an empty list to _empty, so nights is non-empty here, and
    // _reload resets _selected with the new data — this clamp is defence in
    // depth against an out-of-range selection, never a real transient.
    final index = _selected.clamp(0, nights.length - 1);
    final selected = nights[index];
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        _NightNavigator(
          // nights is most-recent-first, so a higher index is further back:
          // "older" steps forward in the list, "newer" steps back toward 0.
          title: index == 0
              ? l10n.sleepLastNight
              : MaterialLocalizations.of(context)
                    .formatMediumDate(selected.night),
          onOlder: index < nights.length - 1
              ? () => setState(() => _selected = index + 1)
              : null,
          onNewer: index > 0
              ? () => setState(() => _selected = index - 1)
              : null,
          theme: theme,
          l10n: l10n,
        ),
        const SizedBox(height: 4),
        Text(_dateLabel(selected), style: theme.textTheme.bodySmall),
        const SizedBox(height: 12),
        SleepSummaryTiles(night: selected),
        if (selected.sources.length > 1)
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: Text(
              l10n.sleepMultipleSources,
              style: theme.textTheme.bodySmall,
            ),
          ),
        const SizedBox(height: 24),
        _SectionTitle(l10n.sleepStagesSection, theme),
        HypnogramChart(night: selected),
        const SizedBox(height: 24),
        _SectionTitle(l10n.sleepBreakdownSection, theme),
        StageBreakdown(night: selected),
        const SizedBox(height: 24),
        _SectionTitle(l10n.sleepTrendSection(_trendNights), theme),
        SleepTrendChart(
          nights: nights,
          selected: selected,
          onSelect: (night) {
            final i = nights.indexWhere((n) => n.night == night.night);
            if (i >= 0) setState(() => _selected = i);
          },
        ),
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
  const new(this.text, this.theme);

  final String text;
  final ThemeData theme;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 8),
    child: Text(text, style: theme.textTheme.titleMedium),
  );
}

/// Header for the sleep deep-dive: the selected night's [title] flanked by
/// step-back / step-forward controls. A `null` callback disables its button
/// (at the ends of the available range).
class _NightNavigator extends StatelessWidget {
  const new({
    required this.title,
    required this.onOlder,
    required this.onNewer,
    required this.theme,
    required this.l10n,
  });

  final String title;
  final VoidCallback? onOlder;
  final VoidCallback? onNewer;
  final ThemeData theme;
  final AppLocalizations l10n;

  @override
  Widget build(BuildContext context) => Row(
    children: [
      Expanded(child: Text(title, style: theme.textTheme.titleLarge)),
      IconButton(
        icon: const Icon(Icons.chevron_left),
        tooltip: l10n.sleepOlderNight,
        onPressed: onOlder,
      ),
      IconButton(
        icon: const Icon(Icons.chevron_right),
        tooltip: l10n.sleepNewerNight,
        onPressed: onNewer,
      ),
    ],
  );
}
