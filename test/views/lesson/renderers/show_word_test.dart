import 'package:flutter_test/flutter_test.dart';
import 'package:words625/courses/languages/kannada_vocab.dart';
import 'package:words625/domain/course/interaction.dart';
import 'package:words625/domain/course/word_entry.dart';
import 'package:words625/views/lesson/components/interactions/show_word_renderer.dart';

import 'renderer_test_helper.dart';

void main() {
  final harness = RendererTestHarness();

  setUp(() {
    harness.submissions.clear();
    swahiliVocabById['w-test-show'] = const WordEntry(
      id: 'w-test-show',
      term: 'Habari',
      translation: 'Hello',
    );
  });

  tearDown(() {
    swahiliVocabById.remove('w-test-show');
  });

  testWidgets('ShowWord builds and submits correct on tap', (tester) async {
    final renderer = ShowWordRenderer();
    final interaction = Interaction.showWord(
      id: 'sw-1',
      wordId: 'w-test-show',
    );

    await tester.pumpWidget(harness.build(renderer, interaction));
    expect(find.text('Habari'), findsOneWidget);

    await tester.tap(find.text('Tap to continue'));
    await tester.pumpAndSettle();

    expect(harness.submissions, [(true, null)]);
  });
}
