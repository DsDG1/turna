// Shared helpers for interaction renderer widget tests.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:varnamala/domain/course/interaction.dart';
import 'package:varnamala/views/lesson/components/interactions/interaction_renderer.dart';

class RendererTestHarness {
  final List<(bool correct, String? userAnswer)> submissions = [];

  Widget build(InteractionRenderer renderer, Interaction interaction) {
    return MaterialApp(
      home: Scaffold(
        body: renderer.build(
          interaction,
          InteractionState.idle,
          (correct, {userAnswerText}) {
            submissions.add((correct, userAnswerText));
          },
        ),
      ),
    );
  }
}

Future<void> tapOption(WidgetTester tester, String label) async {
  await tester.tap(find.widgetWithText(InkWell, label));
  await tester.pumpAndSettle();
}

Future<void> tapCheck(WidgetTester tester) async {
  await tester.tap(find.widgetWithText(ElevatedButton, 'CHECK'));
  await tester.pumpAndSettle();
}

Future<void> tapContinue(WidgetTester tester) async {
  await tester.tap(find.widgetWithText(ElevatedButton, 'CONTINUE'));
  await tester.pumpAndSettle();
}

Future<void> enterText(WidgetTester tester, String text) async {
  await tester.enterText(find.byType(TextField), text);
  await tester.pumpAndSettle();
}
