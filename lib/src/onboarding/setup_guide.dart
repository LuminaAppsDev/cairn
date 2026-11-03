import 'package:cairn/l10n/app_localizations.dart';
import 'package:flutter/foundation.dart';

/// One step in the data-source setup guide.
@immutable
class GuideStep {
  /// Creates a guide step.
  const new({required this.title, required this.body});

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
  const new({
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

/// Returns the localised guide for [platform]; falls back to Android for
/// non-mobile platforms.
SetupGuide setupGuideFor(TargetPlatform platform, AppLocalizations l10n) =>
    platform == TargetPlatform.iOS ? _iosGuide(l10n) : _androidGuide(l10n);

SetupGuide _androidGuide(AppLocalizations l10n) => SetupGuide(
  platformLabel: l10n.guideAndroidLabel,
  intro: l10n.guideAndroidIntro,
  steps: [
    GuideStep(
      title: l10n.guideAndroidStep1Title,
      body: l10n.guideAndroidStep1Body,
    ),
    GuideStep(
      title: l10n.guideAndroidStep2Title,
      body: l10n.guideAndroidStep2Body,
    ),
    GuideStep(
      title: l10n.guideAndroidStep3Title,
      body: l10n.guideAndroidStep3Body,
    ),
    GuideStep(
      title: l10n.guideAndroidStep4Title,
      body: l10n.guideAndroidStep4Body,
    ),
    GuideStep(
      title: l10n.guideAndroidStep5Title,
      body: l10n.guideAndroidStep5Body,
    ),
  ],
  note: l10n.guideAndroidNote,
);

SetupGuide _iosGuide(AppLocalizations l10n) => SetupGuide(
  platformLabel: l10n.guideIosLabel,
  intro: l10n.guideIosIntro,
  steps: [
    GuideStep(title: l10n.guideIosStep1Title, body: l10n.guideIosStep1Body),
    GuideStep(title: l10n.guideIosStep2Title, body: l10n.guideIosStep2Body),
    GuideStep(title: l10n.guideIosStep3Title, body: l10n.guideIosStep3Body),
    GuideStep(title: l10n.guideIosStep4Title, body: l10n.guideIosStep4Body),
  ],
  note: l10n.guideIosNote,
);
