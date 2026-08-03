import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:turna/domain/course/interaction.dart';
import 'package:turna/views/lesson/components/interactions/type_the_word_renderer.dart';

import 'renderer_test_helper.dart';

void main() {
  final harness = RendererTestHarness();

  setUp(() {
    harness.submissions.clear();
  });

  testWidgets('TypeTheWord submits true for correct answer', (tester) async {
    final renderer = TypeTheWordRenderer();
    const interaction = Interaction.typeTheWord(
      id: 'ttw-1',
      audioAsset: 'w-test-audio',
      prompt: 'Type what you hear',
      expected: 'Habari',
    );

    await tester.pumpWidget(harness.build(renderer, interaction));
    await enterText(tester, 'Habari');
    await tapCheck(tester);

    expect(harness.submissions, [(true, 'Habari')]);
  });

  testWidgets('TypeTheWord submits false for wrong answer', (tester) async {
    final renderer = TypeTheWordRenderer();
    const interaction = Interaction.typeTheWord(
      id: 'ttw-2',
      audioAsset: 'w-test-audio',
      prompt: 'Type what you hear',
      expected: 'Habari',
    );

    await tester.pumpWidget(harness.build(renderer, interaction));
    await enterText(tester, 'Asante');
    await tapCheck(tester);

    expect(harness.submissions, [(false, 'Asante')]);
  });

  testWidgets('typing enables CHECK via ValueListenableBuilder',
      (tester) async {
    final renderer = TypeTheWordRenderer();
    const interaction = Interaction.typeTheWord(
      id: 'ttw-vlb',
      audioAsset: 'w-test-audio',
      prompt: 'Type what you hear',
      expected: 'Habari',
    );

    await tester.pumpWidget(harness.build(renderer, interaction));
    ElevatedButton checkButton() =>
        tester.widget(find.widgetWithText(ElevatedButton, '核对'));
    expect(checkButton().onPressed, isNull);
    await tester.enterText(find.byType(TextField), 'Habari');
    await tester.pump();
    expect(checkButton().onPressed, isNotNull);
  });
}
