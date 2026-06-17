import 'package:cairn/src/health/health_source.dart';
import 'package:cairn/src/query/omh_reading_parser.dart';
import 'package:flutter_test/flutter_test.dart';

Map<String, Object?> _header(String name) => {
  'header': {
    'id': 'x',
    'schema_id': {'namespace': 'omh', 'name': name, 'version': '1.0'},
    'acquisition_provenance': {
      'source_name': 'com.fitbit.FitbitMobile',
      'modality': 'sensed',
      'source_creation_date_time': '2026-06-16T15:33:55+02:00',
    },
  },
};

Map<String, Object?> _withBody(String name, Map<String, Object?> body) => {
  ..._header(name),
  'body': body,
};

void main() {
  group('parseScalar', () {
    test('parses heart rate and converts the timestamp to local', () {
      final reading = parseScalar(
        _withBody('heart-rate', {
          'heart_rate': {'value': 62, 'unit': 'beats/min'},
          'effective_time_frame': {'date_time': '2026-06-16T15:33:55+02:00'},
        }),
      );
      expect(reading, isNotNull);
      expect(reading!.value, 62);
      expect(reading.unit, 'beats/min');
      // 15:33:55+02:00 == 13:33:55Z; stored offset must round-trip to local.
      expect(reading.at.toUtc(), DateTime.utc(2026, 6, 16, 13, 33, 55));
      expect(reading.at.isUtc, isFalse);
      expect(reading.source?.name, 'com.fitbit.FitbitMobile');
      expect(reading.source?.modality, 'sensed');
    });

    test('parses body weight', () {
      final reading = parseScalar(
        _withBody('body-weight', {
          'body_weight': {'value': 86.0, 'unit': 'kg'},
          'effective_time_frame': {'date_time': '2026-06-16T15:33:55+02:00'},
        }),
      );
      expect(reading?.value, 86.0);
      expect(reading?.unit, 'kg');
    });

    test('returns null on a missing value', () {
      final reading = parseScalar(
        _withBody('heart-rate', {
          'heart_rate': {'unit': 'beats/min'},
          'effective_time_frame': {'date_time': '2026-06-16T15:33:55+02:00'},
        }),
      );
      expect(reading, isNull);
    });

    test('returns null on a malformed timestamp', () {
      final reading = parseScalar(
        _withBody('heart-rate', {
          'heart_rate': {'value': 62, 'unit': 'beats/min'},
          'effective_time_frame': {'date_time': 'not-a-date'},
        }),
      );
      expect(reading, isNull);
    });

    test('returns null when body is absent', () {
      expect(parseScalar(_header('heart-rate')), isNull);
    });
  });

  test('parseInterval parses a step-count interval', () {
    final reading = parseInterval(
      _withBody('step-count', {
        'step_count': {'value': 443, 'unit': 'steps'},
        'effective_time_frame': {
          'time_interval': {
            'start_date_time': '2026-06-16T06:06:00+02:00',
            'end_date_time': '2026-06-16T06:07:00+02:00',
          },
        },
      }),
    );
    expect(reading?.value, 443);
    expect(reading?.start.toUtc(), DateTime.utc(2026, 6, 16, 4, 6));
    expect(reading?.end.toUtc(), DateTime.utc(2026, 6, 16, 4, 7));
  });

  test('parseWorkout parses optional metrics', () {
    final reading = parseWorkout(
      _withBody('physical-activity', {
        'activity_name': 'WALKING',
        'effective_time_frame': {
          'time_interval': {
            'start_date_time': '2026-06-16T06:06:00+02:00',
            'end_date_time': '2026-06-16T06:36:00+02:00',
          },
        },
        'distance': {'value': 2400.0, 'unit': 'm'},
        'kcal_burned': {'value': 139.0, 'unit': 'kcal'},
        'base_movement_quantity': {'value': 2600.0, 'unit': 'steps'},
      }),
    );
    expect(reading?.activityName, 'WALKING');
    expect(reading?.distanceMeters, 2400.0);
    expect(reading?.kcal, 139.0);
    expect(reading?.steps, 2600);
    expect(reading?.duration, const Duration(minutes: 30));
  });

  test('parseSleepStage maps the wire stage', () {
    final reading = parseSleepStage(
      _withBody('sleep-stage', {
        'sleep_stage': 'asleep_unspecified',
        'effective_time_frame': {
          'time_interval': {
            'start_date_time': '2026-06-15T23:00:00+02:00',
            'end_date_time': '2026-06-16T06:00:00+02:00',
          },
        },
      }),
    );
    expect(reading?.stage, SleepStage.asleepUnspecified);
    expect(reading?.duration, const Duration(hours: 7));
  });

  test('parseSleepStage returns null for an unknown stage', () {
    final reading = parseSleepStage(
      _withBody('sleep-stage', {
        'sleep_stage': 'teleporting',
        'effective_time_frame': {
          'time_interval': {
            'start_date_time': '2026-06-15T23:00:00+02:00',
            'end_date_time': '2026-06-16T06:00:00+02:00',
          },
        },
      }),
    );
    expect(reading, isNull);
  });

  test('parseSleepEpisode reads totals and stage durations', () {
    final reading = parseSleepEpisode(
      _withBody('sleep-episode', {
        'effective_time_frame': {
          'time_interval': {
            'start_date_time': '2026-06-15T23:00:00+02:00',
            'end_date_time': '2026-06-16T06:00:00+02:00',
          },
        },
        'total_sleep_time': {'value': 420.0, 'unit': 'min'},
        'is_main_sleep': true,
        'number_of_awakenings': 2,
        'deep_sleep_duration': {'value': 65.0, 'unit': 'min'},
      }),
    );
    expect(reading?.totalSleep, const Duration(minutes: 420));
    expect(reading?.isMainSleep, isTrue);
    expect(reading?.awakenings, 2);
    expect(reading?.deep, const Duration(minutes: 65));
    expect(reading?.light, isNull);
  });

  test('omhSchemaName reads the schema discriminator', () {
    expect(omhSchemaName(_header('sleep-episode')), 'sleep-episode');
    expect(omhSchemaName(const {}), isNull);
  });

  group('SleepStage.fromWire', () {
    test('round-trips every stage', () {
      for (final stage in SleepStage.values) {
        expect(SleepStage.fromWire(stage.wireName), stage);
      }
    });

    test('returns null for an unknown wire value', () {
      expect(SleepStage.fromWire('bogus'), isNull);
    });
  });
}
