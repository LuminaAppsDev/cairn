import 'package:cairn/l10n/app_localizations.dart';
import 'package:cairn/src/health/health_metric.dart';
import 'package:cairn/src/shell/cairn_services.dart';
import 'package:cairn/src/shell/refresh_feedback.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late AppLocalizations en;
  late AppLocalizations de;

  setUpAll(() async {
    en = await AppLocalizations.delegate.load(const Locale('en'));
    de = await AppLocalizations.delegate.load(const Locale('de'));
  });

  test('a read failure names its metrics, in a fixed order', () {
    // Set order differs from display order on purpose.
    const result = RefreshResult(
      RefreshStatus.readFailed,
      failedMetrics: {HealthMetric.steps, HealthMetric.heartRate},
    );

    expect(
      result.localizedMessage(en),
      'Could not read or save: Heart rate, Steps.',
    );
    expect(
      result.localizedMessage(de),
      'Lesen oder Speichern fehlgeschlagen: Puls, Schritte.',
    );
  });

  test('a read failure with nothing to name stays generic', () {
    const result = RefreshResult(RefreshStatus.readFailed);

    expect(result.localizedMessage(en), en.refreshReadFailed);
  });
}
