import 'package:cairn/src/health/health_metric.dart';
import 'package:cairn/src/health/health_source.dart';
import 'package:flutter/foundation.dart';

/// A single reading taken from the OS health store, before OMH mapping.
///
/// Sealed so the OMH mapper's `switch` is exhaustive under the strict analyzer.
/// Subtypes capture the shape each metric needs: [ScalarSample] for the
/// single-value measures, [WorkoutSample] for activity, and
/// [SleepSegmentSample] for one sleep-stage segment (DESIGN.md §4.3, §5).
@immutable
sealed class HealthSample {
  /// Creates a health sample with its common provenance and time fields.
  const new({
    required this.metric,
    required this.start,
    required this.end,
    required this.source,
  });

  /// The measure this reading belongs to.
  final HealthMetric metric;

  /// Inclusive start of the reading's effective time frame.
  final DateTime start;

  /// End of the effective time frame (equals [start] when instantaneous).
  final DateTime end;

  /// Provenance of the reading (app/device, platform, recording method).
  final HealthSource source;
}

/// A single scalar reading: heart rate, step count, or body weight.
final class ScalarSample extends HealthSample {
  /// Creates a scalar sample.
  const new({
    required super.metric,
    required super.start,
    required super.end,
    required super.source,
    required this.value,
    required this.unit,
  });

  /// Numeric value of the reading, in [unit].
  final double value;

  /// Unit as reported by the source; the mapper re-asserts the schema unit.
  final String unit;
}

/// A workout / physical-activity reading.
final class WorkoutSample extends HealthSample {
  /// Creates a workout sample. The metric is always [HealthMetric.activity].
  const new({
    required super.start,
    required super.end,
    required super.source,
    required this.activityName,
    this.totalDistanceMeters,
    this.totalEnergyKcal,
    this.totalSteps,
  }) : super(metric: HealthMetric.activity);

  /// Name of the activity (e.g. `running`), from the health platform.
  final String activityName;

  /// Distance covered, in metres, if the platform reports it.
  final double? totalDistanceMeters;

  /// Energy burned, in kilocalories, if the platform reports it.
  final double? totalEnergyKcal;

  /// Step count accrued during the workout, if the platform reports it.
  final int? totalSteps;
}

/// One sleep-stage segment (REM / light / deep / awake / …), preserved
/// losslessly before any nightly aggregation (DESIGN.md §5.2).
final class SleepSegmentSample extends HealthSample {
  /// Creates a sleep-segment sample. The metric is always [HealthMetric.sleep].
  const new({
    required super.start,
    required super.end,
    required super.source,
    required this.stage,
  }) : super(metric: HealthMetric.sleep);

  /// The sleep stage this segment represents.
  final SleepStage stage;
}
