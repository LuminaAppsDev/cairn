import 'package:cairn/src/health/health_source.dart';
import 'package:flutter/foundation.dart';

/// Where a reading came from, parsed from an OMH datapoint's
/// `header.acquisition_provenance` block (DESIGN.md §5.2).
@immutable
class ReadingSource {
  /// Creates a reading source.
  const ReadingSource({
    required this.name,
    required this.modality,
    this.creationTime,
  });

  /// The source app/device name (e.g. `com.fitbit.FitbitMobile`).
  final String name;

  /// OMH modality: `self-reported` (manual) or `sensed`.
  final String modality;

  /// When the source recorded the reading, if present.
  final DateTime? creationTime;
}

/// A point-in-time scalar reading (heart rate, body weight).
@immutable
class ScalarReading {
  /// Creates a scalar reading.
  const ScalarReading({
    required this.value,
    required this.unit,
    required this.at,
    this.source,
    this.ingestedAt,
  });

  /// The measured value (e.g. beats/min, kg).
  final double value;

  /// The unit, taken from the schema body (never ad-hoc).
  final String unit;

  /// The instant the reading applies to (local time).
  final DateTime at;

  /// Provenance, if parseable.
  final ReadingSource? source;

  /// When Cairn wrote this datapoint to the cache — the OMH header's
  /// `creation_date_time`, in local time — or `null` if the header lacked it.
  ///
  /// The read path uses this to resolve an in-place correction: among readings
  /// that share a source and effective instant, the one ingested last wins, so
  /// a fixed value (e.g. a re-typed manual weight) supersedes the stale one
  /// without rewriting any append-only file (DESIGN.md §4.3).
  final DateTime? ingestedAt;
}

/// A reading that spans an interval (step count over a minute, etc.).
@immutable
class IntervalReading {
  /// Creates an interval reading.
  const IntervalReading({
    required this.value,
    required this.unit,
    required this.start,
    required this.end,
    this.source,
    this.ingestedAt,
  });

  /// The measured value over the interval.
  final double value;

  /// The unit, taken from the schema body.
  final String unit;

  /// Interval start (local time).
  final DateTime start;

  /// Interval end (local time).
  final DateTime end;

  /// Provenance, if parseable.
  final ReadingSource? source;

  /// When Cairn wrote this datapoint (the OMH header's `creation_date_time`, in
  /// local time), or `null` if absent. The read path breaks same-window ties by
  /// this, so a source that re-reports a cumulative total in a fixed window
  /// (e.g. Samsung Health's whole-day step count) resolves to its newest
  /// snapshot instead of a stale or summed value (DESIGN.md §4.3).
  final DateTime? ingestedAt;
}

/// A workout / physical-activity reading (IEEE 1752.1 physical-activity).
@immutable
class WorkoutReading {
  /// Creates a workout reading.
  const WorkoutReading({
    required this.activityName,
    required this.start,
    required this.end,
    this.distanceMeters,
    this.kcal,
    this.steps,
    this.source,
  });

  /// The activity label (e.g. `WALKING`).
  final String activityName;

  /// Activity start (local time).
  final DateTime start;

  /// Activity end (local time).
  final DateTime end;

  /// Distance covered in metres, if reported.
  final double? distanceMeters;

  /// Energy burned in kcal, if reported.
  final double? kcal;

  /// Base movement count (e.g. steps), if reported.
  final int? steps;

  /// Provenance, if parseable.
  final ReadingSource? source;

  /// Elapsed wall-clock duration of the activity.
  Duration get duration => end.difference(start);
}

/// One sleep-stage segment (`cairn:sleep-stage`).
@immutable
class SleepStageReading {
  /// Creates a sleep-stage reading.
  const SleepStageReading({
    required this.stage,
    required this.start,
    required this.end,
    this.source,
  });

  /// The sleep stage for this segment.
  final SleepStage stage;

  /// Segment start (local time).
  final DateTime start;

  /// Segment end (local time).
  final DateTime end;

  /// Provenance, if parseable.
  final ReadingSource? source;

  /// Segment duration.
  Duration get duration => end.difference(start);
}

/// A nightly sleep-episode rollup (`omh:sleep-episode`).
@immutable
class SleepEpisodeReading {
  /// Creates a sleep-episode reading.
  const SleepEpisodeReading({
    required this.start,
    required this.end,
    required this.totalSleep,
    required this.isMainSleep,
    required this.awakenings,
    this.light,
    this.deep,
    this.rem,
    this.source,
  });

  /// Episode onset (local time).
  final DateTime start;

  /// Episode end / final awakening (local time).
  final DateTime end;

  /// Total time asleep.
  final Duration totalSleep;

  /// Whether the source flagged this as the night's main sleep.
  final bool isMainSleep;

  /// Number of awakenings recorded.
  final int awakenings;

  /// Light-sleep duration, if reported.
  final Duration? light;

  /// Deep-sleep duration, if reported.
  final Duration? deep;

  /// REM-sleep duration, if reported.
  final Duration? rem;

  /// Provenance, if parseable.
  final ReadingSource? source;
}
