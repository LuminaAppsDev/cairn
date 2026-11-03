import 'package:flutter/foundation.dart';

/// One day's aggregated value for a metric (e.g. total steps that day). [day]
/// is a local date-only `DateTime`.
@immutable
class DailyValue {
  /// Creates a daily value.
  const new({required this.day, required this.value});

  /// The local calendar day this value covers (date-only).
  final DateTime day;

  /// The aggregated value for [day].
  final double value;
}

/// One day's min / mean / max for a scalar metric (e.g. heart rate), plus the
/// number of readings that day. [day] is a local date-only `DateTime`.
@immutable
class DailyStat {
  /// Creates a daily statistic.
  const new({
    required this.day,
    required this.min,
    required this.mean,
    required this.max,
    required this.count,
  });

  /// The local calendar day this statistic covers (date-only).
  final DateTime day;

  /// Lowest reading that day.
  final double min;

  /// Mean of the day's readings.
  final double mean;

  /// Highest reading that day.
  final double max;

  /// How many readings contributed to this day.
  final int count;
}
