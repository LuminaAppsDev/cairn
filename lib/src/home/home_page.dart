import 'package:cairn/src/format/duration_format.dart';
import 'package:cairn/src/health/health_metric.dart';
import 'package:cairn/src/profile/bmi.dart';
import 'package:cairn/src/profile/profile.dart';
import 'package:cairn/src/query/display_readings.dart';
import 'package:cairn/src/query/night_sleep.dart';
import 'package:cairn/src/shell/cairn_services.dart';
import 'package:cairn/src/storage/health_ingest_service.dart';
import 'package:cairn/src/sync/nextcloud_sync_target.dart';
import 'package:flutter/material.dart';

/// The overview home screen: at-a-glance latest values read from the local OMH
/// cache, plus a manual Refresh that ingests from the health store and syncs.
class HomePage extends StatefulWidget {
  /// Creates the home page.
  const HomePage({
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

class _HomePageState extends State<HomePage> {
  late Future<_Overview> _data = _load();
  bool _busy = false;

  Future<_Overview> _load() async {
    final query = widget.services.query;
    return _Overview(
      weight: await query.latestScalar(HealthMetric.weight),
      heartRate: await query.latestScalar(HealthMetric.heartRate),
      steps: await query.todayStepTotal(),
      lastNight: await query.lastNight(),
      profile: await widget.services.profileStore.read(),
    );
  }

  Future<void> _refresh() async {
    setState(() => _busy = true);
    String? error;
    try {
      final repo = widget.services.repository;
      final granted = await repo.requestAuthorization(
        HealthMetric.values.toSet(),
      );
      await HealthIngestService(
        repository: repo,
        store: widget.services.store,
      ).ingest(granted);
      if (await widget.services.coordinator.isConnected()) {
        await widget.services.coordinator.syncNow();
      }
    } on NextcloudSyncException catch (e) {
      error = 'Synced data is local only: ${e.message}';
    } on Exception catch (e) {
      error = 'Refresh failed: $e';
    }
    if (!mounted) return;
    setState(() {
      _busy = false;
      _data = _load();
    });
    if (error != null) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(error)));
    }
  }

  @override
  Widget build(BuildContext context) {
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
            tooltip: 'Refresh',
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _refresh,
        child: FutureBuilder<_Overview>(
          future: _data,
          builder: (context, snapshot) {
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
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        _BmiCard(
          weight: data.weight,
          profile: data.profile,
          onAddProfile: widget.onOpenSettings,
        ),
        _SleepCard(night: data.lastNight, onOpen: widget.onOpenSleep),
        Row(
          children: [
            Expanded(
              child: _StatCard(
                icon: Icons.directions_walk,
                label: 'Steps today',
                value: data.steps == null
                    ? '—'
                    : data.steps!.round().toString(),
              ),
            ),
            Expanded(
              child: _StatCard(
                icon: Icons.favorite_outline,
                label: 'Latest heart rate',
                value: data.heartRate == null
                    ? '—'
                    : '${data.heartRate!.value.round()} bpm',
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _Overview {
  const _Overview({
    required this.weight,
    required this.heartRate,
    required this.steps,
    required this.lastNight,
    required this.profile,
  });

  final ScalarReading? weight;
  final ScalarReading? heartRate;
  final double? steps;
  final NightSleep? lastNight;
  final Profile profile;
}

class _BmiCard extends StatelessWidget {
  const _BmiCard({
    required this.weight,
    required this.profile,
    required this.onAddProfile,
  });

  final ScalarReading? weight;
  final Profile profile;
  final VoidCallback onAddProfile;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final w = weight;
    final bmi = computeBmi(weightKg: w?.value, heightCm: profile.heightCm);

    if (w == null) {
      return const _InfoCard(
        icon: Icons.monitor_weight_outlined,
        title: 'Body weight',
        body: 'No weight recorded yet. Refresh after your health app has it.',
      );
    }
    final weightLine = '${w.value.toStringAsFixed(1)} kg';
    if (bmi == null) {
      // Non-prominent prompt: only when weight exists but height is missing.
      return Card(
        child: ListTile(
          leading: const Icon(Icons.straighten),
          title: Text('Add your height to see BMI ($weightLine)'),
          subtitle: const Text('Tap to set it in Settings'),
          onTap: onAddProfile,
        ),
      );
    }
    final color = bmi.category.isNormal ? Colors.green : Colors.orange;
    final age = profile.ageYears(DateTime.now());
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('BMI', style: theme.textTheme.labelMedium),
                Text(
                  bmi.value.toStringAsFixed(1),
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
                        bmi.category.label,
                        style: theme.textTheme.titleMedium,
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    age == null
                        ? 'Weight $weightLine'
                        : 'Weight $weightLine · age $age',
                    style: theme.textTheme.bodySmall,
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SleepCard extends StatelessWidget {
  const _SleepCard({required this.night, required this.onOpen});

  final NightSleep? night;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    final n = night;
    if (n == null) {
      return const _InfoCard(
        icon: Icons.bedtime_outlined,
        title: 'Sleep',
        body: 'No sleep tracked recently.',
      );
    }
    return Card(
      child: ListTile(
        leading: const Icon(Icons.bedtime),
        title: Text('Last night · ${formatHoursMinutes(n.totalSleep)} asleep'),
        subtitle: Text(
          n.hasStageBreakdown
              ? '${n.awakenings} awakenings · tap for stages'
              : 'tap for details',
        ),
        trailing: const Icon(Icons.chevron_right),
        onTap: onOpen,
      ),
    );
  }
}

class _StatCard extends StatelessWidget {
  const _StatCard({
    required this.icon,
    required this.label,
    required this.value,
  });

  final IconData icon;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
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
    );
  }
}

class _InfoCard extends StatelessWidget {
  const _InfoCard({
    required this.icon,
    required this.title,
    required this.body,
  });

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
