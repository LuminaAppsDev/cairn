import 'dart:io';

import 'package:cairn/src/health/health_metric.dart';
import 'package:cairn/src/health/health_repository.dart';
import 'package:cairn/src/health/health_sample.dart';
import 'package:cairn/src/health/health_source.dart';
import 'package:cairn/src/health/read_access_status.dart';
import 'package:cairn/src/storage/health_ingest_service.dart';
import 'package:cairn/src/storage/jsonl_omh_file_store.dart';
import 'package:flutter_test/flutter_test.dart';

/// Records read windows and returns canned samples per metric.
class _FakeRepository implements HealthRepository {
  new(this.samples, {this.failAtRead, this.failure});

  final Map<HealthMetric, List<HealthSample>> samples;
  final List<({HealthMetric metric, DateTime start, DateTime end})> reads = [];

  /// 1-based read that throws [failure] — by default a `StateError`, standing
  /// in for a bug mid-ingest.
  final int? failAtRead;

  /// What the [failAtRead] read throws instead, e.g. a [HealthReadException].
  final Exception? failure;

  @override
  Future<bool> isAvailable() async => true;

  @override
  Future<ReadAccessStatus> backgroundReadStatus() async =>
      ReadAccessStatus.notApplicable;

  @override
  Future<ReadAccessStatus> requestBackgroundRead() async =>
      ReadAccessStatus.notApplicable;

  @override
  Future<ReadAccessStatus> historyReadStatus() async =>
      ReadAccessStatus.notApplicable;

  @override
  Future<ReadAccessStatus> requestHistoryRead() async =>
      ReadAccessStatus.notApplicable;

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
    if (reads.length == failAtRead) {
      final failure = this.failure;
      if (failure != null) throw failure;
      throw StateError('simulated crash');
    }
    // Behave like the real store: match on a sample's start time within the
    // half-open window, as Health Connect's read filter does, so window and
    // slice-boundary logic is actually exercised.
    return (samples[metric] ?? const [])
        .where((s) => !s.start.isBefore(start) && s.start.isBefore(end))
        .toList();
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

  test(
    'a second run re-reads the reconcile window, not just the anchor',
    () async {
      final repo = _FakeRepository({HealthMetric.steps: const []});
      final firstNow = DateTime(2026, 6, 14, 12);
      await HealthIngestService(
        repository: repo,
        store: store,
        clock: () => firstNow,
      ).ingest({HealthMetric.steps});
      // First run has no anchor → window starts ~30 days back, read as a
      // 16-day catch-up (7 + 7 + 2) plus the reconcile window.
      expect(
        repo.reads.first.start.isBefore(
          firstNow.subtract(const Duration(days: 29)),
        ),
        isTrue,
      );
      expect(repo.reads, hasLength(4));
      expect(repo.reads.last.end.isAtSameMomentAs(firstNow), isTrue);

      final secondNow = DateTime(2026, 6, 15, 12);
      repo.reads.clear();
      await HealthIngestService(
        repository: repo,
        store: store,
        clock: () => secondNow,
      ).ingest({HealthMetric.steps});
      // Second run goes back the reconcile window (well before the anchor) so
      // backdated entries are still caught.
      expect(
        repo.reads.first.start.isAtSameMomentAs(
          secondNow.subtract(const Duration(days: 14)),
        ),
        isTrue,
      );
      expect(repo.reads.first.start.isBefore(firstNow), isTrue);
      // No catch-up span, so the reconcile window is a single read.
      expect(repo.reads, hasLength(1));
    },
  );

  test('imports a backdated reading on a later run', () async {
    final repo = _FakeRepository({HealthMetric.weight: []});
    await HealthIngestService(
      repository: repo,
      store: store,
      clock: () => DateTime(2026, 6, 14, 12),
    ).ingest({HealthMetric.weight});

    // User logs a weight dated yesterday — before the anchor, within the
    // reconcile window.
    final backdated = DateTime(2026, 6, 13, 8);
    repo.samples[HealthMetric.weight] = [
      ScalarSample(
        metric: HealthMetric.weight,
        value: 80,
        unit: 'kg',
        start: backdated,
        end: backdated,
        source: source,
      ),
    ];
    final results = await HealthIngestService(
      repository: repo,
      store: store,
      clock: () => DateTime(2026, 6, 14, 18),
    ).ingest({HealthMetric.weight});

    expect(results.single.dataPointCount, 1);
    final onDisk = await store.readRange(
      metric: HealthMetric.weight,
      from: backdated,
      to: DateTime(2026, 6, 14, 18),
    );
    expect(onDisk, hasLength(1));
  });

