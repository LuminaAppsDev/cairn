import 'dart:io';

import 'package:cairn/src/health/health_metric.dart';
import 'package:cairn/src/health/health_repository.dart';
import 'package:cairn/src/health/health_sample.dart';
import 'package:cairn/src/health/health_source.dart';
import 'package:cairn/src/storage/health_ingest_service.dart';
import 'package:cairn/src/storage/jsonl_omh_file_store.dart';
import 'package:flutter_test/flutter_test.dart';

/// Records read windows and returns canned samples per metric.
class _FakeRepository implements HealthRepository {
  _FakeRepository(this.samples);

  final Map<HealthMetric, List<HealthSample>> samples;
  final List<({HealthMetric metric, DateTime start, DateTime end})> reads = [];

  @override
  Future<Set<HealthMetric>> requestAuthorization(
    Set<HealthMetric> metrics,
  ) async => metrics;

  @override
  Future<List<HealthSample>> readSamples({
    required HealthMetric metric,
    required DateTime start,
    required DateTime end,
  }) async {
    reads.add((metric: metric, start: start, end: end));
    return samples[metric] ?? const [];
  }
}

void main() {
  late Directory tempRoot;
  late JsonlOmhFileStore store;

  const source = HealthSource(
    name: 'Watch',
    platform: HealthPlatform.googleHealthConnect,
    recordingMethod: RecordingMethodKind.automatic,
  );

  setUp(() {
    tempRoot = Directory.systemTemp.createTempSync('cairn_ingest_test');
    store = JsonlOmhFileStore(root: tempRoot);
  });
  tearDown(() => tempRoot.deleteSync(recursive: true));

  Map<String, Object?> asMap(Object? value) => value! as Map<String, Object?>;

  test('persists datapoints and advances the anchor', () async {
    final t = DateTime(2026, 6, 14, 8);
    final repo = _FakeRepository({
      HealthMetric.heartRate: [
        ScalarSample(
          metric: HealthMetric.heartRate,
          value: 62,
          unit: 'count/min',
          start: t,
          end: t,
          source: source,
        ),
      ],
    });
    final now = DateTime(2026, 6, 14, 12);
    final ingest = HealthIngestService(
      repository: repo,
      store: store,
      clock: () => now,
    );

    final results = await ingest.ingest({HealthMetric.heartRate});
    expect(results.single.dataPointCount, 1);

    final onDisk = await store.readRange(
      metric: HealthMetric.heartRate,
      from: t,
      to: now,
    );
    expect(onDisk, hasLength(1));
    final anchor = await store.lastSyncAnchor(HealthMetric.heartRate);
    expect(anchor!.isAtSameMomentAs(now), isTrue);
  });

  test('groups datapoints into per-day shards', () async {
    final d1 = DateTime(2026, 6, 13, 23);
    final d2 = DateTime(2026, 6, 14, 1);
    final repo = _FakeRepository({
      HealthMetric.weight: [
        ScalarSample(
          metric: HealthMetric.weight,
          value: 70,
          unit: 'kg',
          start: d1,
          end: d1,
          source: source,
        ),
        ScalarSample(
          metric: HealthMetric.weight,
          value: 71,
          unit: 'kg',
          start: d2,
          end: d2,
          source: source,
        ),
      ],
    });
    final ingest = HealthIngestService(
      repository: repo,
      store: store,
      clock: () => DateTime(2026, 6, 14, 12),
    );
    await ingest.ingest({HealthMetric.weight});

    final root = tempRoot.path;
    expect(File('$root/weight/2026/2026-06-13.jsonl').existsSync(), isTrue);
    expect(File('$root/weight/2026/2026-06-14.jsonl').existsSync(), isTrue);
  });

  test(
    'sleep writes both stage and episode lines into the sleep shard',
    () async {
      final night = DateTime(2026, 6, 13, 23);
      final repo = _FakeRepository({
        HealthMetric.sleep: [
          SleepSegmentSample(
            start: night,
            end: night.add(const Duration(minutes: 60)),
            source: source,
            stage: SleepStage.deep,
          ),
          SleepSegmentSample(
            start: night.add(const Duration(minutes: 60)),
            end: night.add(const Duration(minutes: 120)),
            source: source,
            stage: SleepStage.rem,
          ),
        ],
      });
      final ingest = HealthIngestService(
        repository: repo,
        store: store,
        clock: () => DateTime(2026, 6, 14, 12),
      );
      await ingest.ingest({HealthMetric.sleep});

      final read = await store.readRange(
        metric: HealthMetric.sleep,
        from: night,
        to: DateTime(2026, 6, 14),
      );
      final names = read
          .map((dp) => asMap(asMap(dp['header'])['schema_id'])['name'])
          .toSet();
      expect(names, containsAll(<String>['sleep-stage', 'sleep-episode']));
    },
  );

  test('a second run reads from the advanced anchor', () async {
    final repo = _FakeRepository({HealthMetric.steps: const []});
    final firstNow = DateTime(2026, 6, 14, 12);
    await HealthIngestService(
      repository: repo,
      store: store,
      clock: () => firstNow,
    ).ingest({HealthMetric.steps});
    // First run has no anchor → window starts ~30 days back.
    expect(
      repo.reads.last.start.isBefore(
        firstNow.subtract(const Duration(days: 29)),
      ),
      isTrue,
    );

    final secondNow = DateTime(2026, 6, 15, 12);
    await HealthIngestService(
      repository: repo,
      store: store,
      clock: () => secondNow,
    ).ingest({HealthMetric.steps});
    // Second run starts from the anchor the first run wrote.
    expect(repo.reads.last.start.isAtSameMomentAs(firstNow), isTrue);
  });
}
