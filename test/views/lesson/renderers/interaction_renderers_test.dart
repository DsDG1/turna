// Consolidated component tests for lesson interaction renderers:
// FillBlank, ListenAndPick, ListenOnly, MultiSelect, MultipleChoice,
// ReadingMcq, ReadingShortAnswer, ReadingTrueFalse, ReorderSentence,
// TranslateSentence, TypeTheWord, and ShowWord.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:turna/application/anki_official/official_anki_feature_flags.dart';
import 'package:turna/application/anki_official/projection/official_anki_course_entry.dart';
import 'package:turna/application/anki_official/projection/official_anki_projection_ids.dart';
import 'package:turna/courses/languages/vocab.dart';
import 'package:turna/domain/course/interaction.dart';
import 'package:turna/domain/course/word_entry.dart';
import 'package:turna/views/anki_official/official_anki_reviewer_page.dart';
import 'package:turna/views/lesson/components/interactions/fill_blank_renderer.dart';
import 'package:turna/views/lesson/components/interactions/listen_and_pick_renderer.dart';
import 'package:turna/views/lesson/components/interactions/listen_only_renderer.dart';
import 'package:turna/views/lesson/components/interactions/multi_select_renderer.dart';
import 'package:turna/views/lesson/components/interactions/multiple_choice_renderer.dart';
import 'package:turna/views/lesson/components/interactions/reading_mcq_renderer.dart';
import 'package:turna/views/lesson/components/interactions/reading_short_answer_renderer.dart';
import 'package:turna/views/lesson/components/interactions/reading_true_false_renderer.dart';
import 'package:turna/views/lesson/components/interactions/reorder_sentence_renderer.dart';
import 'package:turna/views/lesson/components/interactions/show_word_renderer.dart';
import 'package:turna/views/lesson/components/interactions/translate_sentence_renderer.dart';
import 'package:turna/views/lesson/components/interactions/type_the_word_renderer.dart';

import '../../../helpers/in_memory_course_db.dart';
import 'fake_audio_controller.dart';
import 'renderer_test_helper.dart';

