import 'package:cairn/l10n/app_localizations.dart';
import 'package:cairn/src/settings/locale_controller.dart';
import 'package:cairn/src/shell/app_shell.dart';
import 'package:flutter/material.dart';

/// Root widget for the Cairn application.
class CairnApp extends StatefulWidget {
  /// Creates the root Cairn application widget driven by [localeController].
  const new({required this.localeController, super.key});

  /// The app-wide locale source; the [MaterialApp] rebuilds when it changes.
  /// Owned here and disposed with the app.
  final LocaleController localeController;

  @override
  State<CairnApp> createState() => _CairnAppState();
}

class _CairnAppState extends State<CairnApp> {
  @override
  void dispose() {
    // The descendant ValueListenableBuilder is torn down before this runs
    // (leaf-first), so no listener remains when the notifier is disposed.
    widget.localeController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<Locale?>(
      valueListenable: widget.localeController,
      builder: (context, locale, _) => MaterialApp(
        title: 'Cairn',
        theme: ThemeData(colorSchemeSeed: Colors.teal, useMaterial3: true),
        locale: locale,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: AppShell(localeController: widget.localeController),
      ),
    );
  }
}
