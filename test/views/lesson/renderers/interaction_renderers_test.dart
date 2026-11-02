// Consolidated component tests for lesson interaction renderers:
// FillBlank, ListenAndPick, ListenOnly, MultiSelect, MultipleChoice,
// ReadingMcq, ReadingShortAnswer, ReadingTrueFalse, ReorderSentence,
// TranslateSentence, TypeTheWord, ShowWord, and ReadAloud.

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
import 'package:turna/views/lesson/components/interactions/interaction_renderer.dart';
import 'package:turna/views/lesson/components/interactions/listen_and_pick_renderer.dart';
import 'package:turna/views/lesson/components/interactions/listen_only_renderer.dart';
import 'package:turna/views/lesson/components/interactions/read_aloud_renderer.dart';
import 'package:turna/views/lesson/components/interactions/multi_select_renderer.dart';
import 'package:turna/views/lesson/components/interactions/multiple_choice_renderer.dart';
import 'package:turna/views/lesson/components/interactions/reading_mcq_renderer.dart';
import 'package:turna/views/lesson/components/interactions/reading_short_answer_renderer.dart';
import 'package:turna/views/lesson/components/interactions/reading_true_false_renderer.dart';
import 'package:turna/views/lesson/components/interactions/reorder_sentence_renderer.dart';
import 'package:turna/views/lesson/components/interactions/show_word_renderer.dart';
import 'package:turna/views/lesson/components/interactions/translate_sentence_renderer.dart';
import 'package:turna/views/lesson/components/interactions/type_the_word_renderer.dart';

import 'package:shared_preferences/shared_preferences.dart';
import 'package:streaming_shared_preferences/streaming_shared_preferences.dart';
import 'package:turna/application/settings_provider.dart';
import 'package:turna/di/injection.dart';
import 'package:turna/service/locator.dart';
import 'package:turna/service/read_aloud_backend.dart';

