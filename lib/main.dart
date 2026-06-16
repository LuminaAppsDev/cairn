import 'dart:async';

import 'package:cairn/src/app.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

void main() {
  // Run inside a guarded zone with framework + platform error hooks so no
  // escaped async error (e.g. a fire-and-forget handler) can vanish silently.
  // In debug these still print; in release they are swallowed rather than
  // crashing — surfacing user-facing failures is each screen's own job.
  runZonedGuarded(
    () {
      WidgetsFlutterBinding.ensureInitialized();
      FlutterError.onError = (details) {
        FlutterError.presentError(details);
        debugPrint('Uncaught framework error: ${details.exception}');
      };
      PlatformDispatcher.instance.onError = (error, stack) {
        debugPrint('Uncaught platform error: $error');
        return true;
      };
      runApp(const CairnApp());
    },
    (error, stack) => debugPrint('Uncaught zone error: $error'),
  );
}
