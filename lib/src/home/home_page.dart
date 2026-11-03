import 'package:cairn/l10n/app_localizations.dart';
import 'package:cairn/src/format/duration_format.dart';
import 'package:cairn/src/format/locale_format.dart';
import 'package:cairn/src/health/health_metric.dart';
import 'package:cairn/src/metrics/activity_page.dart';
import 'package:cairn/src/metrics/heart_rate_page.dart';
import 'package:cairn/src/metrics/steps_page.dart';
import 'package:cairn/src/metrics/weight_page.dart';
import 'package:cairn/src/profile/bmi.dart';
import 'package:cairn/src/profile/bmi_labels.dart';
import 'package:cairn/src/profile/profile.dart';
import 'package:cairn/src/query/display_readings.dart';
import 'package:cairn/src/query/night_sleep.dart';
import 'package:cairn/src/shell/cairn_services.dart';
import 'package:cairn/src/shell/refresh_feedback.dart';
import 'package:flutter/material.dart';

/// The overview home screen: at-a-glance latest values read from the local OMH
/// cache, plus a manual Refresh that ingests from the health store and syncs.
class HomePage extends StatefulWidget {
  /// Creates the home page.
  const new({
    required this.services,
    required this.onOpenSleep,
    required this.onOpenSettings,
    super.key,
  });

  /// Shared app services.
  final CairnServices services;

  /// Switches to the Sleep tab.
  final VoidCallback onOpenSleep;

  /// Switches to the Settings tab (e.g. to enter the profile).
  final VoidCallback onOpenSettings;

  @override
  State<HomePage> createState() => _HomePageState();
}

/// Recent-workout window for the home Activity card.
const int _recentWorkoutDays = 7;

class _HomePageState extends State<HomePage> {
  late Future<_Overview> _data = _load();
  bool _busy = false;
  bool _backupDismissed = false;

  @override
  void initState() {
    super.initState();
    widget.services.dataRevision.addListener(_reload);
  }

  @override
  void dispose() {
    widget.services.dataRevision.removeListener(_reload);
    super.dispose();
  }

  /// Reloads the overview when new data lands in the cache (e.g. after a
  /// refresh triggered from any screen).
  void _reload() {
    if (!mounted) return;
    setState(() {
      _data = _load();
    });
  }

  Future<_Overview> _load() async {
    final query = widget.services.query;
    return _Overview(
      weight: await query.latestScalar(HealthMetric.weight),
      heartRate: await query.latestScalar(HealthMetric.heartRate),
      steps: await query.todayStepTotal(),
      lastNight: await query.lastNight(),
      workoutCount: (await query.recentWorkouts(days: _recentWorkoutDays))
          .length,
    );
  }

  void _push(Widget page) =>
      Navigator.of(context)
          .push<void>(MaterialPageRoute<void>(builder: (_) => page));

  Future<void> _refresh() async {
    final messenger = ScaffoldMessenger.of(context);
    final l10n = AppLocalizations.of(context);
    setState(() => _busy = true);
    try {
      // The bump inside refresh() reloads the cards via _reload.
      final result = await widget.services.refresh();
      if (!mounted) return;
      final message = result.localizedMessage(l10n);
      if (message != null) {
        messenger.showSnackBar(SnackBar(content: Text(message)));
      }
    } finally {
      // In `finally` so the spinner can never be left turning if anything
      // escapes the call.
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Scaffold(
      appBar: AppBar(
        title: const Text('Cairn'),
        actions: [
          IconButton(
            onPressed: _busy ? null : _refresh,
            icon: _busy
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.refresh),
            tooltip: l10n.actionRefresh,
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _refresh,
        child: FutureBuilder<_Overview>(
          future: _data,
          builder: (context, snapshot) {
            if (snapshot.hasError) {
              // Scrollable so pull-to-refresh still works to retry.
              return ListView(
                padding: const EdgeInsets.all(24),
                children: [Center(child: Text(l10n.metricLoadError))],
              );
            }
            if (!snapshot.hasData) {
              return const Center(child: CircularProgressIndicator());
            }
            return _content(context, snapshot.data!);
          },
        ),
      ),
    );
  }

  Widget _content(BuildContext context, _Overview data) {
    final l10n = AppLocalizations.of(context);
    final locale = Localizations.localeOf(context).toLanguageTag();
    final query = widget.services.query;
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        ValueListenableBuilder<Profile>(
          valueListenable: widget.services.profile,
          builder: (context, profile, _) => _BmiCard(
            weight: data.weight,
            profile: profile,
            onAddProfile: widget.onOpenSettings,
            onOpenWeight: () => _push(WeightPage(query: query)),
          ),
        ),
        _SleepCard(night: data.lastNight, onOpen: widget.onOpenSleep),
        Row(
          children: [
            Expanded(
              child: _StatCard(
                icon: Icons.directions_walk,
                label: l10n.homeStepsToday,
                value: data.steps == null
                    ? '—'
                    : formatInteger(data.steps!, locale: locale),
                onTap: () => _push(StepsPage(query: query)),
              ),
            ),
            Expanded(
              child: _StatCard(
                icon: Icons.favorite_outline,
                label: l10n.homeLatestHeartRate,
                value: data.heartRate == null
                    ? '—'
                    : l10n.homeHeartRateValue(
                        data.heartRate!.value.round().toString(),
                      ),
                onTap: () => _push(HeartRatePage(query: query)),
              ),
            ),
          ],
        ),
        Card(
          child: ListTile(
            leading: const Icon(Icons.fitness_center),
            title: Text(l10n.activityTitle),
            subtitle: Text(l10n.homeActivityRecent(data.workoutCount)),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => _push(ActivityPage(query: query)),
          ),
        ),
        if (!_backupDismissed)
          _BackupNudge(
            onDismiss: () => setState(() => _backupDismissed = true),
          ),
      ],
    );
  }
}

