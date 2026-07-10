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
}
