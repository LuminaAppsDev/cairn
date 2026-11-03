import 'dart:async';

import 'package:cairn/l10n/app_localizations.dart';
import 'package:cairn/src/home/home_page.dart';
import 'package:cairn/src/settings/locale_controller.dart';
import 'package:cairn/src/settings/settings_page.dart';
import 'package:cairn/src/shell/cairn_services.dart';
import 'package:cairn/src/shell/refresh_feedback.dart';
import 'package:cairn/src/sleep/sleep_page.dart';
import 'package:flutter/material.dart';

/// The app's root navigation shell: a bottom [NavigationBar] over Home, Sleep
/// and Settings, sharing one [CairnServices] for the screen's lifetime.
class AppShell extends StatefulWidget {
  /// Creates the app shell driven by [localeController] (passed to Settings so
  /// the user can change the app language).
  const new({required this.localeController, super.key});

  /// The app-wide locale source, surfaced in the Settings language picker.
  final LocaleController localeController;

  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> {
  CairnServices? _services;
  String? _error;
  int _index = 0;

  @override
  void initState() {
    super.initState();
    unawaited(_init());
  }

  Future<void> _init() async {
    try {
      final services = await CairnServices.create();
      if (!mounted) {
        services.dispose(); // disposed before first build — close now
        return;
      }
      setState(() => _services = services);
      // Opportunistic foreground sync on open (DESIGN §4.4): screens already
      // show cached data; this reads new readings and uploads them, reloading
      // the screens when it lands. Silent — the manual Refresh/Sync now surface
      // errors; this is coalesced with any user-triggered refresh.
      unawaited(services.refresh());
    } on Object catch (error) {
      if (mounted) setState(() => _error = '$error');
    }
  }

  @override
  void dispose() {
    _services?.dispose();
    super.dispose();
  }

  void _select(int index) => setState(() => _index = index);

  /// Runs an ingest+sync and surfaces any failure as a localised snackbar.
  Future<void> _refresh(CairnServices services) async {
    final messenger = ScaffoldMessenger.of(context);
    final l10n = AppLocalizations.of(context);
    final result = await services.refresh();
    if (!mounted) return;
    final message = result.localizedMessage(l10n);
    if (message != null) {
      messenger.showSnackBar(SnackBar(content: Text(message)));
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final services = _services;
    if (services == null) {
      return Scaffold(
        body: Center(
          child: _error == null
              ? const CircularProgressIndicator()
              : Padding(
                  padding: const EdgeInsets.all(24),
                  child: Text(
                    l10n.shellStartError(_error!),
                    textAlign: TextAlign.center,
                  ),
                ),
        ),
      );
    }
    final pages = [
      HomePage(
        services: services,
        onOpenSleep: () => _select(1),
        onOpenSettings: () => _select(2),
      ),
      SleepPage(
        query: services.query,
        revision: services.dataRevision,
        onRefresh: () => _refresh(services),
      ),
      SettingsPage(
        services: services,
        localeController: widget.localeController,
      ),
    ];
    return Scaffold(
      body: IndexedStack(index: _index, children: pages),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _index,
        onDestinationSelected: _select,
        destinations: [
          NavigationDestination(
            icon: const Icon(Icons.home_outlined),
            selectedIcon: const Icon(Icons.home),
            label: l10n.navHome,
          ),
          NavigationDestination(
            icon: const Icon(Icons.bedtime_outlined),
            selectedIcon: const Icon(Icons.bedtime),
            label: l10n.navSleep,
          ),
          NavigationDestination(
            icon: const Icon(Icons.settings_outlined),
            selectedIcon: const Icon(Icons.settings),
            label: l10n.navSettings,
          ),
        ],
      ),
    );
  }
}
