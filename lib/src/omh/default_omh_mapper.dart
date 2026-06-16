import 'package:cairn/src/health/health_metric.dart';
import 'package:cairn/src/health/health_sample.dart';
import 'package:cairn/src/health/health_source.dart';
import 'package:cairn/src/health/sleep_aggregator.dart';
import 'package:cairn/src/omh/omh_data_point.dart';
import 'package:cairn/src/omh/omh_mapper.dart';
import 'package:cairn/src/omh/omh_time.dart';
import 'package:uuid/uuid.dart';

/// Default [OmhMapper]: normalises raw health samples to OMH / IEEE 1752.1
/// datapoints (DESIGN.md §5).
///
/// Units are re-asserted from the target schema, never passed through ad-hoc
/// (§5.2). Per-sample mappings (scalar, workout, sleep stage) go through
/// [toDataPoint]; the additive nightly rollup goes through
/// [sleepEpisodeToDataPoint].
final class DefaultOmhMapper implements OmhMapper {
  /// Creates a mapper. [uuid] and [clock] are injectable for deterministic
  /// tests; they default to a real v4 generator and [DateTime.now].
  DefaultOmhMapper({Uuid? uuid, DateTime Function()? clock})
    : _uuid = uuid ?? const Uuid(),
      _clock = clock ?? DateTime.now;

  final Uuid _uuid;
  final DateTime Function() _clock;

  @override
  String schemaIdFor(HealthMetric metric) => switch (metric) {
    HealthMetric.heartRate => 'omh:heart-rate:1.0',
    HealthMetric.steps => 'omh:step-count:3.0',
    HealthMetric.weight => 'omh:body-weight:2.0',
    HealthMetric.sleep => 'cairn:sleep-stage:1.0',
    HealthMetric.activity => 'omh:physical-activity:1.0',
  };

  @override
  Map<String, Object?> toDataPoint(HealthSample sample) => switch (sample) {
    final ScalarSample s => _scalar(s),
    final WorkoutSample s => _workout(s),
    final SleepSegmentSample s => _sleepStage(s),
  };

  @override
  Map<String, Object?> sleepEpisodeToDataPoint(SleepEpisode episode) {
    final body = <String, Object?>{
      'effective_time_frame': _intervalFrame(episode.start, episode.end),
      'total_sleep_time': _unitValue(_minutes(episode.totalSleep), 'min'),
      'is_main_sleep': episode.isMainSleep,
      'number_of_awakenings': episode.awakenings,
      'light_sleep_duration': ?_stageMinutes(episode, SleepStage.light),
      'deep_sleep_duration': ?_stageMinutes(episode, SleepStage.deep),
      'rem_sleep_duration': ?_stageMinutes(episode, SleepStage.rem),
    };
    const schema = SchemaId(
      namespace: 'omh',
      name: 'sleep-episode',
      version: '1.0',
    );
    return _wrap(schema, body, episode.source, episode.start).toJson();
  }

  Map<String, Object?> _scalar(ScalarSample s) {
    final dataPoint = switch (s.metric) {
      HealthMetric.heartRate => _wrap(
        const SchemaId(namespace: 'omh', name: 'heart-rate', version: '1.0'),
        <String, Object?>{
          'heart_rate': _unitValue(s.value, 'beats/min'),
          'effective_time_frame': _pointFrame(s.start),
        },
        s.source,
        s.start,
      ),
      HealthMetric.weight => _wrap(
        const SchemaId(namespace: 'omh', name: 'body-weight', version: '2.0'),
        <String, Object?>{
          'body_weight': _unitValue(s.value, 'kg'),
          'effective_time_frame': _pointFrame(s.start),
        },
        s.source,
        s.start,
      ),
      HealthMetric.steps => _wrap(
        const SchemaId(namespace: 'omh', name: 'step-count', version: '3.0'),
        <String, Object?>{
          'step_count': _unitValue(s.value, 'steps'),
          'effective_time_frame': _intervalFrame(s.start, s.end),
        },
        s.source,
        s.start,
      ),
      HealthMetric.sleep || HealthMetric.activity => throw StateError(
        'ScalarSample carries non-scalar metric ${s.metric}',
      ),
    };
    return dataPoint.toJson();
  }

  Map<String, Object?> _workout(WorkoutSample s) {
    final body = <String, Object?>{
      'activity_name': s.activityName,
      'effective_time_frame': _intervalFrame(s.start, s.end),
      'duration': _unitValue(_minutes(s.end.difference(s.start)), 'min'),
      'distance': ?_optUnit(s.totalDistanceMeters, 'm'),
      'kcal_burned': ?_optUnit(s.totalEnergyKcal, 'kcal'),
      'base_movement_quantity': ?_optUnit(s.totalSteps?.toDouble(), 'steps'),
    };
    const schema = SchemaId(
      namespace: 'omh',
      name: 'physical-activity',
      version: '1.0',
    );
    return _wrap(schema, body, s.source, s.start).toJson();
  }

  Map<String, Object?> _sleepStage(SleepSegmentSample s) {
    final body = <String, Object?>{
      'sleep_stage': s.stage.wireName,
      'effective_time_frame': _intervalFrame(s.start, s.end),
    };
    const schema = SchemaId(
      namespace: 'cairn',
      name: 'sleep-stage',
      version: '1.0',
    );
    return _wrap(schema, body, s.source, s.start).toJson();
  }

  OmhDataPoint _wrap(
    SchemaId schema,
    Map<String, Object?> body,
    HealthSource source,
    DateTime sourceCreation,
  ) {
    return OmhDataPoint(
      header: OmhHeader(
        id: _uuid.v4(),
        creationDateTime: omhDateTime(_clock()),
        schemaId: schema,
        provenance: AcquisitionProvenance(
          sourceName: source.name,
          modality: source.recordingMethod.omhModality,
          sourceCreationDateTime: omhDateTime(sourceCreation),
        ),
      ),
      body: body,
    );
  }

  Map<String, Object?> _unitValue(num value, String unit) => {
    'value': value,
    'unit': unit,
  };

  Map<String, Object?>? _optUnit(double? value, String unit) =>
      value == null ? null : _unitValue(value, unit);

  Map<String, Object?>? _stageMinutes(SleepEpisode e, SleepStage stage) {
    final duration = e.stageDurations[stage];
    return duration == null ? null : _unitValue(_minutes(duration), 'min');
  }

  Map<String, Object?> _pointFrame(DateTime t) => {'date_time': omhDateTime(t)};

  Map<String, Object?> _intervalFrame(DateTime start, DateTime end) => {
    'time_interval': {
      'start_date_time': omhDateTime(start),
      'end_date_time': omhDateTime(end),
    },
  };

  double _minutes(Duration d) => d.inSeconds / 60.0;
}
