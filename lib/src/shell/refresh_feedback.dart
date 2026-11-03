import 'package:cairn/l10n/app_localizations.dart';
import 'package:cairn/src/health/health_metric.dart';
import 'package:cairn/src/shell/cairn_services.dart';
import 'package:cairn/src/shell/sync_error_feedback.dart';

/// Maps a [RefreshResult] to a localised, user-facing message — or `null` when
/// the refresh fully succeeded and nothing needs to be shown.
extension RefreshResultMessage on RefreshResult {
  /// The snackbar text for this result in the active locale, or `null` on
  /// success. A `null` [cause] yields a generic message — only a translated,
  /// typed error is ever interpolated into the user-facing text.
  String? localizedMessage(AppLocalizations l10n) => switch (status) {
    // Success is silent on this (snackbar) path — Home/Sleep/on-open show no
    // message even when a push ran; the report is surfaced only in Settings.
    RefreshStatus.ok => null,
    RefreshStatus.readFailed => readFailedMessage(l10n),
    RefreshStatus.healthUnavailable => l10n.refreshHealthUnavailable,
    RefreshStatus.syncFailed =>
      cause == null
          ? l10n.refreshSyncFailedGeneric
          : l10n.refreshSyncFailed(cause!.localizedMessage(l10n)),
  };

  /// The read-failure text, naming the [failedMetrics] (in a fixed order)
  /// when there are any: a metric that fails every run stays named until it
  /// reads again.
  String readFailedMessage(AppLocalizations l10n) {
    if (failedMetrics.isEmpty) return l10n.refreshReadFailed;
    final names = [
      for (final metric in HealthMetric.values)
        if (failedMetrics.contains(metric)) _title(metric, l10n),
    ];
    return l10n.refreshReadFailedFor(names.join(', '));
  }

  static String _title(HealthMetric metric, AppLocalizations l10n) =>
      switch (metric) {
        HealthMetric.heartRate => l10n.heartRateTitle,
        HealthMetric.steps => l10n.stepsTitle,
        HealthMetric.sleep => l10n.sleepTitle,
        HealthMetric.activity => l10n.activityTitle,
        HealthMetric.weight => l10n.weightTitle,
      };
}
