import 'dart:convert';
import 'dart:io';

import 'package:cairn/src/health/health_metric.dart';
import 'package:cairn/src/storage/jsonl_omh_file_store.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

void main() {
  late Directory tempRoot;
  late JsonlOmhFileStore store;

  setUp(() {
    tempRoot = Directory.systemTemp.createTempSync('cairn_store_test');
    store = JsonlOmhFileStore(root: tempRoot);
  });
  tearDown(() => tempRoot.deleteSync(recursive: true));

  Map<String, Object?> asMap(Object? value) => value! as Map<String, Object?>;

  Map<String, Object?> dp(String id) => <String, Object?>{
    'header': {'id': id},
    'body': {
      'heart_rate': {'value': 60, 'unit': 'beats/min'},
    },
  };

  final day = DateTime(2026, 6, 14, 8); // time component is ignored

  test('append then readRange round-trips datapoints in order', () async {
    await store.append(
      metric: HealthMetric.heartRate,
      day: day,
      dataPoints: [dp('a'), dp('b')],
    );
    final read = await store.readRange(
      metric: HealthMetric.heartRate,
      from: day,
      to: day,
    );
    expect(read, hasLength(2));
    expect(asMap(read[0]['header'])['id'], 'a');
    expect(asMap(read[1]['header'])['id'], 'b');
  });

  test('shards one file per metric per day at the documented path', () async {
    await store.append(
      metric: HealthMetric.steps,
      day: day,
      dataPoints: [dp('x')],
    );
    final file = File(
      p.join(tempRoot.path, 'steps', '2026', '2026-06-14.jsonl'),
    );
    expect(file.existsSync(), isTrue);
  });

  test('readRange spans multiple days and skips missing shards', () async {
    final d1 = DateTime(2026, 6, 14);
    final d3 = DateTime(2026, 6, 16);
    await store.append(
      metric: HealthMetric.weight,
      day: d1,
      dataPoints: [dp('1')],
    );
    await store.append(
      metric: HealthMetric.weight,
      day: d3,
      dataPoints: [dp('3')],
    );
    final read = await store.readRange(
      metric: HealthMetric.weight,
      from: d1,
      to: d3,
    );
    expect(read, hasLength(2)); // the empty 06-15 shard is skipped
  });

  test('a malformed trailing line is skipped on read', () async {
    final file = File(
      p.join(tempRoot.path, 'sleep', '2026', '2026-06-14.jsonl'),
    );
    file.parent.createSync(recursive: true);
    file.writeAsStringSync('${jsonEncode(dp('ok'))}\n{"partial": ');
    final read = await store.readRange(
      metric: HealthMetric.sleep,
      from: day,
      to: day,
    );
    expect(read, hasLength(1));
    expect(asMap(read.single['header'])['id'], 'ok');
  });

  test('sync anchor writes and reads back; manifest is atomic', () async {
    expect(await store.lastSyncAnchor(HealthMetric.heartRate), isNull);
    final anchor = DateTime(2026, 6, 15, 12);
    await store.setSyncAnchor(HealthMetric.heartRate, anchor);
    final read = await store.lastSyncAnchor(HealthMetric.heartRate);
    expect(read!.isAtSameMomentAs(anchor), isTrue);

    final manifest = File(p.join(tempRoot.path, 'manifest.json'));
    expect(manifest.existsSync(), isTrue);
    expect(
      jsonDecode(manifest.readAsStringSync()),
      isA<Map<String, dynamic>>(),
    );
    expect(File('${manifest.path}.tmp').existsSync(), isFalse); // renamed away
  });

  test('concurrent anchor writes do not clobber each other', () async {
    await Future.wait([
      store.setSyncAnchor(HealthMetric.heartRate, DateTime(2026, 6, 15)),
      store.setSyncAnchor(HealthMetric.steps, DateTime(2026, 6, 16)),
      store.setSyncAnchor(HealthMetric.weight, DateTime(2026, 6, 17)),
    ]);
    expect(await store.lastSyncAnchor(HealthMetric.heartRate), isNotNull);
    expect(await store.lastSyncAnchor(HealthMetric.steps), isNotNull);
    expect(await store.lastSyncAnchor(HealthMetric.weight), isNotNull);
  });
}
