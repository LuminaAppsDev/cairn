import 'package:cairn/src/onboarding/setup_guide.dart';
import 'package:cairn/src/onboarding/setup_guide_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  Widget app(TargetPlatform platform) => MaterialApp(
    theme: ThemeData(platform: platform),
    home: const SetupGuidePage(),
  );

  testWidgets('shows the Android guide on Android', (tester) async {
    await tester.pumpWidget(app(TargetPlatform.android));
    await tester.pumpAndSettle();
    expect(find.text('Set up on Android'), findsOneWidget);
    expect(find.textContaining('Health Connect'), findsWidgets);
    expect(find.byType(Card), findsWidgets); // step cards render
    // Google Fit is shut down (DESIGN §4.1) — it must not be suggested.
    expect(find.textContaining('Google Fit'), findsNothing);
  });

  testWidgets('shows the iPhone guide on iOS', (tester) async {
    await tester.pumpWidget(app(TargetPlatform.iOS));
    await tester.pumpAndSettle();
    expect(find.text('Set up on iPhone'), findsOneWidget);
    expect(find.textContaining('Apple Health'), findsWidgets);
  });

  test('setupGuideFor selects per platform', () {
    expect(setupGuideFor(TargetPlatform.iOS).platformLabel, 'iPhone');
    expect(setupGuideFor(TargetPlatform.android).platformLabel, 'Android');
    // Non-mobile falls back to the Android guide.
    expect(setupGuideFor(TargetPlatform.linux).platformLabel, 'Android');
  });
}
