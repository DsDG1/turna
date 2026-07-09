import 'package:flutter_test/flutter_test.dart';
import 'package:words625/domain/course/interaction.dart';
import 'package:words625/views/lesson/components/interactions/multiple_choice_renderer.dart';

import 'renderer_test_helper.dart';

void main() {
  final harness = RendererTestHarness();

  setUp(() {
    harness.submissions.clear();
  });

  testWidgets('MultipleChoice submits true for correct option', (tester) async {
    final renderer = MultipleChoiceRenderer();
    final interaction = Interaction.multipleChoice(
      id: 'mcq-1',
      prompt: 'Choose A',
      options: const ['A', 'B'],
      correctIndex: 0,
    );

    await tester.pumpWidget(harness.build(renderer, interaction));
    await tapOption(tester, 'A');
    await tapCheck(tester);

    expect(harness.submissions, [(true, 'A')]);
  });

  testWidgets('MultipleChoice submits false for wrong option', (tester) async {
    final renderer = MultipleChoiceRenderer();
    final interaction = Interaction.multipleChoice(
      id: 'mcq-2',
      prompt: 'Choose A',
      options: const ['A', 'B'],
      correctIndex: 0,
    );

    await tester.pumpWidget(harness.build(renderer, interaction));
    await tapOption(tester, 'B');
    await tapCheck(tester);

    expect(harness.submissions, [(false, 'B')]);
  });
}
