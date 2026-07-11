import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:varnamala/domain/course/interaction.dart';
import 'package:varnamala/views/lesson/components/interactions/fill_blank_renderer.dart';

import 'renderer_test_helper.dart';

void main() {
  final harness = RendererTestHarness();

  setUp(() {
    harness.submissions.clear();
  });

  testWidgets('FillBlank submits true for correct answer', (tester) async {
    final renderer = FillBlankRenderer();
    const interaction = Interaction.fillBlank(
      id: 'fb-1',
      sentence: 'My name _____ John.',
      answer: 'is',
    );

    await tester.pumpWidget(harness.build(renderer, interaction));
    await enterText(tester, 'is');
    await tapCheck(tester);

    expect(harness.submissions, [(true, 'is')]);
  });

  testWidgets('FillBlank submits false for wrong answer', (tester) async {
    final renderer = FillBlankRenderer();
    const interaction = Interaction.fillBlank(
      id: 'fb-2',
      sentence: 'My name _____ John.',
      answer: 'is',
    );

    await tester.pumpWidget(harness.build(renderer, interaction));
    await enterText(tester, 'are');
    await tapCheck(tester);

    expect(harness.submissions, [(false, 'are')]);
  });

  testWidgets('typing enables CHECK via ValueListenableBuilder (no parent setState)',
      (tester) async {
    final renderer = FillBlankRenderer();
    const interaction = Interaction.fillBlank(
      id: 'fb-vlb',
      sentence: 'My name _____ John.',
      answer: 'is',
    );

    await tester.pumpWidget(harness.build(renderer, interaction));

    ElevatedButton checkButton() =>
        tester.widget(find.widgetWithText(ElevatedButton, 'CHECK'));

    // Empty input → CHECK disabled (onPressed null).
    expect(checkButton().onPressed, isNull);

    await tester.enterText(find.byType(TextField), 'is');
    // Single pump is enough for ValueListenableBuilder — full setState would
    // also work, but we assert the button flips without pumpAndSettle.
    await tester.pump();

    expect(checkButton().onPressed, isNotNull);
  });
}
