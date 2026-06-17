import 'package:cairn/src/sync/background_sync_callback.dart';
import 'package:flutter/widgets.dart';
import 'package:workmanager/workmanager.dart';

/// Unique name + identifier for Cairn's periodic background sync.
///
/// On iOS this exact string must also appear in `Info.plist`
/// (`BGTaskSchedulerPermittedIdentifiers`) and be registered in
/// `AppDelegate.swift`.
const String backgroundSyncTask = 'io.github.theflipside.cairn.sync';

/// How often the OS is *asked* to run a background sync. The OS coalesces and
/// throttles this (Android floors at 15 min; iOS decides entirely), so treat it
/// as a ceiling on freshness, never a guarantee — correctness lives in the
/// manual "Sync now" and the foreground sync on open (DESIGN §4.4).
const Duration backgroundSyncInterval = Duration(hours: 6);

/// Initialises WorkManager and schedules the periodic sync. Safe to call on
/// every launch — [ExistingPeriodicWorkPolicy.update] keeps a single task and
/// applies any changed cadence/constraints. Best-effort: failures are logged,
/// never thrown, so they can't break startup.
Future<void> initBackgroundSync() async {
  try {
    await Workmanager().initialize(callbackDispatcher);
    await Workmanager().registerPeriodicTask(
      backgroundSyncTask,
      backgroundSyncTask,
      frequency: backgroundSyncInterval,
      constraints: Constraints(
        networkType: NetworkType.connected,
        requiresBatteryNotLow: true,
      ),
      existingWorkPolicy: ExistingPeriodicWorkPolicy.update,
    );
  } on Object catch (error) {
    debugPrint('Background sync registration failed: $error');
  }
}
