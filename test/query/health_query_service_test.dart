import 'dart:io';

import 'package:cairn/src/health/health_metric.dart';
import 'package:cairn/src/health/health_sample.dart';
import 'package:cairn/src/health/health_source.dart';
import 'package:cairn/src/health/sleep_aggregator.dart';
import 'package:cairn/src/omh/default_omh_mapper.dart';
import 'package:cairn/src/omh/omh_time.dart';
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

  // Writes a scalar whose OMH header `creation_date_time` (the ingest stamp the
  // read path orders corrections by) is pinned to [ingestedAt].
  Future<void> putScalarIngestedAt(
    HealthMetric metric,
    DateTime at,
    double value,
    String unit,
    HealthSource source,
    DateTime ingestedAt,
  ) async {
    final stamped = DefaultOmhMapper(clock: () => ingestedAt);
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
      dataPoints: [stamped.toDataPoint(sample)],
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

  // Writes a step record whose OMH header `creation_date_time` (the ingest
  // stamp the read path breaks same-window ties by) is pinned to [ingestedAt].
  Future<void> putStepsIngestedAt(
    DateTime start,
    DateTime end,
    double value,
    HealthSource source,
    DateTime ingestedAt,
  ) async {
    final stamped = DefaultOmhMapper(clock: () => ingestedAt);
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
      dataPoints: [stamped.toDataPoint(sample)],
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

  Future<void> putWorkout(
    DateTime start,
    DateTime end,
    String name,
    HealthSource source, {
    double? distance,
    double? kcal,
  }) async {
    final sample = WorkoutSample(
      start: start,
      end: end,
      source: source,
      activityName: name,
      totalDistanceMeters: distance,
      totalEnergyKcal: kcal,
    );
    await store.append(
      metric: HealthMetric.activity,
      day: start,
      dataPoints: [mapper.toDataPoint(sample)],
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

  test('a same-instant correction shows the latest-ingested value', () async {
    final at = DateTime(2026, 6, 15, 8);
    final scale = src('scale', method: RecordingMethodKind.manual);
    // A typo fixed in the health app: the same instant + source is re-read and
    // re-ingested a day later with the corrected value. Both lines are on disk
    // (append-only); the read path must surface the later-ingested one.
    await putScalarIngestedAt(
      HealthMetric.weight,
      at,
      80,
      'kg',
      scale,
      DateTime(2026, 6, 15, 8, 0, 1),
    );
    await putScalarIngestedAt(
      HealthMetric.weight,
      at,
      78,
      'kg',
      scale,
      DateTime(2026, 6, 16, 9),
    );
    expect((await service.latestScalar(HealthMetric.weight))?.value, 78);
    final series = await service.scalarSeries(HealthMetric.weight, days: 30);
    expect(series.map((r) => r.value).toList(), [78]);
  });

  // A body-weight datapoint whose header omits `creation_date_time`, to
  // exercise the unknown-ingest-time tie-break.
  Future<void> putWeightNoStamp(
    DateTime at,
    double value,
    String source,
  ) async {
    await store.append(
      metric: HealthMetric.weight,
      day: at,
      dataPoints: [
        {
          'header': {
            'id': 'x',
            'schema_id': {
              'namespace': 'omh',
              'name': 'body-weight',
              'version': '2.0',
            },
            'acquisition_provenance': {
              'source_name': source,
              'modality': 'self-reported',
            },
          },
          'body': {
            'body_weight': {'value': value, 'unit': 'kg'},
            'effective_time_frame': {'date_time': omhDateTime(at)},
          },
        },
      ],
    );
  }

  test('with no ingest stamp, the first-seen reading is kept', () async {
    final at = DateTime(2026, 6, 15, 8);
    // Neither datapoint carries creation_date_time, so an unknown ingest time
    // never supersedes — the first-written reading is the one shown.
    await putWeightNoStamp(at, 80, 'scale');
    await putWeightNoStamp(at, 78, 'scale');
    expect((await service.latestScalar(HealthMetric.weight))?.value, 80);
  });

  test('a same-instant reading from a different source is kept', () async {
    final at = DateTime(2026, 6, 15, 8);
    // Distinct sources are not a correction of each other — keep both.
    await putScalarIngestedAt(
      HealthMetric.weight,
      at,
      80,
      'kg',
      src('scaleA'),
      DateTime(2026, 6, 15, 8, 0, 1),
    );
    await putScalarIngestedAt(
      HealthMetric.weight,
      at,
      78,
      'kg',
      src('scaleB'),
      DateTime(2026, 6, 16, 9),
    );
    final series = await service.scalarSeries(HealthMetric.weight, days: 30);
    expect(series.map((r) => r.value).toList()..sort(), [78, 80]);
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

  test('cumulative daily total keeps the newest snapshot', () async {
    final start = DateTime(2026, 6, 16);
    final end = DateTime(2026, 6, 16, 23, 59, 59);
    final samsung = src('com.sec.android.app.shealth');
    // Samsung Health exposes the day's steps as one whole-day record whose
    // value grows through the day; each refresh appends a fresh snapshot with
    // the identical window. The total must be the newest snapshot (7050), not
    // the stale first one (14) and not the sum of snapshots.
    await putStepsIngestedAt(start, end, 14, samsung, DateTime(2026, 6, 16, 6));
    await putStepsIngestedAt(
      start,
      end,
      5034,
      samsung,
      DateTime(2026, 6, 16, 9),
    );
    await putStepsIngestedAt(
      start,
      end,
      7050,
      samsung,
      DateTime(2026, 6, 16, 14),
    );
    expect(await service.todayStepTotal(), 7050);
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

  test('lastNight / lastNNights are empty (not an error) on no data', () async {
    // Regression: reconcileNights returned a `const []` that the service then
    // sorted in place, throwing "Cannot modify an unmodifiable list" on a
    // fresh, empty install (the home screen showed "Couldn't load this data").
    expect(await service.lastNight(), isNull);
    expect(await service.lastNNights(7), isEmpty);
  });

  test('scalarSeries returns weight readings oldest-first', () async {
    await putScalar(
      HealthMetric.weight,
      DateTime(2026, 6, 16, 9),
      86,
      'kg',
      src('scale'),
    );
    await putScalar(
      HealthMetric.weight,
      DateTime(2026, 6, 10, 8),
      80,
      'kg',
      src('scale'),
    );
    final series = await service.scalarSeries(HealthMetric.weight, days: 30);
    expect(series.map((r) => r.value).toList(), [80, 86]);
  });

  test('dailySteps totals per day and zero-fills empty days', () async {
    // Two sources on the 16th overlap (deduped), plus a record on the 14th.
    final t0 = DateTime(2026, 6, 16, 6);
    final t1 = t0.add(const Duration(minutes: 1));
    await putSteps(t0, t1, 100, src('phone'));
    await putSteps(t0, t1, 90, src('fitband')); // wearable preferred
    await putSteps(
      DateTime(2026, 6, 14, 7),
      DateTime(2026, 6, 14, 8),
      500,
      src('phone'),
    );
    final series = await service.dailySteps(days: 3); // 14th, 15th, 16th
    expect(series.map((d) => d.value).toList(), [500, 0, 90]);
    expect(series.first.day, DateTime(2026, 6, 14));
    expect(series.last.day, DateTime(2026, 6, 16));
  });

  test('dailyHeartRate aggregates min/mean/max per day', () async {
    await putScalar(
      HealthMetric.heartRate,
      DateTime(2026, 6, 16, 6),
      60,
      'bpm',
      src('fitband'),
    );
    await putScalar(
      HealthMetric.heartRate,
      DateTime(2026, 6, 16, 18),
      120,
      'bpm',
      src('fitband'),
    );
    final stats = await service.dailyHeartRate(days: 7);
    expect(stats, hasLength(1));
    expect(stats.single.min, 60);
    expect(stats.single.max, 120);
    expect(stats.single.mean, 90);
    expect(stats.single.count, 2);
  });

  test('recentWorkouts returns workouts most-recent first', () async {
    await putWorkout(
      DateTime(2026, 6, 12, 7),
      DateTime(2026, 6, 12, 8),
      'walking',
      src('fitband'),
      distance: 3000,
      kcal: 150,
    );
    await putWorkout(
      DateTime(2026, 6, 15, 18),
      DateTime(2026, 6, 15, 19),
      'running',
      src('fitband'),
      distance: 8000,
    );
    final workouts = await service.recentWorkouts(days: 14);
    expect(workouts.map((w) => w.activityName).toList(), [
      'running',
      'walking',
    ]);
    expect(workouts.first.distanceMeters, 8000);
  });
}