class _Overview {
  const new({
    required this.weight,
    required this.heartRate,
    required this.steps,
    required this.lastNight,
    required this.workoutCount,
  });

  final ScalarReading? weight;
  final ScalarReading? heartRate;
  final double? steps;
  final NightSleep? lastNight;
  final int workoutCount;
}

class _BmiCard extends StatelessWidget {
  const new({
    required this.weight,
    required this.profile,
    required this.onAddProfile,
    required this.onOpenWeight,
  });

  final ScalarReading? weight;
  final Profile profile;
  final VoidCallback onAddProfile;
  final VoidCallback onOpenWeight;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context);
    final locale = Localizations.localeOf(context).toLanguageTag();
    final w = weight;
    final bmi = computeBmi(weightKg: w?.value, heightCm: profile.heightCm);

    if (w == null) {
      return _InfoCard(
        icon: Icons.monitor_weight_outlined,
        title: l10n.bmiBodyWeightTitle,
        body: l10n.bmiNoWeight,
      );
    }
    final weightLine = '${formatDecimal(w.value, locale: locale)} kg';
    if (bmi == null) {
      // Non-prominent prompt: only when weight exists but height is missing.
      return Card(
        child: ListTile(
          leading: const Icon(Icons.straighten),
          title: Text(l10n.bmiAddHeightTitle(weightLine)),
          subtitle: Text(l10n.bmiAddHeightSubtitle),
          onTap: onAddProfile,
        ),
      );
    }
    final color = bmi.category.isNormal ? Colors.green : Colors.orange;
    final age = profile.ageYears(DateTime.now());
    return Card(
      child: InkWell(
        onTap: onOpenWeight,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(l10n.bmiLabel, style: theme.textTheme.labelMedium),
                  Text(
                    formatDecimal(bmi.value, locale: locale),
                    style: theme.textTheme.headlineMedium,
                  ),
                ],
              ),
              const SizedBox(width: 20),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(Icons.circle, size: 12, color: color),
                        const SizedBox(width: 6),
                        Text(
                          bmiCategoryLabel(l10n, bmi.category),
                          style: theme.textTheme.titleMedium,
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      age == null
                          ? l10n.bmiWeightOnly(weightLine)
                          : l10n.bmiWeightAndAge(weightLine, age),
                      style: theme.textTheme.bodySmall,
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SleepCard extends StatelessWidget {
  const new({required this.night, required this.onOpen});

  final NightSleep? night;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final n = night;
    if (n == null) {
      return _InfoCard(
        icon: Icons.bedtime_outlined,
        title: l10n.homeSleepTitle,
        body: l10n.homeSleepNone,
      );
    }
    return Card(
      child: ListTile(
        leading: const Icon(Icons.bedtime),
        title: Text(
          l10n.homeSleepLastNight(formatHoursMinutes(n.totalSleep, l10n)),
        ),
        subtitle: Text(
          n.hasStageBreakdown
              ? l10n.homeSleepStages(n.awakenings)
              : l10n.homeSleepDetails,
        ),
        trailing: const Icon(Icons.chevron_right),
        onTap: onOpen,
      ),
    );
  }
}

class _StatCard extends StatelessWidget {
  const new({
    required this.icon,
    required this.label,
    required this.value,
    this.onTap,
  });

  final IconData icon;
  final String label;
  final String value;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(icon, color: theme.colorScheme.primary),
              const SizedBox(height: 8),
              Text(value, style: theme.textTheme.titleLarge),
              Text(label, style: theme.textTheme.bodySmall),
            ],
          ),
        ),
      ),
    );
  }
}

/// A gentle, dismissible reminder that the synced files are the only long-term
/// copy of the user's history (DESIGN.md §10.2).
class _BackupNudge extends StatelessWidget {
  const new({required this.onDismiss});

  final VoidCallback onDismiss;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context);
    return Card(
      color: theme.colorScheme.surfaceContainerHighest,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 8, 12),
        child: Row(
          children: [
            Icon(
              Icons.cloud_outlined,
              size: 20,
              color: theme.colorScheme.primary,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(l10n.backupNudge, style: theme.textTheme.bodySmall),
            ),
            IconButton(
              icon: const Icon(Icons.close, size: 18),
              tooltip: MaterialLocalizations.of(context).closeButtonTooltip,
              onPressed: onDismiss,
            ),
          ],
        ),
      ),
    );
  }
}

class _InfoCard extends StatelessWidget {
  const new({required this.icon, required this.title, required this.body});

  final IconData icon;
  final String title;
  final String body;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            Icon(icon, color: theme.colorScheme.primary),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: theme.textTheme.titleMedium),
                  const SizedBox(height: 4),
                  Text(body, style: theme.textTheme.bodySmall),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
