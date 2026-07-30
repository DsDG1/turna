import 'package:flutter_test/flutter_test.dart';
import 'package:varnamala/courses/languages/vocab.dart';
import 'package:varnamala/domain/course/interaction.dart';
import 'package:varnamala/domain/course/word_entry.dart';
import 'package:varnamala/views/lesson/components/interactions/show_word_renderer.dart';

import 'fake_audio_controller.dart';
import 'renderer_test_helper.dart';

void main() {
  final harness = RendererTestHarness();

  setUp(() {
    harness.submissions.clear();
    vocabById['w-test-show'] = const WordEntry(
      id: 'w-test-show',
      term: 'Habari',
      translation: 'Hello',
    );
  });

  tearDown(() {
    vocabById.remove('w-test-show');
  });

  testWidgets('ShowWord builds and submits correct on tap', (tester) async {
    final renderer = ShowWordRenderer(FakeAudioController());
    const interaction = Interaction.showWord(
      id: 'sw-1',
      wordId: 'w-test-show',
    );

    await tester.pumpWidget(harness.build(renderer, interaction));
    expect(find.text('Habari'), findsOneWidget);

    await tester.tap(find.text('点击继续'));
    await tester.pumpAndSettle();

    expect(harness.submissions, [(true, null)]);
  });

  testWidgets('ShowWord speaks term and context sentence on tap', (tester) async {
    final audio = FakeAudioController();
    final renderer = ShowWordRenderer(audio);
    const interaction = Interaction.showWord(
      id: 'sw-1',
      wordId: 'w-test-show',
      context: 'Habari asubuhi. — Good morning.',
    );

    await tester.pumpWidget(harness.build(renderer, interaction));
    expect(find.text('Habari'), findsOneWidget);
    expect(find.text('Habari asubuhi. — Good morning.'), findsOneWidget);

    // Tapping the word speaks the term and does not submit.
    await tester.tap(find.text('Habari'));
    await tester.pumpAndSettle();
    expect(audio.lastSpoken, 'Habari');
    expect(harness.submissions, isEmpty);

    // Tapping the context sentence speaks only the target-language part.
    await tester.tap(find.text('Habari asubuhi. — Good morning.'));
    await tester.pumpAndSettle();
    expect(audio.lastSpoken, 'Habari asubuhi.');
    expect(harness.submissions, isEmpty);
  });
}
