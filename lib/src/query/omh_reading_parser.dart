import 'package:cairn/src/health/health_source.dart';
import 'package:cairn/src/query/display_readings.dart';

/// Parses OMH datapoint maps (as read from the local cache) back into typed
/// display [readings](display_readings.dart) for the dashboard (DESIGN.md §9,
/// read path A).
///
/// Every function returns `null` on a missing or malformed field rather than
/// throwing, so a single bad line never breaks a screen. Timestamps are parsed
/// with [_parseTs], which converts the stored local-offset ISO strings back to
/// local time (`DateTime.parse` of an offset string yields UTC).

/// The `header.schema_id.name` of [map], used to tell sleep-stage from
/// sleep-episode lines that share one shard. `null` if absent.
String? omhSchemaName(Map<String, Object?> map) {
  final header = _obj(map, 'header');
  final schema = header == null ? null : _obj(header, 'schema_id');
  return schema == null ? null : _str(schema, 'name');
}

/// Parses a heart-rate or body-weight point reading.
ScalarReading? parseScalar(Map<String, Object?> map) {
  final body = _obj(map, 'body');
  if (body == null) return null;
  final value = _unit(body, 'heart_rate') ?? _unit(body, 'body_weight');
  final at = _pointTime(body);
  if (value == null || at == null) return null;
  return ScalarReading(
    value: value.value,
    unit: value.unit,
    at: at,
    source: _provenance(map),
  );
}

/// Parses a step-count interval reading.
IntervalReading? parseInterval(Map<String, Object?> map) {
  final body = _obj(map, 'body');
  if (body == null) return null;
  final value = _unit(body, 'step_count');
  final frame = _interval(body);
  if (value == null || frame == null) return null;
  return IntervalReading(
    value: value.value,
    unit: value.unit,
    start: frame.start,
    end: frame.end,
    source: _provenance(map),
  );
}

/// Parses a physical-activity (workout) reading.
WorkoutReading? parseWorkout(Map<String, Object?> map) {
  final body = _obj(map, 'body');
  if (body == null) return null;
  final name = _str(body, 'activity_name');
  final frame = _interval(body);
  if (name == null || frame == null) return null;
  return WorkoutReading(
    activityName: name,
    start: frame.start,
    end: frame.end,
    distanceMeters: _unit(body, 'distance')?.value,
    kcal: _unit(body, 'kcal_burned')?.value,
    steps: _unit(body, 'base_movement_quantity')?.value.round(),
    source: _provenance(map),
  );
}

/// Parses a single `cairn:sleep-stage` segment.
SleepStageReading? parseSleepStage(Map<String, Object?> map) {
  final body = _obj(map, 'body');
  if (body == null) return null;
  final wire = _str(body, 'sleep_stage');
  final stage = wire == null ? null : SleepStage.fromWire(wire);
  final frame = _interval(body);
  if (stage == null || frame == null) return null;
  return SleepStageReading(
    stage: stage,
    start: frame.start,
    end: frame.end,
    source: _provenance(map),
  );
}

/// Parses an `omh:sleep-episode` nightly rollup.
SleepEpisodeReading? parseSleepEpisode(Map<String, Object?> map) {
  final body = _obj(map, 'body');
  if (body == null) return null;
  final frame = _interval(body);
  final total = _unit(body, 'total_sleep_time');
  if (frame == null || total == null) return null;
  Duration? minutesField(String field) {
    final value = _unit(body, field);
    return value == null ? null : _minutes(value.value);
  }

  return SleepEpisodeReading(
    start: frame.start,
    end: frame.end,
    totalSleep: _minutes(total.value),
    isMainSleep: body['is_main_sleep'] == true,
    awakenings: (_num(body, 'number_of_awakenings') ?? 0).round(),
    light: minutesField('light_sleep_duration'),
    deep: minutesField('deep_sleep_duration'),
    rem: minutesField('rem_sleep_duration'),
    source: _provenance(map),
  );
}

// --- helpers -------------------------------------------------------------

Map<String, Object?>? _obj(Map<String, Object?> map, String key) {
  final value = map[key];
  return value is Map<String, Object?> ? value : null;
}

String? _str(Map<String, Object?> map, String key) {
  final value = map[key];
  return value is String ? value : null;
}

num? _num(Map<String, Object?> map, String key) {
  final value = map[key];
  return value is num ? value : null;
}

/// Parses a stored local-offset ISO-8601 string back to **local** time.
///
/// `DateTime.tryParse` of an offset string yields a UTC instant; `.toLocal()`
/// converts it to the device's current zone. Do not drop the `.toLocal()` — a
/// raw UTC value would shift night-bucketing and "today" across the boundary.
DateTime? _parseTs(String? value) =>
    value == null ? null : DateTime.tryParse(value)?.toLocal();

({double value, String unit})? _unit(Map<String, Object?> body, String field) {
  final uv = _obj(body, field);
  if (uv == null) return null;
  final value = _num(uv, 'value');
  final unit = _str(uv, 'unit');
  if (value == null || unit == null) return null;
  return (value: value.toDouble(), unit: unit);
}

DateTime? _pointTime(Map<String, Object?> body) {
  final frame = _obj(body, 'effective_time_frame');
  return frame == null ? null : _parseTs(_str(frame, 'date_time'));
}

({DateTime start, DateTime end})? _interval(Map<String, Object?> body) {
  final frame = _obj(body, 'effective_time_frame');
  final interval = frame == null ? null : _obj(frame, 'time_interval');
  if (interval == null) return null;
  final start = _parseTs(_str(interval, 'start_date_time'));
  final end = _parseTs(_str(interval, 'end_date_time'));
  if (start == null || end == null) return null;
  return (start: start, end: end);
}

ReadingSource? _provenance(Map<String, Object?> map) {
  final header = _obj(map, 'header');
  final prov = header == null ? null : _obj(header, 'acquisition_provenance');
  if (prov == null) return null;
  final name = _str(prov, 'source_name');
  final modality = _str(prov, 'modality');
  if (name == null || modality == null) return null;
  return ReadingSource(
    name: name,
    modality: modality,
    creationTime: _parseTs(_str(prov, 'source_creation_date_time')),
  );
}

Duration _minutes(double minutes) =>
    Duration(milliseconds: (minutes * 60000).round());
