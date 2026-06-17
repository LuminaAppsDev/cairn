import 'package:cairn/src/health/health_metric.dart';
import 'package:cairn/src/health/health_source.dart';
import 'package:cairn/src/query/display_readings.dart';
import 'package:cairn/src/query/health_query_service.dart';
import 'package:cairn/src/query/night_sleep.dart';
import 'package:cairn/src/sleep/sleep_page.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// In-memory query so the widget test has no real file I/O (which can't
/// complete under the widget tester's fake-async).
class _FakeQuery implements HealthQueryService {
  _FakeQuery(this.nights);

  final List<NightSleep> nights;

  @override
  Future<List<NightSleep>> lastNNights(int n) async => nights.take(n).toList();

  @override
  Future<NightSleep?> lastNight() async => nights.isEmpty ? null : nights.first;

  @override
  Future<ScalarReading?> latestScalar(HealthMetric metric) async => null;

  @override
  Future<double?> todayStepTotal() async => null;
}

NightSleep _sampleNight() {
  final base = DateTime(2026, 6, 15, 23);
  return NightSleep(
    night: DateTime(2026, 6, 15),
    start: base,
    end: base.add(const Duration(hours: 6)),
    stages: [
      SleepStageReading(
        stage: SleepStage.deep,
        start: base,
        end: base.add(const Duration(hours: 2)),
      ),
      SleepStageReading(
        stage: SleepStage.awake,
        start: base.add(const Duration(hours: 2)),
        end: base.add(const Duration(hours: 3)),
      ),
      SleepStageReading(
        stage: SleepStage.light,
        start: base.add(const Duration(hours: 3)),
        end: base.add(const Duration(hours: 6)),
      ),
    ],
    totalSleep: const Duration(hours: 5),
    awakenings: 1,
    perStage: const {
      SleepStage.deep: Duration(hours: 2),
      SleepStage.light: Duration(hours: 3),
      SleepStage.awake: Duration(hours: 1),
    },
    isMainSleep: true,
    sources: const {'fitband'},
    timeInBed: const Duration(hours: 6),
    efficiency: 5 / 6,
  );
}

void main() {
  Widget app(List<NightSleep> nights) =>
      MaterialApp(home: SleepPage(query: _FakeQuery(nights)));

  testWidgets('shows the empty state when there is no sleep data', (
    tester,
  ) async {
    await tester.pumpWidget(app(const []));
    await tester.pumpAndSettle();
    expect(find.text('No sleep data yet'), findsOneWidget);
  });

  testWidgets('renders the hypnogram, breakdown and trend with data', (
    tester,
  ) async {
    await tester.pumpWidget(app([_sampleNight()]));
    await tester.pumpAndSettle();

    expect(find.text('Last night'), findsOneWidget);
    expect(find.byType(LineChart), findsOneWidget); // hypnogram
    expect(find.byType(PieChart), findsOneWidget); // stage breakdown
    // The trend is the last item in the ListView; scroll it into view.
    await tester.scrollUntilVisible(find.byType(BarChart), 200);
    expect(find.byType(BarChart), findsOneWidget); // trend
  });
}
