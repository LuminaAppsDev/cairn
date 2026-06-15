import 'package:flutter/foundation.dart';

/// The OS health platform that produced a reading.
enum HealthPlatform {
  /// Apple HealthKit (iOS).
  appleHealth,

  /// Android Health Connect.
  googleHealthConnect,
}

/// How a reading was recorded, normalised from the `health` package's
/// `RecordingMethod`. Drives the OMH `acquisition_provenance.modality` (§5.2).
enum RecordingMethodKind {
  /// Recorded automatically by a sensor/device.
  automatic,

  /// Entered manually by the user.
  manual,

  /// Actively recorded (Android), e.g. during a tracked workout.
  active,

  /// Recording method unknown.
  unknown;

  /// OMH `modality`: manual entry is `self-reported`, everything else `sensed`.
  String get omhModality =>
      this == RecordingMethodKind.manual ? 'self-reported' : 'sensed';
}

/// A sleep-stage classification, preserved losslessly before nightly
/// aggregation (DESIGN.md §5.2).
enum SleepStage {
  /// Awake during the sleep period.
  awake,

  /// Light sleep.
  light,

  /// Deep sleep.
  deep,

  /// REM sleep.
  rem,

  /// Asleep, stage unspecified by the platform.
  asleepUnspecified,

  /// Awake but still in bed (not counted as asleep).
  inBed,

  /// Out of bed during the sleep period (distinct from an in-bed awakening).
  outOfBed,

  /// An overall sleep session with no per-stage breakdown (e.g. a manual
  /// entry). Counts as time asleep, but is tracked separately from the stages
  /// so it is never conflated with `asleepUnspecified` sub-segments.
  session;

  /// The wire value emitted in the `cairn:sleep-stage` schema body.
  String get wireName => switch (this) {
    SleepStage.awake => 'awake',
    SleepStage.light => 'light',
    SleepStage.deep => 'deep',
    SleepStage.rem => 'rem',
    SleepStage.asleepUnspecified => 'asleep_unspecified',
    SleepStage.inBed => 'in_bed',
    SleepStage.outOfBed => 'out_of_bed',
    SleepStage.session => 'session',
  };

  /// Whether this stage counts as time asleep, for total-sleep-time
  /// aggregation.
  bool get isAsleep => switch (this) {
    SleepStage.light ||
    SleepStage.deep ||
    SleepStage.rem ||
    SleepStage.asleepUnspecified ||
    SleepStage.session => true,
    SleepStage.awake || SleepStage.inBed || SleepStage.outOfBed => false,
  };
}

/// Provenance of a reading (DESIGN.md §4.3): which app/device produced it.
///
/// Used both for source-priority deduplication and the OMH
/// `acquisition_provenance` block.
@immutable
class HealthSource {
  /// Creates a health-data source descriptor.
  const HealthSource({
    required this.name,
    required this.platform,
    required this.recordingMethod,
    this.deviceId,
  });

  /// Human-readable source/app name (e.g. `Samsung Health`).
  final String name;

  /// The OS platform that surfaced the reading.
  final HealthPlatform platform;

  /// How the reading was recorded.
  final RecordingMethodKind recordingMethod;

  /// Optional originating device id, when the platform exposes one. Internal
  /// only — never serialised into the OMH output, since it can be a hardware
  /// identifier and thus a de-anonymisation vector.
  final String? deviceId;
}
