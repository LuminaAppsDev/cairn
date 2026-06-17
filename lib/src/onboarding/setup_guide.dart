import 'package:flutter/foundation.dart';

/// One step in the data-source setup guide.
@immutable
class GuideStep {
  /// Creates a guide step.
  const GuideStep({required this.title, required this.body});

  /// Short step heading.
  final String title;

  /// Explanatory body text.
  final String body;
}

/// An OS-specific walkthrough of getting health data flowing into Cairn
/// (DESIGN.md §8): set up a tracking app / wearable, link it to the OS health
/// store, grant permissions, then let Cairn read.
@immutable
class SetupGuide {
  /// Creates a setup guide.
  const SetupGuide({
    required this.platformLabel,
    required this.intro,
    required this.steps,
    required this.note,
  });

  /// The platform this guide targets (e.g. `Android`).
  final String platformLabel;

  /// One-paragraph overview of the data chain.
  final String intro;

  /// Ordered setup steps.
  final List<GuideStep> steps;

  /// Closing caveat about data completeness.
  final String note;
}

/// Returns the guide for [platform]; falls back to Android for non-mobile.
SetupGuide setupGuideFor(TargetPlatform platform) =>
    platform == TargetPlatform.iOS ? _iosGuide : _androidGuide;

const SetupGuide _androidGuide = SetupGuide(
  platformLabel: 'Android',
  intro:
      'Cairn reads from Android Health Connect — it never talks to your '
      'watch or band directly. Your tracking apps write data into Health '
      'Connect, and Cairn reads it from there.',
  steps: [
    GuideStep(
      title: '1. Make sure Health Connect is available',
      body:
          'On Android 14 and newer it is built into Settings. On older '
          'versions, install "Health Connect" from the Play Store.',
    ),
    GuideStep(
      title: '2. Use an app that records your data',
      body:
          'Use a health or fitness app that writes to Health Connect — for '
          'example Samsung Health, Fitbit, or Garmin Connect (or the fitness '
          'app that came with your phone). Cairn reads whatever they store.',
    ),
    GuideStep(
      title: '3. Pair your wearable in its own app',
      body:
          'Pair your watch or band in its vendor app (Samsung Health, '
          'Fitbit, Garmin Connect, …). Health Connect does not run on the '
          'watch, so data flows watch → vendor app → Health Connect; expect '
          'some delay set by the vendor.',
    ),
    GuideStep(
      title: '4. Link that app to Health Connect',
      body:
          'In the vendor/tracking app, turn on the Health Connect '
          'integration and let it WRITE the types you want: steps, heart '
          'rate, sleep, weight and exercise. Samsung Health also needs its '
          '"process health & wellness data" consent — a phone restart may be '
          'required before data appears.',
    ),
    GuideStep(
      title: '5. Let Cairn read',
      body:
          'Open Cairn and tap Refresh. Grant the Health Connect read '
          'permissions Cairn asks for (heart rate, steps, sleep, weight, '
          'exercise, plus distance and calories). Cairn only ever reads — it '
          'never writes to your health store.',
    ),
  ],
  note:
      'Cairn can only see what your apps actually write to Health Connect, so '
      'enable every relevant sub-category in each app. Permissions can be '
      'revoked at any time in Health Connect.',
);

const SetupGuide _iosGuide = SetupGuide(
  platformLabel: 'iPhone',
  intro:
      'Cairn reads from Apple Health, which is built into iOS. Your data must '
      'be in Apple Health first; Cairn reads it from there and never writes '
      'back.',
  steps: [
    GuideStep(
      title: '1. Apple Health is already installed',
      body:
          'There is nothing to install — the Health app is part of iOS and '
          'the iPhone records steps and walking data automatically.',
    ),
    GuideStep(
      title: '2. Get richer data into Apple Health',
      body:
          'For heart rate and sleep, pair an Apple Watch or your wearable, '
          'and use its companion app. Apple Watch writes to Apple Health '
          'automatically.',
    ),
    GuideStep(
      title: '3. Allow your apps to write to Apple Health',
      body:
          'For a third-party band/app, open its Apple Health permissions and '
          'allow it to write the types you want (heart rate, sleep, weight, '
          'workouts).',
    ),
    GuideStep(
      title: '4. Let Cairn read',
      body:
          'Open Cairn and tap Refresh. In the Apple Health sheet, allow Cairn '
          'to read heart rate, steps, sleep, weight and workouts. Cairn only '
          'ever reads.',
    ),
  ],
  note:
      'iOS hides whether a read permission was granted, so if a metric stays '
      'empty, re-check that you allowed it and that the data actually exists '
      'in Apple Health.',
);
