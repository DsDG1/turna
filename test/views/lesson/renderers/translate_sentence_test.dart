import 'package:flutter_test/flutter_test.dart';
import 'package:varnamala/domain/course/interaction.dart';
import 'package:varnamala/views/lesson/components/interactions/translate_sentence_renderer.dart';

import 'renderer_test_helper.dart';

void main() {
  final harness = RendererTestHarness();

  setUp(() {
    harness.submissions.clear();
  });

  testWidgets('TranslateSentence submits true for correct translation',
      (tester) async {
    final renderer = TranslateSentenceRenderer();
    const interaction = Interaction.translateSentence(
      id: 'ts-1',
      source: 'Habari',
      expected: 'Hello',
    );

    await tester.pumpWidget(harness.build(renderer, interaction));
    await enterText(tester, 'Hello');
    await tapCheck(tester);

    expect(harness.submissions, [(true, 'Hello')]);
  });

  testWidgets('TranslateSentence submits false for wrong translation',
      (tester) async {
    final renderer = TranslateSentenceRenderer();
    const interaction = Interaction.translateSentence(
      id: 'ts-2',
      source: 'Habari',
      expected: 'Hello',
    );

    await tester.pumpWidget(harness.build(renderer, interaction));
    await enterText(tester, 'Goodbye');
    await tapCheck(tester);

    expect(harness.submissions, [(false, 'Goodbye')]);
  });
}
