// Widget + unit tests for the beginner-guide return bubble.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:turna/application/guide_return_controller.dart';
import 'package:turna/di/injection.dart';
import 'package:turna/l10n/app_strings.dart';
import 'package:turna/service/tab_router.dart';
import 'package:turna/views/settings/widgets/guide_return_bubble.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late GuideReturnController controller;

  setUp(() async {
    await getIt.reset();
    controller = GuideReturnController();
    getIt.registerSingleton<GuideReturnController>(controller);
    getIt.registerLazySingleton<TabRouter>(() => TabRouter());
  });

  tearDown(() async {
    await getIt.reset();
  });

  test('arm shows; dismiss hides', () {
    expect(controller.visible, isFalse);
    controller.arm(guidePopped: true);
    expect(controller.visible, isTrue);
    expect(controller.guidePopped, isTrue);
    controller.dismiss();
    expect(controller.visible, isFalse);
    expect(controller.guidePopped, isFalse);
  });

  testWidgets('bubble appears after arm and dismisses on close', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Stack(
            children: [
              const SizedBox.expand(),
              const GuideReturnBubbleOverlay(),
            ],
          ),
        ),
      ),
    );
    await tester.pump();

    expect(find.text(AppStrings.beginnerGuideReturnBubble), findsNothing);

    controller.arm(guidePopped: false);
    await tester.pump();
    // No ParentDataWidget / layout exception (would paint a red error screen).
    expect(tester.takeException(), isNull);
    expect(find.text(AppStrings.beginnerGuideReturnBubble), findsOneWidget);

    // Tap the dismiss (close) control.
    await tester.tap(find.byIcon(Icons.close_rounded));
    await tester.pump();
    expect(find.text(AppStrings.beginnerGuideReturnBubble), findsNothing);
    expect(controller.visible, isFalse);
  });

  testWidgets('Positioned is outside ListenableBuilder (no ParentData crash)',
      (tester) async {
    // Reproduces the app-root Stack layout: Positioned must not sit under
    // ListenableBuilder or Flutter throws and paints a full red screen.
    await tester.pumpWidget(
      MaterialApp(
        builder: (context, child) => Stack(
          children: [
            child!,
            const GuideReturnBubbleOverlay(),
          ],
        ),
        home: const Scaffold(
          body: Center(child: Text('趣味实验室')),
        ),
      ),
    );
    await tester.pump();

    controller.arm(guidePopped: true);
    await tester.pump();

    expect(tester.takeException(), isNull);
    expect(find.text('趣味实验室'), findsOneWidget);
    expect(find.text(AppStrings.beginnerGuideReturnBubble), findsOneWidget);
    expect(find.byType(ErrorWidget), findsNothing);
  });
}
