import 'package:cairn/l10n/app_localizations.dart';
import 'package:cairn/src/health/health_metric.dart';
import 'package:cairn/src/health/health_source.dart';
import 'package:cairn/src/query/display_readings.dart';
import 'package:cairn/src/query/health_query_service.dart';
import 'package:cairn/src/query/metric_series.dart';
import 'package:cairn/src/query/night_sleep.dart';
import 'package:cairn/src/sleep/sleep_page.dart';
import 'package:cairn/src/sleep/sleep_visuals.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// In-memory query so the widget test has no real file I/O (which can't
/// complete under the widget tester's fake-async).
class _FakeQuery implements HealthQueryService {
  new(this.nights);

  List<NightSleep> nights;

  @override
  Future<List<NightSleep>> lastNNights(int n) async => nights.take(n).toList();

  @override
  Future<NightSleep?> lastNight() async => nights.isEmpty ? null : nights.first;

  @override
  Future<ScalarReading?> latestScalar(HealthMetric metric) async => null;

  @override
  Future<double?> todayStepTotal() async => null;

  @override
  Future<List<ScalarReading>> scalarSeries(
    HealthMetric metric, {
    int days = 90,
  }) async => const [];

  @override
  Future<List<DailyValue>> dailySteps({int days = 14}) async => const [];

  @override
  Future<List<DailyStat>> dailyHeartRate({int days = 14}) async => const [];

  @override
  Future<List<WorkoutReading>> recentWorkouts({int days = 30}) async =>
      const [];
}

