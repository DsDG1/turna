// Shared helpers for interaction renderer widget tests.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:turna/domain/course/interaction.dart';
import 'package:turna/views/lesson/components/interactions/interaction_renderer.dart';

class RendererTestHarness {
  final List<(bool correct, String? userAnswer)> submissions = [];

  Widget build(InteractionRenderer renderer, Interaction interaction) {
    return MaterialApp(
      home: Scaffold(
        body: renderer.build(
          interaction,
          InteractionState.idle,
          (correct, {userAnswerText, reviewQuality}) {
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

/// LessonCheckButton is a gradient InkWell CTA (not ElevatedButton).
Future<void> tapCheck(WidgetTester tester) async {
  await tester.tap(find.widgetWithText(InkWell, '核对'));
  await tester.pumpAndSettle();
}

Future<void> tapContinue(WidgetTester tester) async {
  await tester.tap(find.widgetWithText(InkWell, '继续'));
  await tester.pumpAndSettle();
}

/// Whether the lesson CHECK CTA is enabled (InkWell.onTap non-null).
bool isCheckEnabled(WidgetTester tester) {
  final ink = tester.widget<InkWell>(find.widgetWithText(InkWell, '核对'));
  return ink.onTap != null;
}

Future<void> enterText(WidgetTester tester, String text) async {
  await tester.enterText(find.byType(TextField), text);
  await tester.pumpAndSettle();
}
