import 'package:cairn/src/health/health_sample.dart';
import 'package:cairn/src/health/health_source.dart';
import 'package:cairn/src/health/sleep_aggregator.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const source = HealthSource(
    name: 'Watch',
    platform: HealthPlatform.googleHealthConnect,
    recordingMethod: RecordingMethodKind.automatic,
  );
  const aggregator = SleepEpisodeAggregator();

  SleepSegmentSample seg(SleepStage stage, DateTime start, int minutes) =>
      SleepSegmentSample(
        start: start,
        end: start.add(Duration(minutes: minutes)),
        source: source,
        stage: stage,
      );

  test('empty input yields no episodes', () {
    expect(aggregator.aggregate([]), isEmpty);
  });

  test('contiguous segments form one episode; awake excluded from sleep', () {
    final t = DateTime(2026, 6, 13, 23);
    final episodes = aggregator.aggregate([
      seg(SleepStage.light, t, 60),
      seg(SleepStage.deep, t.add(const Duration(minutes: 60)), 90),
      seg(SleepStage.awake, t.add(const Duration(minutes: 150)), 10),
      seg(SleepStage.rem, t.add(const Duration(minutes: 160)), 60),
    ]);

    expect(episodes, hasLength(1));
    final e = episodes.single;
    expect(e.totalSleep, const Duration(minutes: 210)); // 60 + 90 + 60
    expect(e.awakenings, 1);
    expect(e.isMainSleep, isTrue);
    expect(e.start, t);
    expect(e.end, t.add(const Duration(minutes: 220)));
    expect(e.stageDurations[SleepStage.deep], const Duration(minutes: 90));
  });

  test('a gap beyond tolerance splits into separate episodes', () {
    final t = DateTime(2026, 6, 14, 1);
    final episodes = aggregator.aggregate([
      seg(SleepStage.deep, t, 30),
      // 2h gap (> 60min tolerance) starts a new episode
      seg(SleepStage.deep, t.add(const Duration(hours: 3)), 30),
    ]);
    expect(episodes, hasLength(2));
  });

  test('same-night nap and main sleep: only the longer is main', () {
    final nap = DateTime(2026, 6, 14, 2);
    final main = DateTime(2026, 6, 14, 22);
    final episodes = aggregator.aggregate([
      seg(SleepStage.light, nap, 30),
      seg(SleepStage.deep, main, 360),
    ]);

    expect(episodes, hasLength(2));
    final byStart = {for (final e in episodes) e.start: e};
    expect(byStart[nap]!.isMainSleep, isFalse);
    expect(byStart[main]!.isMainSleep, isTrue);
  });

  test('episodes on different nights are each their night main', () {
    final n1 = DateTime(2026, 6, 13, 23);
    final n2 = DateTime(2026, 6, 14, 23);
    final episodes = aggregator.aggregate([
      seg(SleepStage.deep, n1, 300),
      seg(SleepStage.deep, n2, 200),
    ]);
    expect(episodes, hasLength(2));
    expect(episodes.every((e) => e.isMainSleep), isTrue);
  });

  test('only awake segments count as awakenings (not in/out of bed)', () {
    final t = DateTime(2026, 6, 13, 23);
    final episodes = aggregator.aggregate([
      seg(SleepStage.deep, t, 60),
      seg(SleepStage.awake, t.add(const Duration(minutes: 60)), 5),
      seg(SleepStage.outOfBed, t.add(const Duration(minutes: 65)), 10),
      seg(SleepStage.inBed, t.add(const Duration(minutes: 75)), 5),
      seg(SleepStage.rem, t.add(const Duration(minutes: 80)), 40),
    ]);

    final e = episodes.single;
    expect(e.awakenings, 1);
    expect(e.totalSleep, const Duration(minutes: 100)); // deep 60 + rem 40
  });

  test('a session-only sleep totals the session duration', () {
    final t = DateTime(2026, 6, 13, 23);
    final episodes = aggregator.aggregate([
      seg(SleepStage.session, t, 450),
    ]);
    expect(episodes.single.totalSleep, const Duration(minutes: 450));
    expect(episodes.single.isMainSleep, isTrue);
  });

  test('a session overlapping its stages is not double-counted', () {
    final t = DateTime(2026, 6, 13, 23);
    final episodes = aggregator.aggregate([
      seg(SleepStage.session, t, 480), // whole session
      seg(SleepStage.deep, t.add(const Duration(minutes: 30)), 90),
      seg(SleepStage.rem, t.add(const Duration(minutes: 180)), 60),
    ]);
    // Union of asleep intervals = the 480-min session, not 480 + 90 + 60.
    expect(episodes.single.totalSleep, const Duration(minutes: 480));
  });
}