NightSleep _sampleNight([DateTime? base]) {
  final start = base ?? DateTime(2026, 6, 15, 23);
  return NightSleep(
    night: DateTime(start.year, start.month, start.day),
    start: start,
    end: start.add(const Duration(hours: 6)),
    stages: [
      SleepStageReading(
        stage: SleepStage.deep,
        start: start,
        end: start.add(const Duration(hours: 2)),
      ),
      SleepStageReading(
        stage: SleepStage.awake,
        start: start.add(const Duration(hours: 2)),
        end: start.add(const Duration(hours: 3)),
      ),
      SleepStageReading(
        stage: SleepStage.light,
        start: start.add(const Duration(hours: 3)),
        end: start.add(const Duration(hours: 6)),
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
  Widget wrap(Widget home) => MaterialApp(
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    home: home,
  );

  Widget app(List<NightSleep> nights) => wrap(
    SleepPage(
      query: _FakeQuery(nights),
      revision: ValueNotifier<int>(0),
      onRefresh: () async {},
    ),
  );

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

  testWidgets('hypnogram draws one coloured bar per stage segment', (
    tester,
  ) async {
    await tester.pumpWidget(app([_sampleNight()]));
    await tester.pumpAndSettle();

    final chart = tester.widget<LineChart>(find.byType(LineChart));
    final bars = chart.data.lineBarsData;
    // One bar per segment (deep, awake, light) — not a single stepped line —
    // each drawn in its own stage colour so the phases stand apart.
    expect(bars, hasLength(3));
    expect(bars.any((b) => b.isStepLineChart), isFalse);
    expect(bars.map((b) => b.color).toSet(), {
      stageColor(SleepStage.deep),
      stageColor(SleepStage.awake),
      stageColor(SleepStage.light),
    });
  });

  testWidgets('hypnogram tooltip names the stage and its clock span', (
    tester,
  ) async {
    await tester.pumpWidget(app([_sampleNight()]));
    await tester.pumpAndSettle();

    final chart = tester.widget<LineChart>(find.byType(LineChart));
    expect(chart.data.lineTouchData.enabled, isTrue);

    final l10n = AppLocalizations.of(tester.element(find.byType(LineChart)));
    final bars = chart.data.lineBarsData;
    final tooltip = chart.data.lineTouchData.touchTooltipData;

    // The first bar is the deep segment (23:00–01:00): its tooltip names the
    // stage and shows both clock times.
    final items = tooltip.getTooltipItems([
      LineBarSpot(bars.first, 0, bars.first.spots.first),
    ]);
    expect(items, hasLength(1));
    expect(items.first!.text, contains(stageLabel(l10n, SleepStage.deep)));
    expect(items.first!.text, contains(':')); // a formatted clock time

    // Two touches on the same bar collapse to a single tooltip line.
    final deduped = tooltip.getTooltipItems([
      LineBarSpot(bars.first, 0, bars.first.spots.first),
      LineBarSpot(bars.first, 0, bars.first.spots.last),
    ]);
    expect(deduped[1], isNull);
  });

  testWidgets('pages from last night back to an earlier night', (tester) async {
    await tester.pumpWidget(
      app([
        _sampleNight(), // newest: night of 2026-06-15
        _sampleNight(DateTime(2026, 6, 14, 23)), // older: 2026-06-14
      ]),
    );
    await tester.pumpAndSettle();

    final olderButton = find.widgetWithIcon(IconButton, Icons.chevron_left);
    final newerButton = find.widgetWithIcon(IconButton, Icons.chevron_right);

    // Starts on the most recent night: title is "Last night" and the
    // step-forward (newer) control is disabled.
    expect(find.text('Last night'), findsOneWidget);
    expect(find.textContaining('2026-06-15'), findsWidgets);
    expect(tester.widget<IconButton>(newerButton).onPressed, isNull);

    // Step back to the earlier night.
    await tester.tap(olderButton);
    await tester.pumpAndSettle();

    expect(find.text('Last night'), findsNothing);
    expect(find.textContaining('2026-06-14'), findsWidgets);
    // Now the step-back (older) control is disabled at the end of the range.
    expect(tester.widget<IconButton>(olderButton).onPressed, isNull);
  });

  testWidgets('tapping a trend bar selects that night', (tester) async {
    // A tall viewport so the whole page (incl. the trend) is on-screen and the
    // tap target isn't scrolled out from under the tap.
    tester.view.physicalSize = const Size(1200, 2600);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      app([
        _sampleNight(), // newest: 2026-06-15
        _sampleNight(DateTime(2026, 6, 14, 23)), // older: 2026-06-14
      ]),
    );
    await tester.pumpAndSettle();

    // Detail starts on the newest night.
    expect(find.text('Last night'), findsOneWidget);

    // Trend is ordered oldest→newest, so index 0 is the 14th (leftmost column).
    await tester.tap(find.byKey(const ValueKey('sleepTrendTap-0')));
    await tester.pumpAndSettle();

    // The detail panels switched to the tapped (earlier) night.
    expect(find.text('Last night'), findsNothing);
    expect(find.textContaining('2026-06-14'), findsWidgets);

    // …and the highlight moved to that bar: full-strength colour on the 14th,
    // dimmed on the 15th.
    final chart = tester.widget<BarChart>(find.byType(BarChart));
    final colours = chart.data.barGroups
        .map((g) => g.barRods.first.color!)
        .toList();
    expect(colours[0].a, 1.0); // 14th (now selected)
    expect(colours[1].a, lessThan(1.0)); // 15th (dimmed)
  });

  testWidgets('reloads when the data revision changes', (tester) async {
    final query = _FakeQuery([]);
    final revision = ValueNotifier<int>(0);
    await tester.pumpWidget(
      wrap(SleepPage(query: query, revision: revision, onRefresh: () async {})),
    );
    await tester.pumpAndSettle();
    expect(find.text('No sleep data yet'), findsOneWidget);

    // New data is ingested elsewhere → bump the shared revision.
    query.nights = [_sampleNight()];
    revision.value++;
    await tester.pumpAndSettle();

    expect(find.text('No sleep data yet'), findsNothing);
    expect(find.text('Last night'), findsOneWidget);
  });
}
