import 'package:flutter_test/flutter_test.dart';
import 'package:varnamala/domain/course/interaction.dart';
import 'package:varnamala/views/lesson/components/interactions/listen_only_renderer.dart';

import 'renderer_test_helper.dart';

void main() {
  final harness = RendererTestHarness();

  setUp(() {
    harness.submissions.clear();
  });

  testWidgets('ListenOnly builds and submits correct on continue',
      (tester) async {
    final renderer = ListenOnlyRenderer();
    const interaction = Interaction.listenOnly(
      id: 'lo-1',
      transcript: 'Habari, jambo.',
      prompt: 'Listen to the summary',
    );

    await tester.pumpWidget(harness.build(renderer, interaction));
    await tapContinue(tester);

    expect(harness.submissions, [(true, 'listened')]);
  });
}
