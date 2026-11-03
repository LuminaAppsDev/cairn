import 'package:cairn/l10n/app_localizations.dart';
import 'package:cairn/src/format/duration_format.dart';
import 'package:cairn/src/format/locale_format.dart';
import 'package:cairn/src/query/display_readings.dart';
import 'package:cairn/src/query/health_query_service.dart';
import 'package:flutter/material.dart';

/// How many days of workouts the screen lists.
const int _activityDays = 30;

/// Activity detail screen: the recent workouts over the last [_activityDays]
/// days, newest first, each with duration / distance / energy where reported.
class ActivityPage extends StatefulWidget {
  /// Creates the activity page reading from [query].
  const new({required this.query, super.key});

  /// The query service over the local OMH cache.
  final HealthQueryService query;

  @override
  State<ActivityPage> createState() => _ActivityPageState();
}

class _ActivityPageState extends State<ActivityPage> {
  late final Future<List<WorkoutReading>> _workouts = widget.query
      .recentWorkouts(days: _activityDays);

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Scaffold(
      appBar: AppBar(title: Text(l10n.activityTitle)),
      body: FutureBuilder<List<WorkoutReading>>(
        future: _workouts,
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return Center(child: Text(l10n.metricLoadError));
          }
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          final workouts = snapshot.data!;
          if (workouts.isEmpty) {
            return Center(child: Text(l10n.activityEmpty));
          }
          return _content(context, workouts);
        },
      ),
    );
  }

  Widget _content(BuildContext context, List<WorkoutReading> workouts) {
    final l10n = AppLocalizations.of(context);
    final theme = Theme.of(context);
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Text(
          l10n.activityWorkoutCount(workouts.length),
          style: theme.textTheme.titleMedium,
        ),
        Text(
          l10n.metricLastDays(_activityDays),
          style: theme.textTheme.bodySmall,
        ),
        const SizedBox(height: 12),
        for (final w in workouts) _WorkoutTile(workout: w),
      ],
    );
  }
}

class _WorkoutTile extends StatelessWidget {
  const new({required this.workout});

  final WorkoutReading workout;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final locale = Localizations.localeOf(context).toLanguageTag();
    final parts = <String>[formatHoursMinutes(workout.duration, l10n)];
    final distance = workout.distanceMeters;
    if (distance != null && distance > 0) {
      parts.add(
        l10n.workoutDistance(formatDecimal(distance / 1000, locale: locale)),
      );
    }
    final kcal = workout.kcal;
    if (kcal != null && kcal > 0) {
      parts.add(l10n.workoutEnergy(formatInteger(kcal, locale: locale)));
    }
    final start = workout.start;
    final date = '${start.year}-${_two(start.month)}-${_two(start.day)}';
    return Card(
      child: ListTile(
        leading: const Icon(Icons.fitness_center),
        title: Text(_prettyName(workout.activityName)),
        subtitle: Text(parts.join(' · ')),
        trailing: Text(date, style: Theme.of(context).textTheme.bodySmall),
      ),
    );
  }

  /// Turns a platform activity name (`STRENGTH_TRAINING`, `running`) into a
  /// readable label. The set is open-ended and platform-supplied, so it is
  /// presented as data (not translated), like a source name.
  static String _prettyName(String raw) {
    final cleaned = raw.replaceAll('_', ' ').trim().toLowerCase();
    if (cleaned.isEmpty) return raw;
    return cleaned[0].toUpperCase() + cleaned.substring(1);
  }

  static String _two(int v) => v.toString().padLeft(2, '0');
}
