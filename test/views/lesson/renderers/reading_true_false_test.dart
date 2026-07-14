import 'package:flutter_test/flutter_test.dart';
import 'package:varnamala/domain/course/interaction.dart';
import 'package:varnamala/views/lesson/components/interactions/reading_true_false_renderer.dart';

import 'renderer_test_helper.dart';

void main() {
  final harness = RendererTestHarness();

  setUp(() {
    harness.submissions.clear();
  });

  testWidgets('ReadingTrueFalse submits true for correct answer',
      (tester) async {
    final renderer = ReadingTrueFalseRenderer();
    const interaction = Interaction.readingTrueFalse(
      id: 'rtf-1',
      statement: 'The sky is blue.',
      answer: true,
    );

    await tester.pumpWidget(harness.build(renderer, interaction));
    await tapOption(tester, 'True');
    await tapCheck(tester);

    expect(harness.submissions, [(true, 'True')]);
  });

  testWidgets('ReadingTrueFalse submits false for wrong answer',
      (tester) async {
    final renderer = ReadingTrueFalseRenderer();
    const interaction = Interaction.readingTrueFalse(
      id: 'rtf-2',
      statement: 'The sky is blue.',
      answer: true,
    );

    await tester.pumpWidget(harness.build(renderer, interaction));
    await tapOption(tester, 'False');
    await tapCheck(tester);

    expect(harness.submissions, [(false, 'False')]);
  });
}
