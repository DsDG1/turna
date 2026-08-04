import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:turna/domain/course/interaction.dart';
import 'package:turna/views/lesson/components/interactions/reading_short_answer_renderer.dart';

import 'renderer_test_helper.dart';

void main() {
  final harness = RendererTestHarness();

  setUp(() {
    harness.submissions.clear();
  });

  testWidgets('ReadingShortAnswer submits true for correct answer',
      (tester) async {
    final renderer = ReadingShortAnswerRenderer();
    const interaction = Interaction.readingShortAnswer(
      id: 'rsa-1',
      prompt: 'What color is the sky?',
      expectedAnswer: 'Blue',
    );

    await tester.pumpWidget(harness.build(renderer, interaction));
    await enterText(tester, 'Blue');
    await tapCheck(tester);

    expect(harness.submissions, [(true, 'Blue')]);
  });

  testWidgets('ReadingShortAnswer submits false for wrong answer',
      (tester) async {
    final renderer = ReadingShortAnswerRenderer();
    const interaction = Interaction.readingShortAnswer(
      id: 'rsa-2',
      prompt: 'What color is the sky?',
      expectedAnswer: 'Blue',
    );

    await tester.pumpWidget(harness.build(renderer, interaction));
    await enterText(tester, 'Green');
    await tapCheck(tester);

    expect(harness.submissions, [(false, 'Green')]);
  });

  testWidgets('typing enables CHECK via ValueListenableBuilder',
      (tester) async {
    final renderer = ReadingShortAnswerRenderer();
    const interaction = Interaction.readingShortAnswer(
      id: 'rsa-vlb',
      prompt: 'What color is the sky?',
      expectedAnswer: 'Blue',
    );

    await tester.pumpWidget(harness.build(renderer, interaction));
    expect(isCheckEnabled(tester), isFalse);
    await tester.enterText(find.byType(TextField), 'Blue');
    await tester.pump();
    expect(isCheckEnabled(tester), isTrue);
  });
}
