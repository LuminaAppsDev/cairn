import 'package:cairn/src/health/health_source.dart';
import 'package:flutter/material.dart';

/// Colour for a sleep [stage] in charts and legends.
Color stageColor(SleepStage stage) => switch (stage) {
  SleepStage.deep => const Color(0xFF303F9F),
  SleepStage.light ||
  SleepStage.asleepUnspecified ||
  SleepStage.session => const Color(0xFF5C6BC0),
  SleepStage.rem => const Color(0xFF26A69A),
  SleepStage.awake ||
  SleepStage.inBed ||
  SleepStage.outOfBed => const Color(0xFFFFB74D),
};

/// Human-readable label for a sleep [stage].
String stageLabel(SleepStage stage) => switch (stage) {
  SleepStage.deep => 'Deep',
  SleepStage.light => 'Light',
  SleepStage.rem => 'REM',
  SleepStage.asleepUnspecified => 'Asleep',
  SleepStage.session => 'Sleep',
  SleepStage.awake => 'Awake',
  SleepStage.inBed => 'In bed',
  SleepStage.outOfBed => 'Out of bed',
};

/// Vertical depth rank for the hypnogram Y axis (deeper sleep lower). Awake is
/// at the top, deep at the bottom; light/asleep/session share the middle band.
double stageDepth(SleepStage stage) => switch (stage) {
  SleepStage.deep => 0,
  SleepStage.light || SleepStage.asleepUnspecified || SleepStage.session => 1,
  SleepStage.rem => 2,
  SleepStage.awake || SleepStage.inBed || SleepStage.outOfBed => 3,
};

/// Y-axis tick labels for the hypnogram, keyed by [stageDepth].
const Map<int, String> kHypnogramAxis = {
  0: 'Deep',
  1: 'Light',
  2: 'REM',
  3: 'Awake',
};