void main() {
  final harness = RendererTestHarness();

  setUp(() {
    harness.submissions.clear();
  });

  group('FillBlankRenderer', () {
    testWidgets('submits true for correct answer', (tester) async {
      final renderer = FillBlankRenderer();
      const interaction = Interaction.fillBlank(
        id: 'fb-1',
        sentence: 'I ___ a student.',
        answer: 'am',
      );

      await tester.pumpWidget(harness.build(renderer, interaction));
      await enterText(tester, 'am');
      await tapCheck(tester);

      expect(harness.submissions, [(true, 'am')]);
    });

    testWidgets('submits false for wrong answer', (tester) async {
      final renderer = FillBlankRenderer();
      const interaction = Interaction.fillBlank(
        id: 'fb-2',
        sentence: 'I ___ a student.',
        answer: 'am',
      );

      await tester.pumpWidget(harness.build(renderer, interaction));
      await enterText(tester, 'is');
      await tapCheck(tester);

      expect(harness.submissions, [(false, 'is')]);
    });

    testWidgets(
        'typing enables CHECK via ValueListenableBuilder (no parent setState)',
        (tester) async {
      final renderer = FillBlankRenderer();
      const interaction = Interaction.fillBlank(
        id: 'fb-vlb',
        sentence: 'My name _____ John.',
        answer: 'is',
      );

      await tester.pumpWidget(harness.build(renderer, interaction));

      // Empty input → CHECK disabled (InkWell.onTap null).
      expect(isCheckEnabled(tester), isFalse);

      await tester.enterText(find.byType(TextField), 'is');
      // Single pump is enough for ValueListenableBuilder — full setState would
      // also work, but we assert the button flips without pumpAndSettle.
      await tester.pump();

      expect(isCheckEnabled(tester), isTrue);
    });
  });

  group('ListenAndPickRenderer', () {
    testWidgets('submits true for correct option', (tester) async {
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

    testWidgets('submits false for wrong option', (tester) async {
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
  });

  group('ListenOnlyRenderer', () {
    testWidgets('builds and submits correct on continue', (tester) async {
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
  });

  group('MultiSelectRenderer', () {
    testWidgets('submits true when all correct options picked', (tester) async {
      final renderer = MultiSelectRenderer();
      const interaction = Interaction.multiSelect(
        id: 'ms-1',
        prompt: 'Select the words you heard',
        options: ['apple', 'banana', 'carrot', 'date'],
        correctIndices: [0, 2],
        minSelections: 2,
        maxSelections: 2,
      );

      await tester.pumpWidget(harness.build(renderer, interaction));
      await tapOption(tester, 'apple');
      await tapOption(tester, 'carrot');
      await tapCheck(tester);

      expect(harness.submissions, [(true, '0,2')]);
    });

    testWidgets('submits false when a wrong option is picked', (tester) async {
      final renderer = MultiSelectRenderer();
      const interaction = Interaction.multiSelect(
        id: 'ms-2',
        prompt: 'Select the words you heard',
        options: ['apple', 'banana', 'carrot', 'date'],
        correctIndices: [0, 2],
        minSelections: 2,
        maxSelections: 2,
      );

      await tester.pumpWidget(harness.build(renderer, interaction));
      await tapOption(tester, 'apple');
      await tapOption(tester, 'banana');
      await tapCheck(tester);

      expect(harness.submissions, [(false, '0,1')]);
    });

    testWidgets('disables check until selection count is in range', (tester) async {
      final renderer = MultiSelectRenderer();
      const interaction = Interaction.multiSelect(
        id: 'ms-3',
        prompt: 'Select the words you heard',
        options: ['apple', 'banana', 'carrot', 'date'],
        correctIndices: [0, 2],
        minSelections: 2,
        maxSelections: 2,
      );

      await tester.pumpWidget(harness.build(renderer, interaction));

      // No selection yet: check button should be disabled.
      expect(isCheckEnabled(tester), isFalse);

      await tapOption(tester, 'apple');
      expect(isCheckEnabled(tester), isFalse);

      await tapOption(tester, 'carrot');
      expect(isCheckEnabled(tester), isTrue);
    });
  });

  group('MultipleChoiceRenderer', () {
    testWidgets('submits true for correct option', (tester) async {
      final renderer = MultipleChoiceRenderer();
      const interaction = Interaction.multipleChoice(
        id: 'mcq-1',
        prompt: 'Choose A',
        options: ['A', 'B'],
        correctIndex: 0,
      );

      await tester.pumpWidget(harness.build(renderer, interaction));
      await tapOption(tester, 'A');
      await tapCheck(tester);

      expect(harness.submissions, [(true, 'A')]);
    });

    testWidgets('submits false for wrong option', (tester) async {
      final renderer = MultipleChoiceRenderer();
      const interaction = Interaction.multipleChoice(
        id: 'mcq-2',
        prompt: 'Choose A',
        options: ['A', 'B'],
        correctIndex: 0,
      );

      await tester.pumpWidget(harness.build(renderer, interaction));
      await tapOption(tester, 'B');
      await tapCheck(tester);

      expect(harness.submissions, [(false, 'B')]);
    });
  });

  group('ReadingMcqRenderer', () {
    testWidgets('submits true for correct option', (tester) async {
      final renderer = ReadingMcqRenderer();
      const interaction = Interaction.readingMcq(
        id: 'rmcq-1',
        prompt: 'Choose A',
        options: ['A', 'B'],
        correctIndex: 0,
      );

      await tester.pumpWidget(harness.build(renderer, interaction));
      await tapOption(tester, 'A');
      await tapCheck(tester);

      expect(harness.submissions, [(true, 'A')]);
    });

    testWidgets('submits false for wrong option', (tester) async {
      final renderer = ReadingMcqRenderer();
      const interaction = Interaction.readingMcq(
        id: 'rmcq-2',
        prompt: 'Choose A',
        options: ['A', 'B'],
        correctIndex: 0,
      );

      await tester.pumpWidget(harness.build(renderer, interaction));
      await tapOption(tester, 'B');
      await tapCheck(tester);

      expect(harness.submissions, [(false, 'B')]);
    });
  });

  group('ReadingShortAnswerRenderer', () {
    testWidgets('submits true for correct answer', (tester) async {
      final renderer = ReadingShortAnswerRenderer();
      const interaction = Interaction.readingShortAnswer(
        id: 'rsa-1',
        prompt: 'What color is the sky?',
        expectedAnswer: 'Blue',
      );

      await tester.pumpWidget(harness.build(renderer, interaction));
      await enterText(tester, 'Blue');
      await tapCheck(tester);

      expect(harness.submissions, [(true, 'Blue')]);
    });

    testWidgets('submits false for wrong answer', (tester) async {
      final renderer = ReadingShortAnswerRenderer();
      const interaction = Interaction.readingShortAnswer(
        id: 'rsa-2',
        prompt: 'What color is the sky?',
        expectedAnswer: 'Blue',
      );

      await tester.pumpWidget(harness.build(renderer, interaction));
      await enterText(tester, 'Green');
      await tapCheck(tester);

      expect(harness.submissions, [(false, 'Green')]);
    });

    testWidgets('typing enables CHECK via ValueListenableBuilder', (tester) async {
      final renderer = ReadingShortAnswerRenderer();
      const interaction = Interaction.readingShortAnswer(
        id: 'rsa-vlb',
        prompt: 'What color is the sky?',
        expectedAnswer: 'Blue',
      );

      await tester.pumpWidget(harness.build(renderer, interaction));
      expect(isCheckEnabled(tester), isFalse);
      await tester.enterText(find.byType(TextField), 'Blue');
      await tester.pump();
      expect(isCheckEnabled(tester), isTrue);
    });
  });

  group('ReadingTrueFalseRenderer', () {
    testWidgets('submits true for correct answer', (tester) async {
      final renderer = ReadingTrueFalseRenderer();
      const interaction = Interaction.readingTrueFalse(
        id: 'rtf-1',
        statement: 'The sky is blue.',
        answer: true,
      );

      await tester.pumpWidget(harness.build(renderer, interaction));
      await tapOption(tester, '正确');
      await tapCheck(tester);

      expect(harness.submissions, [(true, 'True')]);
    });

    testWidgets('submits false for wrong answer', (tester) async {
      final renderer = ReadingTrueFalseRenderer();
      const interaction = Interaction.readingTrueFalse(
        id: 'rtf-2',
        statement: 'The sky is blue.',
        answer: true,
      );

      await tester.pumpWidget(harness.build(renderer, interaction));
      await tapOption(tester, '错误');
      await tapCheck(tester);

      expect(harness.submissions, [(false, 'False')]);
    });
  });

  group('ReorderSentenceRenderer', () {
    testWidgets('submits true for correct order', (tester) async {
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

    testWidgets('submits false for wrong order', (tester) async {
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
  });

  group('TranslateSentenceRenderer', () {
    testWidgets('submits true for correct translation', (tester) async {
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

    testWidgets('submits false for wrong translation', (tester) async {
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

    testWidgets('typing enables CHECK via ValueListenableBuilder', (tester) async {
      final renderer = TranslateSentenceRenderer();
      const interaction = Interaction.translateSentence(
        id: 'ts-vlb',
        source: 'Habari',
        expected: 'Hello',
      );

      await tester.pumpWidget(harness.build(renderer, interaction));
      expect(isCheckEnabled(tester), isFalse);
      await tester.enterText(find.byType(TextField), 'Hello');
      await tester.pump();
      expect(isCheckEnabled(tester), isTrue);
    });
  });

  group('TypeTheWordRenderer', () {
    testWidgets('submits true for correct answer', (tester) async {
      final renderer = TypeTheWordRenderer();
      const interaction = Interaction.typeTheWord(
        id: 'ttw-1',
        audioAsset: 'w-test-audio',
        prompt: 'Type what you hear',
        expected: 'Habari',
      );

      await tester.pumpWidget(harness.build(renderer, interaction));
      await enterText(tester, 'Habari');
      await tapCheck(tester);

      expect(harness.submissions, [(true, 'Habari')]);
    });

    testWidgets('submits false for wrong answer', (tester) async {
      final renderer = TypeTheWordRenderer();
      const interaction = Interaction.typeTheWord(
        id: 'ttw-2',
        audioAsset: 'w-test-audio',
        prompt: 'Type what you hear',
        expected: 'Habari',
      );

      await tester.pumpWidget(harness.build(renderer, interaction));
      await enterText(tester, 'Asante');
      await tapCheck(tester);

      expect(harness.submissions, [(false, 'Asante')]);
    });

    testWidgets('typing enables CHECK via ValueListenableBuilder', (tester) async {
      final renderer = TypeTheWordRenderer();
      const interaction = Interaction.typeTheWord(
        id: 'ttw-vlb',
        audioAsset: 'w-test-audio',
        prompt: 'Type what you hear',
        expected: 'Habari',
      );

      await tester.pumpWidget(harness.build(renderer, interaction));
      expect(isCheckEnabled(tester), isFalse);
      await tester.enterText(find.byType(TextField), 'Habari');
      await tester.pump();
      expect(isCheckEnabled(tester), isTrue);
    });
  });

  group('ShowWordRenderer', () {
    setUp(() {
      vocabById['w-test-show'] = const WordEntry(
        id: 'w-test-show',
        term: 'Habari',
        translation: 'Hello',
      );
    });

    tearDown(() {
      vocabById.remove('w-test-show');
    });

    testWidgets('builds and submits correct on tap', (tester) async {
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

    testWidgets('speaks term and context sentence on tap', (tester) async {
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

    testWidgets('renders long terms on narrow screens without overflow', (tester) async {
      tester.view.physicalSize = const Size(360, 640);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(() => tester.view.resetPhysicalSize());
      addTearDown(() => tester.view.resetDevicePixelRatio());

      final audio = FakeAudioController();
      final renderer = ShowWordRenderer(audio);
      const interaction = Interaction.showWord(
        id: 'sw-long',
        wordId: 'w-long',
        term: 'affedersiniz',
        translation: 'excuse me',
        context: 'affedersiniz — excuse me',
      );

      await tester.pumpWidget(harness.build(renderer, interaction));
      expect(find.text('affedersiniz'), findsOneWidget);
      expect(find.text('excuse me'), findsOneWidget);
      expect(tester.takeException(), isNull);

      await tester.tap(find.text('affedersiniz'));
      await tester.pumpAndSettle();
      expect(audio.lastSpoken, 'affedersiniz');
      expect(tester.takeException(), isNull);
    });

    testWidgets('canonicalLink fail-closes without opening vocab or Legacy', (tester) async {
      OfficialAnkiCourseEntry.resetHooks();
      addTearDown(OfficialAnkiCourseEntry.resetHooks);
      OfficialAnkiCourseEntry.flagsOf = () => const OfficialAnkiFeatureFlags();
      final renderer = ShowWordRenderer(FakeAudioController());
      final interaction = Interaction.showWord(
        id: 'sw-link',
        wordId: officialAnkiCanonicalWordId(sourceId: 'src1', cardId: 1),
        context: 'official-canonical-link:src1:1',
      );
      await tester.pumpWidget(harness.build(renderer, interaction));
      expect(find.byKey(const Key('official-canonical-fail-closed')),
          findsOneWidget);
      expect(find.byKey(const Key('official-canonical-continue')), findsNothing);
      expect(find.text('Habari'), findsNothing);
      expect(find.byType(OfficialAnkiReviewerPage), findsNothing);
    });

    testWidgets('canonicalLink renders inline without a route push', (tester) async {
      ensurePathProviderMockForTest();
      OfficialAnkiCourseEntry.resetHooks();
      addTearDown(OfficialAnkiCourseEntry.resetHooks);
      OfficialAnkiCourseEntry.flagsOf = () => const OfficialAnkiFeatureFlags(
            engine: true,
            catalogReady: true,
            runtimeCapable: true,
            platformReady: true,
            renderer: true,
          );
      final renderer = ShowWordRenderer(FakeAudioController());
      final interaction = Interaction.showWord(
        id: 'sw-link',
        wordId: officialAnkiCanonicalWordId(sourceId: 'src1', cardId: 9),
        context: 'official-canonical-link:src1:9',
      );
      await tester.pumpWidget(harness.buildRouted(renderer, interaction));
      // AutoRoute resolves the initial host page asynchronously; boot then
      // fails deterministically (no worker session in the test environment).
      await tester.pumpAndSettle();

      // No route push ever happens: the card itself is the surface.
      expect(find.byType(OfficialAnkiReviewerPage), findsNothing);
      expect(find.byKey(const Key('official-canonical-boot-failed')),
          findsOneWidget);
      // Release hatch: a card whose boot failed must not stall the lesson.
      final button = tester.widget<FilledButton>(
        find.byKey(const Key('official-canonical-continue')),
      );
      expect(button.onPressed, isNotNull);
      await tester.tap(find.byKey(const Key('official-canonical-continue')));
      await tester.pumpAndSettle();
      expect(harness.submissions, [(true, null)]);
    });
  });
}