import '../../../helpers/in_memory_course_db.dart';
import 'fake_audio_controller.dart';
import 'fake_read_aloud_backend.dart';
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

    testWidgets('hides CHECK after submit', (tester) async {
      final renderer = FillBlankRenderer();
      const interaction = Interaction.fillBlank(
        id: 'fb-checked',
        sentence: 'I ___ a student.',
        answer: 'am',
      );

      await tester.pumpWidget(
        harness.build(
          renderer,
          interaction,
          state: const InteractionState(submitted: true, correct: true),
        ),
      );
      expect(find.text('核对'), findsNothing);
      expect(find.text('已核对'), findsNothing);
    });

    testWidgets('accepts ASCII iyi for dotted-İ answer İyi', (tester) async {
      final renderer = FillBlankRenderer();
      const interaction = Interaction.fillBlank(
        id: 'fb-tr',
        sentence: '___ günler.',
        answer: 'İyi',
      );

      await tester.pumpWidget(harness.build(renderer, interaction));
      await enterText(tester, 'iyi');
      await tapCheck(tester);

      expect(harness.submissions, [(true, 'iyi')]);
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

    testWidgets('choices mode: CHECK disabled until a chip is tapped',
        (tester) async {
      final renderer = FillBlankRenderer();
      const interaction = Interaction.fillBlank(
        id: 'fb-choices-idle',
        sentence: '「谢谢」= _____',
        answer: 'Teşekkürler',
        choices: ['Teşekkürler', 'Merhaba', 'Türkçe'],
      );

      await tester.pumpWidget(harness.build(renderer, interaction));

      // 选择填空 has no text field at all.
      expect(find.byType(TextField), findsNothing);
      expect(isCheckEnabled(tester), isFalse);

      await tapOption(tester, 'Teşekkürler');
      expect(isCheckEnabled(tester), isTrue);
    });

    testWidgets('choices mode: restores the picked chip when submitted',
        (tester) async {
      final renderer = FillBlankRenderer();
      const interaction = Interaction.fillBlank(
        id: 'fb-choices-submit',
        sentence: '— Merhaba!\n— _____',
        answer: 'Merhaba!',
        choices: ['Teşekkürler!', 'Merhaba!', 'Türkçe!'],
      );

      // Harness 不推进 submitted（页面级状态由外部持有），锁死行为按既有
      // 'hides CHECK after submit' 模式直接以 submitted 状态构建来验证。
      await tester.pumpWidget(
        harness.build(
          renderer,
          interaction,
          state: const InteractionState(
            submitted: true,
            correct: true,
            userAnswerText: 'Merhaba!',
          ),
        ),
      );
      expect(find.text('核对'), findsNothing);
      // 已选项回填进挖空（空白处一份）+ 词块本身一份，同文本各在原位.
      expect(find.text('Merhaba!'), findsNWidgets(2));
      // 词块渲染为不可点（onTap null），再点不炸也不再产生选择.
      await tester.tap(find.byKey(const ValueKey(2)));
      await tester.pumpAndSettle();
      expect(find.text('Merhaba!'), findsNWidgets(2));
    });

    testWidgets('choices mode: submits false for wrong chip', (tester) async {
      final renderer = FillBlankRenderer();
      const interaction = Interaction.fillBlank(
        id: 'fb-choices-wrong',
        sentence: '「谢谢」= _____',
        answer: 'Teşekkürler',
        choices: ['Teşekkürler', 'Merhaba', 'Türkçe'],
      );

      await tester.pumpWidget(harness.build(renderer, interaction));
      await tapOption(tester, 'Merhaba');
      await tapCheck(tester);

      expect(harness.submissions, [(false, 'Merhaba')]);
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

    testWidgets('disables check until selection count is in range',
        (tester) async {
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

    testWidgets('accepts ASCII iyi for dotted-İ answer İyi', (tester) async {
      final renderer = ReadingShortAnswerRenderer();
      const interaction = Interaction.readingShortAnswer(
        id: 'rsa-tr',
        prompt: 'How do you say good?',
        expectedAnswer: 'İyi',
      );

      await tester.pumpWidget(harness.build(renderer, interaction));
      await enterText(tester, 'iyi');
      await tapCheck(tester);

      expect(harness.submissions, [(true, 'iyi')]);
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

    testWidgets('typing enables CHECK via ValueListenableBuilder',
        (tester) async {
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
    // 词库芯片放进句子后不消失（原位变暗锁定），按文本找会同时命中词库和句中
    // 两枚芯片 —— 全组统一用稳定 pool id（ValueKey('pool-<scrambled 下标>')）点词。
    testWidgets('submits true for correct order', (tester) async {
      final renderer = ReorderSentenceRenderer();
      const interaction = Interaction.reorderSentence(
        id: 'rs-1',
        scrambled: ['world', 'hello'], // pool: 0='world', 1='hello'
        correct: ['hello', 'world'],
      );

      await tester.pumpWidget(harness.build(renderer, interaction));
      await tapPoolChip(tester, 1);
      await tapPoolChip(tester, 0);
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
      await tapPoolChip(tester, 0);
      await tapPoolChip(tester, 1);
      await tapCheck(tester);

      expect(harness.submissions, [(false, 'world hello')]);
    });

    testWidgets('renders the source prompt above the word bank', (tester) async {
      final renderer = ReorderSentenceRenderer();
      const interaction = Interaction.reorderSentence(
        id: 'rs-prompt',
        prompt: '「我要一杯咖啡」（istiyorum=我要，bir=一，kahve=咖啡）',
        scrambled: ['kahve', 'istiyorum', 'bir'], // pool: 0/1/2
        correct: ['bir', 'kahve', 'istiyorum'],
      );

      await tester.pumpWidget(harness.build(renderer, interaction));
      expect(
        find.text('「我要一杯咖啡」（istiyorum=我要，bir=一，kahve=咖啡）'),
        findsOneWidget,
      );

      // 翻译拼句 still builds from the word bank — tapping a token both
      // moves it and (outside tests, where no AudioController is registered)
      // speaks it.
      await tapPoolChip(tester, 2);
      await tapPoolChip(tester, 0);
      await tapPoolChip(tester, 1);
      await tapCheck(tester);

      expect(harness.submissions, [(true, 'bir kahve istiyorum')]);
    });

    testWidgets('placed pool chip cannot be picked twice', (tester) async {
      final renderer = ReorderSentenceRenderer();
      const interaction = Interaction.reorderSentence(
        id: 'rs-repeat',
        scrambled: ['a', 'b'], // pool: 0='a', 1='b'
        correct: ['a', 'b'],
      );

      await tester.pumpWidget(harness.build(renderer, interaction));
      await tapPoolChip(tester, 0);
      // 已放置的词库芯片 onTap 为 null —— 第二次点击必须是 no-op.
      await tapPoolChip(tester, 0);

      expect(find.byKey(const ValueKey('picked-0')), findsOneWidget);
      // 词库芯片仍在原位（变暗），不消失.
      expect(find.byKey(const ValueKey('pool-0')), findsOneWidget);

      await tapPoolChip(tester, 1);
      await tapCheck(tester);

      expect(harness.submissions, [(true, 'a b')]);
    });

    testWidgets('tap answer chip returns it to the pool, then back in',
        (tester) async {
      final renderer = ReorderSentenceRenderer();
      const interaction = Interaction.reorderSentence(
        id: 'rs-return',
        scrambled: ['world', 'hello'],
        correct: ['hello', 'world'],
      );

      await tester.pumpWidget(harness.build(renderer, interaction));
      await tapPoolChip(tester, 1);
      expect(find.byKey(const ValueKey('picked-1')), findsOneWidget);

      await tapAnswerChip(tester, 1);
      expect(find.byKey(const ValueKey('picked-1')), findsNothing);

      // 词库芯片重新可用: 再次放入, 换个顺序拼对.
      await tapPoolChip(tester, 1);
      await tapPoolChip(tester, 0);
      await tapCheck(tester);

      expect(harness.submissions, [(true, 'hello world')]);
    });

    testWidgets('long-press drag reorders within the answer row',
        (tester) async {
      final renderer = ReorderSentenceRenderer();
      const interaction = Interaction.reorderSentence(
        id: 'rs-drag',
        scrambled: ['b', 'a'], // pool: 0='b', 1='a'
        correct: ['a', 'b'],
      );

      await tester.pumpWidget(harness.build(renderer, interaction));
      await tapPoolChip(tester, 0); // b 先入句
      await tapPoolChip(tester, 1); // a 后入句 → "b a"（错序）

      // 长按句首 'b'（picked-0），越过 kLongPressTimeout 后拖到 'a'（picked-1）
      // 芯片中心上放手 —— 瞄准目标芯片中心而不是固定像素, 免受芯片宽度影响.
      final start = tester.getCenter(find.byKey(const ValueKey('picked-0')));
      final target = tester.getCenter(find.byKey(const ValueKey('picked-1')));
      final gesture = await tester.startGesture(start);
      await tester.pump(const Duration(milliseconds: 600));
      // 分两步移动, 模拟真实拖拽路径, 给 DragTarget 一帧处理 hover.
      final half = (target - start) * 0.6;
      await gesture.moveBy(half);
      await tester.pump();
      await gesture.moveBy(target - start - half);
      await tester.pump();
      await gesture.up();
      await tester.pumpAndSettle();

      await tapCheck(tester);
      expect(harness.submissions, [(true, 'a b')]);
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

    testWidgets('accepts ASCII iyi for dotted-İ expected İyi', (tester) async {
      final renderer = TranslateSentenceRenderer();
      const interaction = Interaction.translateSentence(
        id: 'ts-tr',
        source: 'good',
        expected: 'İyi',
      );

      await tester.pumpWidget(harness.build(renderer, interaction));
      await enterText(tester, 'iyi');
      await tapCheck(tester);

      expect(harness.submissions, [(true, 'iyi')]);
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

    testWidgets('typing enables CHECK via ValueListenableBuilder',
        (tester) async {
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

    testWidgets('accepts ASCII iyi for dotted-İ expected İyi', (tester) async {
      final renderer = TypeTheWordRenderer();
      const interaction = Interaction.typeTheWord(
        id: 'ttw-tr',
        audioAsset: 'w-test-audio',
        prompt: 'Type what you hear',
        expected: 'İyi',
      );

      await tester.pumpWidget(harness.build(renderer, interaction));
      await enterText(tester, 'iyi');
      await tapCheck(tester);

      expect(harness.submissions, [(true, 'iyi')]);
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

    testWidgets('typing enables CHECK via ValueListenableBuilder',
        (tester) async {
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

    testWidgets('rapid double tap submits once', (tester) async {
      final renderer = ShowWordRenderer(FakeAudioController());
      const interaction = Interaction.showWord(
        id: 'sw-debounce',
        wordId: 'w-test-show',
      );

      await tester.pumpWidget(harness.build(renderer, interaction));
      await tester.tap(find.text('点击继续'));
      await tester.tap(find.text('点击继续'));
      await tester.pump();

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
      expect(audio.lastSpoken, 'w-test-show');
      expect(harness.submissions, isEmpty);

      // Tapping the context sentence speaks only the target-language part.
      await tester.tap(find.text('Habari asubuhi. — Good morning.'));
      await tester.pumpAndSettle();
      expect(audio.lastSpoken, 'Habari asubuhi.');
      expect(harness.submissions, isEmpty);
    });

    testWidgets('renders long terms on narrow screens without overflow',
        (tester) async {
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

    testWidgets('canonicalLink fail-closes without opening vocab or Legacy',
        (tester) async {
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
      expect(
          find.byKey(const Key('official-canonical-continue')), findsNothing);
      expect(find.text('Habari'), findsNothing);
      expect(find.byType(OfficialAnkiReviewerPage), findsNothing);
    });

    testWidgets('canonicalLink renders inline without a route push',
        (tester) async {
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
      // A failed card must not complete the lesson or introduce unseen cards.
      final button = tester.widget<FilledButton>(
        find.byKey(const Key('official-canonical-continue')),
      );
      expect(button.onPressed, isNull);
      expect(harness.submissions, isEmpty);
    });
  });

  group('ReadAloudRenderer', () {
    // The mic card only exists when the master switch is on (opt-in, ADR
    // 0061); these tests register a real SettingsProvider over mock prefs so
    // the gate helper reads a live value instead of the DI-absent fallback.
    late AppPrefs prefs;
    late SettingsProvider settings;

    setUp(() async {
      await getIt.reset();
      SharedPreferences.setMockInitialValues({});
      final streaming = await StreamingSharedPreferences.instance;
      prefs = AppPrefs(streaming);
      settings = SettingsProvider(prefs);
      getIt.registerSingleton<SettingsProvider>(settings);
    });

    tearDown(getIt.reset);

    testWidgets(
        'gate off degrades to a listen-only card with an in-card '
        'enable offer', (tester) async {
      final renderer = ReadAloudRenderer(FakeReadAloudBackend());
      const interaction = Interaction.readAloud(
        id: 'ra-gate-off',
        targetText: 'Merhaba!',
      );

      await tester.pumpWidget(harness.build(renderer, interaction));

      // Enable offer is visible because the backend itself is capable.
      expect(
        find.widgetWithText(OutlinedButton, '开启跟读练习'),
        findsOneWidget,
      );
      await tapContinue(tester);
      expect(harness.submissions, [(true, 'read-aloud-degraded')]);
    });

    testWidgets('unsupported builds degrade without an enable offer',
        (tester) async {
      final renderer =
          ReadAloudRenderer(FakeReadAloudBackend(supported: false));
      const interaction = Interaction.readAloud(
        id: 'ra-unsupported',
        targetText: 'Merhaba!',
      );

      await tester.pumpWidget(harness.build(renderer, interaction));

      expect(find.widgetWithText(OutlinedButton, '开启跟读练习'), findsNothing);
      expect(find.byIcon(Icons.mic_rounded), findsNothing);
      await tapContinue(tester);
      expect(harness.submissions, [(true, 'read-aloud-degraded')]);
    });

    testWidgets('mic flow: final transcript scores and submits pass',
        (tester) async {
      await settings.setReadAloudExercisesEnabled(true);
      final backend = FakeReadAloudBackend();
      final renderer = ReadAloudRenderer(backend);
      const interaction = Interaction.readAloud(
        id: 'ra-pass',
        targetText: 'Merhaba!',
      );

      await tester.pumpWidget(harness.build(renderer, interaction));
      await tester.tap(find.byIcon(Icons.mic_rounded));
      await tester.pumpAndSettle();

      expect(backend.startLocales, ['tr']);
      backend.emitPartial('mer');
      await tester.pump();
      backend.emitFinal('merhaba');
      await tester.pumpAndSettle();

      expect(harness.submissions, [(true, 'merhaba')]);
      // Word-level feedback replaces the plain sentence.
      expect(
        find.byKey(const ValueKey('read-aloud-words')),
        findsOneWidget,
      );
    });

    testWidgets(
        'active readAloud card displays speaker button to model pronunciation',
        (tester) async {
      await settings.setReadAloudExercisesEnabled(true);
      final backend = FakeReadAloudBackend();
      final renderer = ReadAloudRenderer(backend);
      const interaction = Interaction.readAloud(
        id: 'ra-speaker',
        targetText: 'Merhaba!',
      );

      await tester.pumpWidget(harness.build(renderer, interaction));
      expect(find.byType(SpeakerButton), findsOneWidget);
      await tester.tap(find.byType(SpeakerButton));
      await tester.pumpAndSettle();
    });

    testWidgets('a weak transcript fails without blocking progression',
        (tester) async {
      await settings.setReadAloudExercisesEnabled(true);
      final backend = FakeReadAloudBackend();
      final renderer = ReadAloudRenderer(backend);
      const interaction = Interaction.readAloud(
        id: 'ra-fail',
        targetText: 'bir çay lütfen',
      );

      await tester.pumpWidget(harness.build(renderer, interaction));
      await tester.tap(find.byIcon(Icons.mic_rounded));
      await tester.pumpAndSettle();
      backend.emitFinal('bir');
      await tester.pumpAndSettle();

      // 1/3 words < 0.6 threshold: binary fail, transcript recorded.
      expect(harness.submissions, [(false, 'bir')]);
    });

    testWidgets('an empty final transcript is a retry, not a submission',
        (tester) async {
      await settings.setReadAloudExercisesEnabled(true);
      final backend = FakeReadAloudBackend();
      final renderer = ReadAloudRenderer(backend);
      const interaction = Interaction.readAloud(
        id: 'ra-empty',
        targetText: 'Merhaba!',
      );

      await tester.pumpWidget(harness.build(renderer, interaction));
      await tester.tap(find.byIcon(Icons.mic_rounded));
      await tester.pumpAndSettle();
      backend.emitFinal('  ');
      await tester.pumpAndSettle();

      expect(harness.submissions, isEmpty);
      expect(find.text('没听清，再点麦克风试一次'), findsOneWidget);
    });

    testWidgets('permission refusal degrades the card for this item',
        (tester) async {
      await settings.setReadAloudExercisesEnabled(true);
      final backend = FakeReadAloudBackend(ready: false);
      final renderer = ReadAloudRenderer(backend);
      const interaction = Interaction.readAloud(
        id: 'ra-perm',
        targetText: 'Merhaba!',
      );

      await tester.pumpWidget(harness.build(renderer, interaction));
      await tester.tap(find.byIcon(Icons.mic_rounded));
      await tester.pumpAndSettle();

      expect(find.byIcon(Icons.mic_rounded), findsNothing);
      expect(find.text('麦克风权限被拒绝——请在系统设置中允许后重试'), findsOneWidget);
    });

    testWidgets('missing recognition service degrades with service guidance',
        (tester) async {
      await settings.setReadAloudExercisesEnabled(true);
      final backend = FakeReadAloudBackend(
        ready: false,
        readyFailure: ReadAloudFailure.serviceUnavailable,
      );
      final renderer = ReadAloudRenderer(backend);
      const interaction = Interaction.readAloud(
        id: 'ra-service',
        targetText: 'Merhaba!',
      );

      await tester.pumpWidget(harness.build(renderer, interaction));
      await tester.tap(find.byIcon(Icons.mic_rounded));
      await tester.pumpAndSettle();

      expect(find.byIcon(Icons.mic_rounded), findsNothing);
      expect(
        find.text('系统没有可用的语音识别服务，请安装或启用后重试'),
        findsOneWidget,
      );
    });

    testWidgets('network failure stays retryable and explains the real cause',
        (tester) async {
      await settings.setReadAloudExercisesEnabled(true);
      final backend = FakeReadAloudBackend();
      final renderer = ReadAloudRenderer(backend);
      const interaction = Interaction.readAloud(
        id: 'ra-network',
        targetText: 'Merhaba!',
      );

      await tester.pumpWidget(harness.build(renderer, interaction));
      await tester.tap(find.byIcon(Icons.mic_rounded));
      await tester.pumpAndSettle();
      backend.emitError(ReadAloudFailure.networkUnavailable);
      await tester.pumpAndSettle();

      expect(harness.submissions, isEmpty);
      expect(find.byIcon(Icons.mic_rounded), findsOneWidget);
      expect(
        find.text('识别服务连接失败，请检查网络或下载该语言的离线识别资源后重试'),
        findsOneWidget,
      );
    });
  });
}
