import 'package:cairn/src/health/health_metric.dart';
import 'package:cairn/src/health/health_sample.dart';
import 'package:cairn/src/health/health_source.dart';
import 'package:cairn/src/health/source_dedup.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  HealthSource src(
    String name, {
    RecordingMethodKind method = RecordingMethodKind.automatic,
  }) => HealthSource(
    name: name,
    platform: HealthPlatform.googleHealthConnect,
    recordingMethod: method,
  );

  ScalarSample hr(double value, DateTime at, HealthSource source) =>
      ScalarSample(
        metric: HealthMetric.heartRate,
        value: value,
        unit: 'count/min',
        start: at,
        end: at,
        source: source,
      );

  const dedup = SourcePriorityDeduplicator();
  final t = DateTime(2026, 6, 14, 8);

  test('competing same-window readings collapse to the preferred source', () {
    final result = dedup.deduplicate([
      hr(70, t, src('Pixel Phone')),
      hr(68, t, src('Galaxy Watch')),
    ]);
    expect(result, hasLength(1));
    expect((result.single as ScalarSample).value, 68);
    expect(result.single.source.name, 'Galaxy Watch');
  });

  test('readings in different windows are both kept', () {
    final result = dedup.deduplicate([
      hr(70, t, src('Phone')),
      hr(72, t.add(const Duration(minutes: 1)), src('Phone')),
    ]);
    expect(result, hasLength(2));
  });

  test('on a priority tie, automatic beats manual', () {
    final result = dedup.deduplicate([
      hr(70, t, src('Phone', method: RecordingMethodKind.manual)),
      hr(71, t, src('Tablet')),
    ]);
    expect(result, hasLength(1));
    expect(result.single.source.recordingMethod, RecordingMethodKind.automatic);
  });

  test('empty input yields empty output', () {
    expect(dedup.deduplicate([]), isEmpty);
  });
}
