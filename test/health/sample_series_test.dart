import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:health/health.dart';

// Patch 5 of the vendored plugin (third_party/health/CAIRN_PATCHES.md): Android
// sends heart rate as one map per record with its samples as arrays, and the
// plugin's parser expands them. What comes out must be exactly the map per
// sample upstream sends, so everything downstream is unchanged.
void main() {
  const base = {
    'uuid': 'record-1',
    'source_id': '',
    'source_name': 'com.fitbit.FitbitMobile',
    'recording_method': 1,
  };

  test('a heart-rate series expands to upstream maps per sample', () {
    final series = <Object?, Object?>{
      ...base,
      'sample_times': Int64List.fromList([1000, 3500]),
      'sample_values': Int64List.fromList([61, 64]),
    };
    expect(expandSampleSeries([series]).toList(), [
      {...base, 'value': 61, 'date_from': 1000, 'date_to': 1000},
      {...base, 'value': 64, 'date_from': 3500, 'date_to': 3500},
    ]);
  });

  test('other points pass through unchanged and in order', () {
    final steps = {...base, 'value': 120, 'date_from': 0, 'date_to': 60000};
    final empty = <Object?, Object?>{
      ...base,
      'sample_times': Int64List(0),
      'sample_values': Int64List(0),
    };
    expect(expandSampleSeries([steps, empty, steps]).toList(), [steps, steps]);
  });

  test('a series whose arrays disagree in length is refused', () {
    // Never pair a time with a neighbour's value, or drop the extra ones.
    final torn = <Object?, Object?>{
      ...base,
      'sample_times': Int64List.fromList([1000, 2000]),
      'sample_values': Int64List.fromList([61]),
    };
    expect(() => expandSampleSeries([torn]).toList(), throwsFormatException);
  });
}
