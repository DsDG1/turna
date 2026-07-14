import 'package:flutter_test/flutter_test.dart';
import 'package:varnamala/domain/course/interaction.dart';
import 'package:varnamala/views/lesson/components/interactions/listen_and_pick_renderer.dart';

import 'renderer_test_helper.dart';

void main() {
  final harness = RendererTestHarness();

  setUp(() {
    harness.submissions.clear();
  });

  testWidgets('ListenAndPick submits true for correct option', (tester) async {
    final renderer = ListenAndPickRenderer();
    const interaction = Interaction.listenAndPick(
      id: 'lap-1',
      audioAsset: 'w-test-audio',
      prompt: 'What do you hear?',
      options: ['Habari', 'Asante'],
      correctIndex: 0,
    );

    await tester.pumpWidget(harness.build(renderer, interaction));
    await tapOption(tester, 'Habari');
    await tapCheck(tester);

    expect(harness.submissions, [(true, 'Habari')]);
  });

  testWidgets('ListenAndPick submits false for wrong option', (tester) async {
    final renderer = ListenAndPickRenderer();
    const interaction = Interaction.listenAndPick(
      id: 'lap-2',
      audioAsset: 'w-test-audio',
      prompt: 'What do you hear?',
      options: ['Habari', 'Asante'],
      correctIndex: 0,
    );

    await tester.pumpWidget(harness.build(renderer, interaction));
    await tapOption(tester, 'Asante');
    await tapCheck(tester);

    expect(harness.submissions, [(false, 'Asante')]);
  });
}
