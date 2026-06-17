import 'package:cairn/src/shell/cairn_services.dart';
import 'package:flutter/foundation.dart';
import 'package:workmanager/workmanager.dart';

/// Background-isolate entry point invoked by WorkManager / BGTaskScheduler.
///
/// Kept in its own file: it must be a top-level function annotated with
/// `@pragma('vm:entry-point')` so it survives tree-shaking and is callable from
/// a fresh isolate. (Pairing it with the scheduler API would trip
/// `unreachable_from_main`, since that API is reached from `main`, not here.)
@pragma('vm:entry-point')
void callbackDispatcher() {
  // executeTask initialises the binding before invoking this handler, so the
  // stores below (path_provider / secure storage) are safe to build here.
  Workmanager().executeTask((_, _) async {
    // Reuse the exact read→push cycle the foreground uses, so background and
    // manual sync can never diverge.
    final services = await CairnServices.create();
    try {
      final result = await services.refresh();
      // Retry only a (likely transient) upload failure; a read failure won't
      // be helped by an immediate retry — the next periodic run will try again.
      return result.status != RefreshStatus.syncFailed;
    } on Object catch (error) {
      // services.refresh() returns typed results and doesn't throw, so this is
      // a truly unexpected error (e.g. isolate/store setup). The message can't
      // carry the app password (it's never in an exception here). Don't retry —
      // an immediate retry rarely helps and spends the OS background budget.
      debugPrint('Background sync failed: $error');
      return true;
    } finally {
      services.dispose();
    }
  });
}
