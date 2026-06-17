import 'dart:io';

import 'package:cairn/src/app.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'support/platform_mocks.dart';

void main() {
  late Directory tempDir;

  setUp(() {
    tempDir = Directory.systemTemp.createTempSync('cairn_app_test');
    installPlatformMocks(tempDir);
  });
  tearDown(() {
    removePlatformMocks();
    tempDir.deleteSync(recursive: true);
  });

  testWidgets('CairnApp shows the navigation shell', (tester) async {
    // CairnServices.create() + the pages' file reads use real async that the
    // widget tester's fake-async can't drive; complete them on the real loop.
    await tester.runAsync(() async {
      await tester.pumpWidget(const CairnApp());
      await Future<void>.delayed(const Duration(milliseconds: 300));
    });
    // A few bounded frames to rebuild the resolved shell (no pumpAndSettle:
    // an offstage page may still be loading, which never "settles").
    for (var i = 0; i < 5; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }

    expect(find.byType(NavigationBar), findsOneWidget);
    expect(find.text('Sleep'), findsOneWidget);
    expect(find.text('Settings'), findsOneWidget);
  });
}
