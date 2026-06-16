import 'package:cairn/src/health/health_metric.dart';
import 'package:cairn/src/storage/manifest.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('empty manifest has the current format version and no anchors', () {
    final manifest = Manifest.empty();
    expect(manifest.formatVersion, kFormatVersion);
    expect(manifest.syncAnchors, isEmpty);
  });

  test('anchors round-trip through toJson/fromJson by instant', () {
    final anchor = DateTime(2026, 6, 15, 14, 26, 18);
    final manifest = Manifest.empty()
        .withAnchor(HealthMetric.heartRate, anchor)
        .withAnchor(HealthMetric.steps, anchor.add(const Duration(hours: 1)));

    final json = manifest.toJson(updatedAt: DateTime(2026, 6, 15, 15));
    final restored = Manifest.fromJson(json);

    expect(restored.formatVersion, kFormatVersion);
    expect(
      restored.syncAnchors[HealthMetric.heartRate]!.isAtSameMomentAs(anchor),
      isTrue,
    );
    expect(restored.syncAnchors[HealthMetric.steps], isNotNull);
    expect(json['format_version'], kFormatVersion);
    final anchorsJson = json['sync_anchors']! as Map<String, Object?>;
    expect(anchorsJson.containsKey('heart-rate'), isTrue);
  });

  test('fromJson tolerates missing, unknown, and malformed entries', () {
    final manifest = Manifest.fromJson(const {
      'sync_anchors': <String, Object?>{
        'heart-rate': 'not-a-date',
        'unknown-metric': '2026-06-15T00:00:00+02:00',
      },
      'devices': <Object?>['phone', 42],
    });
    expect(manifest.formatVersion, kFormatVersion); // missing → default
    expect(manifest.syncAnchors, isEmpty); // bad date + unknown slug dropped
    expect(manifest.devices, ['phone']); // non-strings filtered out
  });
}