  test(
    're-ingesting sleep does not duplicate stage or episode lines',
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
        ],
      });
      final first = await HealthIngestService(
        repository: repo,
        store: store,
        clock: () => DateTime(2026, 6, 14, 12),
      ).ingest({HealthMetric.sleep});
      expect(first.single.dataPointCount, 2); // one stage + one episode line

      final second = await HealthIngestService(
        repository: repo,
        store: store,
        clock: () => DateTime(2026, 6, 14, 18),
      ).ingest({HealthMetric.sleep});
      expect(second.single.dataPointCount, 0); // neither line re-written

      final onDisk = await store.readRange(
        metric: HealthMetric.sleep,
        from: night,
        to: DateTime(2026, 6, 14, 18),
      );
      expect(onDisk, hasLength(2));
    },
  );

  test('re-ingesting the same data does not duplicate it', () async {
    final t = DateTime(2026, 6, 14, 8);
    final repo = _FakeRepository({
      HealthMetric.weight: [
        ScalarSample(
          metric: HealthMetric.weight,
          value: 70,
          unit: 'kg',
          start: t,
          end: t,
          source: source,
        ),
      ],
    });
    final first = await HealthIngestService(
      repository: repo,
      store: store,
      clock: () => DateTime(2026, 6, 14, 12),
    ).ingest({HealthMetric.weight});
    expect(first.single.dataPointCount, 1);

    // Same reading is still inside the next run's window — must not re-write.
    final second = await HealthIngestService(
      repository: repo,
      store: store,
      clock: () => DateTime(2026, 6, 14, 18),
    ).ingest({HealthMetric.weight});
    expect(second.single.dataPointCount, 0);

    final onDisk = await store.readRange(
      metric: HealthMetric.weight,
      from: t,
      to: DateTime(2026, 6, 14, 18),
    );
    expect(onDisk, hasLength(1));
  });

  test('a cumulative daily total is compacted, not accumulated', () async {
    // Samsung Health reports the day's steps as one whole-day record whose
    // value grows through the day; each refresh reads the current total.
    final dayStart = DateTime(2026, 6, 14);
    final dayEnd = DateTime(2026, 6, 14, 23, 59, 59);
    final repo = _FakeRepository({HealthMetric.steps: []});

    Future<void> ingestTotal(double value, DateTime at) async {
      repo.samples[HealthMetric.steps] = [
        ScalarSample(
          metric: HealthMetric.steps,
          value: value,
          unit: 'steps',
          start: dayStart,
          end: dayEnd,
          source: source,
        ),
      ];
      await HealthIngestService(
        repository: repo,
        store: store,
        clock: () => at,
      ).ingest({HealthMetric.steps});
    }

    await ingestTotal(14, DateTime(2026, 6, 14, 6));
    await ingestTotal(5034, DateTime(2026, 6, 14, 9));
    await ingestTotal(7050, DateTime(2026, 6, 14, 14));

    final onDisk = await store.readRange(
      metric: HealthMetric.steps,
      from: dayStart,
      to: dayEnd,
    );
    // The same whole-day window collapses to a single, current record.
    expect(onDisk, hasLength(1));
    final body = asMap(onDisk.single['body']);
    expect(asMap(body['step_count'])['value'], 7050.0);
  });

  test('distinct step windows are not compacted together', () async {
    // A source that writes per-interval deltas (distinct windows) must keep
    // every record — only same-window re-reports collapse.
    final t0 = DateTime(2026, 6, 14, 6);
    final t1 = t0.add(const Duration(minutes: 1));
    final t2 = t1.add(const Duration(minutes: 1));
    final repo = _FakeRepository({
      HealthMetric.steps: [
        ScalarSample(
          metric: HealthMetric.steps,
          value: 50,
          unit: 'steps',
          start: t0,
          end: t1,
          source: source,
        ),
        ScalarSample(
          metric: HealthMetric.steps,
          value: 60,
          unit: 'steps',
          start: t1,
          end: t2,
          source: source,
        ),
      ],
    });
    await HealthIngestService(
      repository: repo,
      store: store,
      clock: () => DateTime(2026, 6, 14, 12),
    ).ingest({HealthMetric.steps});

    final onDisk = await store.readRange(
      metric: HealthMetric.steps,
      from: t0,
      to: DateTime(2026, 6, 14, 12),
    );
    expect(onDisk, hasLength(2));
  });

  test('a malformed shard line blocks compaction (no data loss)', () async {
    final dayStart = DateTime(2026, 6, 14);
    final dayEnd = DateTime(2026, 6, 14, 23, 59, 59);

    Future<void> ingestTotal(double value, DateTime at) async {
      final repo = _FakeRepository({
        HealthMetric.steps: [
          ScalarSample(
            metric: HealthMetric.steps,
            value: value,
            unit: 'steps',
            start: dayStart,
            end: dayEnd,
            source: source,
          ),
        ],
      });
      await HealthIngestService(
        repository: repo,
        store: store,
        clock: () => at,
      ).ingest({HealthMetric.steps});
    }

    await ingestTotal(14, DateTime(2026, 6, 14, 6));

    // Simulate a torn append (a crash mid-write) leaving a malformed line.
    final shard = File('${tempRoot.path}/steps/2026/2026-06-14.jsonl')
      ..writeAsStringSync('{"torn":\n', mode: FileMode.append);

    // A new total supersedes 14, but the malformed line must block the rewrite,
    // so the shard is appended to (not compacted) and the torn line survives.
    await ingestTotal(7050, DateTime(2026, 6, 14, 14));

    expect(shard.readAsStringSync(), contains('{"torn":'));
    final values = (await store.readRange(
      metric: HealthMetric.steps,
      from: dayStart,
      to: dayEnd,
    )).map((dp) => asMap(asMap(dp['body'])['step_count'])['value']).toSet();
    // Compaction skipped: 14 was NOT dropped, and 7050 was appended.
    expect(values, containsAll(<double>[14, 7050]));
  });

  test('a first run whose read fails keeps its window start', () async {
    // Without the pinned start, the retry would compute its own
    // `now - initialLookback`, and the oldest days would slide out unread.
    final now = DateTime(2026, 6, 14, 12);
    final repo = _FakeRepository(
      {HealthMetric.steps: const []},
      failAtRead: 1,
      failure: const HealthReadException(HealthMetric.steps),
    );
    final results = await HealthIngestService(
      repository: repo,
      store: store,
      clock: () => now,
    ).ingest({HealthMetric.steps});

    expect(results.single.failed, isTrue);
    final pinned = await store.lastSyncAnchor(HealthMetric.steps);
    final firstRunStart = now.subtract(const Duration(days: 30));
    expect(pinned!.isAtSameMomentAs(firstRunStart), isTrue);
  });

  group('a long sync gap', () {
    final now = DateTime(2026, 6, 14, 12);
    final anchor = now.subtract(const Duration(days: 60));
    // One reading a day across the whole gap, each exactly on a day boundary,
    // so every slice boundary carries a sample (none lost, none doubled).
    final daily = [
      for (var d = 0; d < 60; d++)
        ScalarSample(
          metric: HealthMetric.heartRate,
          value: 60,
          unit: 'count/min',
          start: anchor.add(Duration(days: d)),
          end: anchor.add(Duration(days: d)),
          source: source,
        ),
    ];

    test(
      'catches up in week slices, then reads the reconcile window',
      () async {
        await store.setSyncAnchor(HealthMetric.heartRate, anchor);
        final repo = _FakeRepository({HealthMetric.heartRate: daily});
        final results = await HealthIngestService(
          repository: repo,
          store: store,
          clock: () => now,
        ).ingest({HealthMetric.heartRate});

        final reads = repo.reads;
        expect(reads.first.start.isAtSameMomentAs(anchor), isTrue);
        for (var i = 1; i < reads.length; i++) {
          expect(reads[i].start.isAtSameMomentAs(reads[i - 1].end), isTrue);
        }
        // Every catch-up read spans at most a week ...
        for (final read in reads.take(reads.length - 1)) {
          final span = read.end.difference(read.start);
          expect(span, lessThanOrEqualTo(const Duration(days: 7)));
        }
        // ... and the trailing reconcile window is still one read.
        final reconcileStart = now.subtract(const Duration(days: 14));
        expect(reads.last.start.isAtSameMomentAs(reconcileStart), isTrue);
        expect(reads.last.end.isAtSameMomentAs(now), isTrue);
        expect(results.single.dataPointCount, daily.length);
      },
    );

    test('a failure mid catch-up keeps the finished slices', () async {
      await store.setSyncAnchor(HealthMetric.heartRate, anchor);
      final repo = _FakeRepository({
        HealthMetric.heartRate: daily,
      }, failAtRead: 3);
      final ingest = HealthIngestService(
        repository: repo,
        store: store,
        clock: () => now,
      );
      // Any failure — here a bug's StateError — stops only this metric, and
      // comes back with the result rather than out of ingest.
      final results = await ingest.ingest({HealthMetric.heartRate});
      expect(results.single.error, isA<StateError>());
      expect(results.single.stackTrace, isNotNull);

      // Two slices landed, so the next run resumes after them instead of
      // re-reading (and re-crashing on) the whole gap.
      final resumed = await store.lastSyncAnchor(HealthMetric.heartRate);
      expect(resumed!.isAtSameMomentAs(repo.reads[1].end), isTrue);
      final onDisk = await store.readRange(
        metric: HealthMetric.heartRate,
        from: anchor,
        to: now,
      );
      expect(onDisk, hasLength(14));

      // The resumed run reads on from that anchor and finishes the gap.
      await HealthIngestService(
        repository: _FakeRepository({HealthMetric.heartRate: daily}),
        store: store,
        clock: () => now,
      ).ingest({HealthMetric.heartRate});
      final afterResume = await store.readRange(
        metric: HealthMetric.heartRate,
        from: anchor,
        to: now,
      );
      expect(afterResume, hasLength(daily.length));
      final finished = await store.lastSyncAnchor(HealthMetric.heartRate);
      expect(finished!.isAtSameMomentAs(now), isTrue);
    });

    test('a failed read holds that metric, and the rest still run', () async {
      // Heart rate's third read (mid catch-up) fails; weight comes after it.
      await store.setSyncAnchor(HealthMetric.heartRate, anchor);
      final weighIn = now.subtract(const Duration(hours: 1));
      final repo = _FakeRepository(
        {
          HealthMetric.heartRate: daily,
          HealthMetric.weight: [
            ScalarSample(
              metric: HealthMetric.weight,
              value: 70,
              unit: 'kg',
              start: weighIn,
              end: weighIn,
              source: source,
            ),
          ],
        },
        failAtRead: 3,
        failure: const HealthReadException(HealthMetric.heartRate),
      );
      final results = await HealthIngestService(
        repository: repo,
        store: store,
        clock: () => now,
      ).ingest({HealthMetric.heartRate, HealthMetric.weight});

      final heartRate = results.first;
      expect(heartRate.failed, isTrue);
      expect(heartRate.dataPointCount, 14);
      // Held at the last finished slice — not walked past the failed one.
      final held = await store.lastSyncAnchor(HealthMetric.heartRate);
      expect(held!.isAtSameMomentAs(repo.reads[1].end), isTrue);

      final weight = results.last;
      expect(weight.failed, isFalse);
      expect(weight.dataPointCount, 1);
      final weightAnchor = await store.lastSyncAnchor(HealthMetric.weight);
      expect(weightAnchor!.isAtSameMomentAs(now), isTrue);
    });

    // Episode integrity itself is covered by the sleep tests above; this pins
    // the mechanism — one read, so the aggregator always sees whole nights.
    test('sleep is read in one call even over a long gap', () async {
      await store.setSyncAnchor(HealthMetric.sleep, anchor);
      final repo = _FakeRepository({HealthMetric.sleep: const []});
      await HealthIngestService(
        repository: repo,
        store: store,
        clock: () => now,
      ).ingest({HealthMetric.sleep});

      final read = repo.reads.single;
      expect(read.start.isAtSameMomentAs(anchor), isTrue);
      expect(read.end.isAtSameMomentAs(now), isTrue);
    });

    test('a record straddling a slice boundary is read exactly once', () async {
      // A near-whole-day total across the first boundary: matched on its
      // start time, it belongs to the slice before the boundary and only that
      // one — neither lost nor doubled.
      final boundary = anchor.add(const Duration(days: 7));
      final straddling = ScalarSample(
        metric: HealthMetric.steps,
        value: 8000,
        unit: 'steps',
        start: boundary.subtract(const Duration(hours: 12)),
        end: boundary.add(const Duration(hours: 11)),
        source: source,
      );
      await store.setSyncAnchor(HealthMetric.steps, anchor);
      final repo = _FakeRepository({
        HealthMetric.steps: [straddling],
      });
      final results = await HealthIngestService(
        repository: repo,
        store: store,
        clock: () => now,
      ).ingest({HealthMetric.steps});

      expect(results.single.dataPointCount, 1);
      final onDisk = await store.readRange(
        metric: HealthMetric.steps,
        from: anchor,
        to: now,
      );
      expect(onDisk, hasLength(1));
    });
  });

  group('a failure other than a read', () {
    final now = DateTime(2026, 6, 14, 12);
    final weighIn = now.subtract(const Duration(hours: 1));
    final samples = {
      HealthMetric.steps: [
        ScalarSample(
          metric: HealthMetric.steps,
          value: 1200,
          unit: 'steps',
          start: weighIn,
          end: weighIn,
          source: source,
        ),
      ],
      HealthMetric.weight: [
        ScalarSample(
          metric: HealthMetric.weight,
          value: 70,
          unit: 'kg',
          start: weighIn,
          end: weighIn,
          source: source,
        ),
      ],
    };

    test('stops only its own metric, holding its anchor', () async {
      // A failure that is the metric's own (here a bad record's
      // FormatException on steps' first read): the rest still run.
      await store.setSyncAnchor(HealthMetric.steps, weighIn);
      final before = await store.lastSyncAnchor(HealthMetric.steps);
      final repo = _FakeRepository(
        samples,
        failAtRead: 1,
        failure: const FormatException('bad record'),
      );

      final results = await HealthIngestService(
        repository: repo,
        store: store,
        clock: () => now,
      ).ingest({HealthMetric.steps, HealthMetric.weight});

      expect(results.first.error, isA<FormatException>());
      final held = await store.lastSyncAnchor(HealthMetric.steps);
      expect(held!.isAtSameMomentAs(before!), isTrue);
      final weight = results.last;
      expect(weight.failed, isFalse);
      expect(weight.dataPointCount, 1);
      final advanced = await store.lastSyncAnchor(HealthMetric.weight);
      expect(advanced!.isAtSameMomentAs(now), isTrue);
    });

    test('a local storage failure ends the run after its metric', () async {
      // A real write failure — a plain file where the steps shard directory
      // has to go. Like a full disk, it isn't steps' own: carrying on would
      // only tear another metric's shard.
      File('${tempRoot.path}/steps').writeAsStringSync('in the way');
      await store.setSyncAnchor(HealthMetric.steps, weighIn);
      final before = await store.lastSyncAnchor(HealthMetric.steps);

      final results = await HealthIngestService(
        repository: _FakeRepository(samples),
        store: store,
        clock: () => now,
      ).ingest({HealthMetric.steps, HealthMetric.weight});

      // Weight was never reached: it fails with the same error.
      expect(results.map((r) => r.error), [
        isA<FileSystemException>(),
        same(results.first.error),
      ]);
      final held = await store.lastSyncAnchor(HealthMetric.steps);
      expect(held!.isAtSameMomentAs(before!), isTrue);
      expect(await store.lastSyncAnchor(HealthMetric.weight), isNull);
    });

    test('a rate limit ends the run after its metric', () async {
      // Each further read would only spend more of the spent quota.
      final repo = _FakeRepository(
        samples,
        failAtRead: 1,
        failure: const HealthReadException(
          HealthMetric.steps,
          failure: HealthReadFailure.rateLimited,
        ),
      );

      final results = await HealthIngestService(
        repository: repo,
        store: store,
        clock: () => now,
      ).ingest({HealthMetric.steps, HealthMetric.weight});

      expect(repo.reads.map((r) => r.metric), [HealthMetric.steps]);
      expect(results.map((r) => r.metric), [
        HealthMetric.steps,
        HealthMetric.weight,
      ]);
      expect(results.last.error, same(results.first.error));
      expect(results.last.dataPointCount, 0);
      expect(await store.lastSyncAnchor(HealthMetric.weight), isNull);
    });

    test('a missing health store ends the run, without throwing', () async {
      // Nothing more can be read; the refresh reports it as its own outcome.
      final repo = _FakeRepository(
        samples,
        failAtRead: 1,
        failure: const HealthStoreUnavailableException(),
      );

      final results = await HealthIngestService(
        repository: repo,
        store: store,
        clock: () => now,
      ).ingest({HealthMetric.steps, HealthMetric.weight});

      expect(results.map((r) => r.error), [
        isA<HealthStoreUnavailableException>(),
        same(results.first.error),
      ]);
      expect(repo.reads, hasLength(1));
    });
  });
}
