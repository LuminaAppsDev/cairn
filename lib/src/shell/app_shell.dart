import 'dart:async';

import 'package:cairn/src/home/home_page.dart';
import 'package:cairn/src/settings/settings_page.dart';
import 'package:cairn/src/shell/cairn_services.dart';
import 'package:cairn/src/sleep/sleep_page.dart';
import 'package:flutter/material.dart';

/// The app's root navigation shell: a bottom [NavigationBar] over Home, Sleep
/// and Settings, sharing one [CairnServices] for the screen's lifetime.
class AppShell extends StatefulWidget {
  /// Creates the app shell.
  const AppShell({super.key});

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

  @override
  Widget build(BuildContext context) {
    final services = _services;
    if (services == null) {
      return Scaffold(
        body: Center(
          child: _error == null
              ? const CircularProgressIndicator()
              : Padding(
                  padding: const EdgeInsets.all(24),
                  child: Text(
                    'Could not start Cairn: $_error',
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
      SleepPage(query: services.query),
      SettingsPage(services: services),
    ];
    return Scaffold(
      body: IndexedStack(index: _index, children: pages),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _index,
        onDestinationSelected: _select,
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.home_outlined),
            selectedIcon: Icon(Icons.home),
            label: 'Home',
          ),
          NavigationDestination(
            icon: Icon(Icons.bedtime_outlined),
            selectedIcon: Icon(Icons.bedtime),
            label: 'Sleep',
          ),
          NavigationDestination(
            icon: Icon(Icons.settings_outlined),
            selectedIcon: Icon(Icons.settings),
            label: 'Settings',
          ),
        ],
      ),
    );
  }
}
