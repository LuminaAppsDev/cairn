import 'dart:io';

import 'package:cairn/src/health/health_metric.dart';
import 'package:cairn/src/health/health_sample.dart';
import 'package:cairn/src/health/health_source.dart';
import 'package:cairn/src/health/sleep_aggregator.dart';
import 'package:cairn/src/omh/default_omh_mapper.dart';
import 'package:cairn/src/query/health_query_service.dart';
import 'package:cairn/src/storage/jsonl_omh_file_store.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late Directory tempRoot;
  late JsonlOmhFileStore store;
  late OmhHealthQueryService service;
  final mapper = DefaultOmhMapper();

  final now = DateTime(2026, 6, 16, 12);
  final lastNight = DateTime(2026, 6, 15, 23); // night of the 15th→16th

  setUp(() {
    tempRoot = Directory.systemTemp.createTempSync('cairn_query_test');
    store = JsonlOmhFileStore(root: tempRoot);
    service = OmhHealthQueryService(store: store, clock: () => now);
  });
  tearDown(() => tempRoot.deleteSync(recursive: true));

  HealthSource src(
    String name, {
    RecordingMethodKind method = RecordingMethodKind.automatic,
  }) => HealthSource(
    name: name,
    platform: HealthPlatform.googleHealthConnect,
    recordingMethod: method,
  );

  Future<void> putScalar(
    HealthMetric metric,
    DateTime at,
    double value,
    String unit,
    HealthSource source,
  ) async {
    final sample = ScalarSample(
      metric: metric,
      start: at,
      end: at,
      value: value,
      unit: unit,
      source: source,
    );
    await store.append(
      metric: metric,
      day: at,
      dataPoints: [mapper.toDataPoint(sample)],
    );
  }

  Future<void> putSteps(
    DateTime start,
    DateTime end,
    double value,
    HealthSource source,
  ) async {
    final sample = ScalarSample(
      metric: HealthMetric.steps,
      start: start,
      end: end,
      value: value,
      unit: 'steps',
      source: source,
    );
    await store.append(
      metric: HealthMetric.steps,
      day: start,
      dataPoints: [mapper.toDataPoint(sample)],
    );
  }

  SleepSegmentSample seg(
    DateTime start,
    DateTime end,
    SleepStage stage,
    HealthSource source,
  ) => SleepSegmentSample(start: start, end: end, source: source, stage: stage);

  Future<void> putStage(SleepSegmentSample s) async {
    await store.append(
      metric: HealthMetric.sleep,
      day: s.start,
      dataPoints: [mapper.toDataPoint(s)],
    );
  }

  Future<void> putEpisode(List<SleepSegmentSample> segments) async {
    final episode = const SleepEpisodeAggregator().aggregate(segments).first;
    await store.append(
      metric: HealthMetric.sleep,
      day: episode.start,
      dataPoints: [mapper.sleepEpisodeToDataPoint(episode)],
    );
  }

  test('latestScalar returns the most recent weight', () async {
    await putScalar(
      HealthMetric.weight,
      DateTime(2026, 6, 14, 8),
      80,
      'kg',
      src('scale'),
    );
    await putScalar(
      HealthMetric.weight,
      DateTime(2026, 6, 16, 9),
      86,
      'kg',
      src('scale'),
    );
    final reading = await service.latestScalar(HealthMetric.weight);
    expect(reading?.value, 86);
  });

  test('latestScalar returns null when there is no data', () async {
    expect(await service.latestScalar(HealthMetric.weight), isNull);
  });

  test('todayStepTotal dedups overlapping sources, then sums', () async {
    final t0 = DateTime(2026, 6, 16, 6);
    final t1 = t0.add(const Duration(minutes: 1));
    final t2 = t1.add(const Duration(minutes: 1));
    await putSteps(t0, t1, 100, src('phone'));
    await putSteps(t0, t1, 90, src('fitband')); // wearable preferred
    await putSteps(t1, t2, 50, src('phone'));
    expect(await service.todayStepTotal(), 140);
  });

  test(
    'lastNight builds a stages-only night with per-stage + efficiency',
    () async {
      await putStage(
        seg(
          lastNight,
          lastNight.add(const Duration(hours: 2)),
          SleepStage.deep,
          src('fitband'),
        ),
      );
      await putStage(
        seg(
          lastNight.add(const Duration(hours: 2)),
          lastNight.add(const Duration(hours: 3)),
          SleepStage.awake,
          src('fitband'),
        ),
      );
      await putStage(
        seg(
          lastNight.add(const Duration(hours: 3)),
          lastNight.add(const Duration(hours: 6)),
          SleepStage.light,
          src('fitband'),
        ),
      );

      final night = await service.lastNight();
      expect(night, isNotNull);
      expect(night!.perStage[SleepStage.deep], const Duration(hours: 2));
      expect(night.perStage[SleepStage.light], const Duration(hours: 3));
      expect(night.awakenings, 1);
      expect(night.totalSleep, const Duration(hours: 5));
      expect(night.hasStageBreakdown, isTrue);
      expect(night.efficiency, closeTo(5 / 6, 0.001)); // 5h asleep / 6h in bed
    },
  );

  test('a session-only night has no breakdown and null efficiency', () async {
    await putStage(
      seg(
        lastNight,
        lastNight.add(const Duration(hours: 7)),
        SleepStage.session,
        src('manual', method: RecordingMethodKind.manual),
      ),
    );
    final night = await service.lastNight();
    expect(night!.totalSleep, const Duration(hours: 7));
    expect(night.hasStageBreakdown, isFalse);
    expect(night.efficiency, isNull);
    expect(night.timeInBed, isNull);
  });

  test('crash-replay duplicate segments are not double-counted', () async {
    final s = seg(
      lastNight,
      lastNight.add(const Duration(hours: 7)),
      SleepStage.asleepUnspecified,
      src('fitband'),
    );
    await putStage(s);
    await putStage(s); // re-ingest writes a fresh UUID for the same content
    final night = await service.lastNight();
    expect(night!.totalSleep, const Duration(hours: 7));
    expect(night.stages, hasLength(1));
  });

  test(
    'an exact-window multi-source collision keeps the preferred source',
    () async {
      final end = lastNight.add(const Duration(hours: 7));
      await putStage(
        seg(lastNight, end, SleepStage.asleepUnspecified, src('phone')),
      );
      await putStage(
        seg(lastNight, end, SleepStage.asleepUnspecified, src('fitband')),
      );
      final night = await service.lastNight();
      expect(night!.stages.single.source?.name, 'fitband');
      expect(night.totalSleep, const Duration(hours: 7));
    },
  );

  test('a stored sleep-episode is attached to the night', () async {
    final segments = [
      seg(
        lastNight,
        lastNight.add(const Duration(hours: 7)),
        SleepStage.asleepUnspecified,
        src('fitband'),
      ),
    ];
    await putStage(segments.single);
    await putEpisode(segments);
    final night = await service.lastNight();
    expect(night!.storedEpisode, isNotNull);
    expect(night.storedEpisode!.totalSleep, const Duration(hours: 7));
  });

  test('lastNNights returns recent nights, most-recent first', () async {
    await putStage(
      seg(
        DateTime(2026, 6, 13, 23),
        DateTime(2026, 6, 14, 5),
        SleepStage.asleepUnspecified,
        src('fitband'),
      ),
    );
    await putStage(
      seg(
        lastNight,
        lastNight.add(const Duration(hours: 6)),
        SleepStage.asleepUnspecified,
        src('fitband'),
      ),
    );
    final nights = await service.lastNNights(7);
    expect(nights.length, greaterThanOrEqualTo(2));
    expect(nights.first.start.isAfter(nights.last.start), isTrue);
  });
}
