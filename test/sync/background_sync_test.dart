import 'package:cairn/src/sync/background_sync.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('initBackgroundSync is best-effort and never throws', () async {
    // There is no WorkManager platform implementation under unit tests; the
    // registration must swallow the resulting error rather than crash startup.
    await initBackgroundSync();
  });

  test('exposes a calm interval and a reverse-DNS task identifier', () {
    expect(backgroundSyncInterval, const Duration(hours: 6));
    // iOS BGTaskScheduler requires a reverse-DNS identifier.
    expect(backgroundSyncTask, contains('.'));
  });
}
