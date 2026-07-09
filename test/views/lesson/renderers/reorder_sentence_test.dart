import 'package:flutter_test/flutter_test.dart';
import 'package:words625/domain/course/interaction.dart';
import 'package:words625/views/lesson/components/interactions/reorder_sentence_renderer.dart';

import 'renderer_test_helper.dart';

void main() {
  final harness = RendererTestHarness();

  setUp(() {
    harness.submissions.clear();
  });

  testWidgets('ReorderSentence submits true for correct order', (tester) async {
    final renderer = ReorderSentenceRenderer();
    const interaction = Interaction.reorderSentence(
      id: 'rs-1',
      scrambled: ['world', 'hello'],
      correct: ['hello', 'world'],
    );

    await tester.pumpWidget(harness.build(renderer, interaction));
    await tapOption(tester, 'hello');
    await tapOption(tester, 'world');
    await tapCheck(tester);

    expect(harness.submissions, [(true, 'hello world')]);
  });

  testWidgets('ReorderSentence submits false for wrong order', (tester) async {
    final renderer = ReorderSentenceRenderer();
    const interaction = Interaction.reorderSentence(
      id: 'rs-2',
      scrambled: ['world', 'hello'],
      correct: ['hello', 'world'],
    );

    await tester.pumpWidget(harness.build(renderer, interaction));
    await tapOption(tester, 'world');
    await tapOption(tester, 'hello');
    await tapCheck(tester);

    expect(harness.submissions, [(false, 'world hello')]);
  });
}
