import 'package:flutter_test/flutter_test.dart';
import 'package:words625/domain/course/interaction.dart';
import 'package:words625/views/lesson/components/interactions/reading_mcq_renderer.dart';

import 'renderer_test_helper.dart';

void main() {
  final harness = RendererTestHarness();

  setUp(() {
    harness.submissions.clear();
  });

  testWidgets('ReadingMcq submits true for correct option', (tester) async {
    final renderer = ReadingMcqRenderer();
    const interaction = Interaction.readingMcq(
      id: 'rmcq-1',
      prompt: 'What is the answer?',
      options: ['A', 'B'],
      correctIndex: 0,
    );

    await tester.pumpWidget(harness.build(renderer, interaction));
    await tapOption(tester, 'A');
    await tapCheck(tester);

    expect(harness.submissions, [(true, 'A')]);
  });

  testWidgets('ReadingMcq submits false for wrong option', (tester) async {
    final renderer = ReadingMcqRenderer();
    const interaction = Interaction.readingMcq(
      id: 'rmcq-2',
      prompt: 'What is the answer?',
      options: ['A', 'B'],
      correctIndex: 0,
    );

    await tester.pumpWidget(harness.build(renderer, interaction));
    await tapOption(tester, 'B');
    await tapCheck(tester);

    expect(harness.submissions, [(false, 'B')]);
  });
}
