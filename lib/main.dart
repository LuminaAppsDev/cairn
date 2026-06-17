import 'dart:async';

import 'package:cairn/src/app.dart';
import 'package:cairn/src/settings/locale_controller.dart';
import 'package:cairn/src/settings/locale_store.dart';
import 'package:cairn/src/sync/background_sync.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

void main() {
  // Run inside a guarded zone with framework + platform error hooks so no
  // escaped async error (e.g. a fire-and-forget handler) can vanish silently.
  // In debug these still print; in release they are swallowed rather than
  // crashing — surfacing user-facing failures is each screen's own job.
  unawaited(
    runZonedGuarded(
      () async {
        WidgetsFlutterBinding.ensureInitialized();
        FlutterError.onError = (details) {
          FlutterError.presentError(details);
          debugPrint('Uncaught framework error: ${details.exception}');
        };
        PlatformDispatcher.instance.onError = (error, stack) {
          debugPrint('Uncaught platform error: $error');
          return true;
        };
        // Resolve the persisted language before the first frame so the
        // app opens in the right locale (null = follow the device locale).
        final localeStore = await LocaleStore.appSupport();
        final code = await localeStore.read();
        final localeController = LocaleController(
          localeStore,
          initial: code == null ? null : Locale(code),
        );
        runApp(CairnApp(localeController: localeController));
        // Schedule opportunistic background sync (DESIGN §4.4); best-effort and
        // never trusted for correctness, so it must not block or break startup.
        unawaited(initBackgroundSync());
      },
      (error, stack) => debugPrint('Uncaught zone error: $error'),
    ),
  );
}
