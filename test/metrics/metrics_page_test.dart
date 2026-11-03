import 'dart:io';

import 'package:cairn/l10n/app_localizations.dart';
import 'package:cairn/src/health/health_metric.dart';
import 'package:cairn/src/metrics/activity_page.dart';
import 'package:cairn/src/metrics/heart_rate_page.dart';
import 'package:cairn/src/metrics/steps_page.dart';
import 'package:cairn/src/metrics/weight_page.dart';
import 'package:cairn/src/query/display_readings.dart';
import 'package:cairn/src/query/health_query_service.dart';
import 'package:cairn/src/query/metric_series.dart';
import 'package:cairn/src/query/night_sleep.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// In-memory query so the widget tests have no real file I/O.
class _FakeQuery implements HealthQueryService {
  List<ScalarReading> weight = const [];
  List<DailyValue> steps = const [];
  List<DailyStat> heartRate = const [];
  List<WorkoutReading> workouts = const [];
  ScalarReading? latestHr;

  /// When true, reads throw to exercise the error branch.
  bool fail = false;

  @override
  Future<List<ScalarReading>> scalarSeries(
    HealthMetric metric, {
    int days = 90,
  }) async {
    if (fail) throw const FileSystemException('boom');
    return metric == HealthMetric.weight ? weight : const [];
  }

  @override
  Future<List<DailyValue>> dailySteps({int days = 14}) async => steps;

  @override
  Future<List<DailyStat>> dailyHeartRate({int days = 14}) async => heartRate;

  @override
  Future<List<WorkoutReading>> recentWorkouts({int days = 30}) async =>
      workouts;

  @override
  Future<ScalarReading?> latestScalar(HealthMetric metric) async => latestHr;

  @override
  Future<double?> todayStepTotal() async => null;

  @override
  Future<NightSleep?> lastNight() async => null;

  @override
  Future<List<NightSleep>> lastNNights(int n) async => const [];
}

void main() {
  Widget wrap(Widget home) => MaterialApp(
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    home: home,
  );

  ScalarReading kg(int day, double value) =>
      ScalarReading(value: value, unit: 'kg', at: DateTime(2026, 6, day));

  testWidgets('weight page shows the trend and latest/change tiles', (
    tester,
  ) async {
    final query = _FakeQuery()..weight = [kg(10, 80), kg(16, 82)];
    await tester.pumpWidget(wrap(WeightPage(query: query)));
    await tester.pumpAndSettle();
    expect(find.text('Weight'), findsWidgets); // app bar title
    expect(find.text('Latest'), findsOneWidget);
    expect(find.text('Change'), findsOneWidget);
    expect(find.text('+2.0 kg'), findsOneWidget);
    expect(find.byType(LineChart), findsOneWidget);
  });

  testWidgets('weight page shows the empty state with no data', (tester) async {
    await tester.pumpWidget(wrap(WeightPage(query: _FakeQuery())));
    await tester.pumpAndSettle();
    expect(find.text('No weight data yet.'), findsOneWidget);
  });

  testWidgets('steps page renders a bar chart', (tester) async {
    final query = _FakeQuery()
      ..steps = [
        DailyValue(day: DateTime(2026, 6, 15), value: 8000),
        DailyValue(day: DateTime(2026, 6, 16), value: 12000),
      ];
    await tester.pumpWidget(wrap(StepsPage(query: query)));
    await tester.pumpAndSettle();
    expect(find.text('Today'), findsOneWidget);
    expect(find.byType(BarChart), findsOneWidget);
  });

  testWidgets('heart-rate page shows tiles and the average chart', (
    tester,
  ) async {
    final query = _FakeQuery()
      ..latestHr = ScalarReading(
        value: 72,
        unit: 'bpm',
        at: DateTime(2026, 6, 16),
      )
      ..heartRate = [
        DailyStat(
          day: DateTime(2026, 6, 15),
          min: 55,
          mean: 70,
          max: 130,
          count: 100,
        ),
        DailyStat(
          day: DateTime(2026, 6, 16),
          min: 58,
          mean: 74,
          max: 140,
          count: 100,
        ),
      ];
    await tester.pumpWidget(wrap(HeartRatePage(query: query)));
    await tester.pumpAndSettle();
    expect(find.text('Latest'), findsOneWidget);
    expect(find.text('Range'), findsOneWidget);
    expect(find.text('55–140'), findsOneWidget); // min–max across the window
    expect(find.byType(LineChart), findsOneWidget);
  });

  testWidgets('activity page lists workouts newest-first', (tester) async {
    final query = _FakeQuery()
      ..workouts = [
        WorkoutReading(
          activityName: 'RUNNING',
          start: DateTime(2026, 6, 16, 7),
          end: DateTime(2026, 6, 16, 8),
          distanceMeters: 8000,
        ),
      ];
    await tester.pumpWidget(wrap(ActivityPage(query: query)));
    await tester.pumpAndSettle();
    expect(find.text('Running'), findsOneWidget); // prettified name
    expect(find.textContaining('8.0 km'), findsOneWidget);
  });

  testWidgets('activity page shows the empty state', (tester) async {
    await tester.pumpWidget(wrap(ActivityPage(query: _FakeQuery())));
    await tester.pumpAndSettle();
    expect(find.text('No workouts yet.'), findsOneWidget);
  });

  testWidgets('weight chart Y-axis uses round, non-wrapping labels', (
    tester,
  ) async {
    // A tiny spread (<1 kg) used to render dense, full-precision labels that
    // wrapped to two lines. The axis now snaps to a 0.2 step.
    final query = _FakeQuery()
      ..weight = [kg(14, 72.7), kg(15, 73), kg(16, 73.5)];
    await tester.pumpWidget(wrap(WeightPage(query: query)));
    await tester.pumpAndSettle();
    expect(find.text('73.0'), findsWidgets); // a round step tick
    expect(find.text('72.7'), findsNothing); // raw value is not an axis label
  });

  testWidgets('detail page surfaces a generic error on read failure', (
    tester,
  ) async {
    final query = _FakeQuery()..fail = true;
    await tester.pumpWidget(wrap(WeightPage(query: query)));
    await tester.pumpAndSettle();
    expect(find.text("Couldn't load this data."), findsOneWidget);
  });
}
