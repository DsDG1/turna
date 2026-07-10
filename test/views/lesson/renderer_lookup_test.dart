// Wave B: lookupRenderer must match freezed interface types, not _$Impl.

import 'package:flutter_test/flutter_test.dart';
import 'package:varnamala/domain/course/interaction.dart';
import 'package:varnamala/views/lesson/components/interactions/fill_blank_renderer.dart';
import 'package:varnamala/views/lesson/components/interactions/interaction_renderer.dart';
import 'package:varnamala/views/lesson/components/interactions/listen_and_pick_renderer.dart';
import 'package:varnamala/views/lesson/components/interactions/listen_only_renderer.dart';
import 'package:varnamala/views/lesson/components/interactions/multiple_choice_renderer.dart';
import 'package:varnamala/views/lesson/components/interactions/reading_mcq_renderer.dart';
import 'package:varnamala/views/lesson/components/interactions/reading_short_answer_renderer.dart';
import 'package:varnamala/views/lesson/components/interactions/reading_true_false_renderer.dart';
import 'package:varnamala/views/lesson/components/interactions/reorder_sentence_renderer.dart';
import 'package:varnamala/views/lesson/components/interactions/show_word_renderer.dart';
import 'package:varnamala/views/lesson/components/interactions/translate_sentence_renderer.dart';
import 'package:varnamala/views/lesson/components/interactions/type_the_word_renderer.dart';

import 'renderers/fake_audio_controller.dart';

void main() {
  final renderers = <InteractionRenderer>{
    ShowWordRenderer(FakeAudioController()),
    MultipleChoiceRenderer(),
    FillBlankRenderer(),
    TranslateSentenceRenderer(),
    ListenAndPickRenderer(),
    TypeTheWordRenderer(),
    ListenOnlyRenderer(),
    ReorderSentenceRenderer(),
    ReadingMcqRenderer(),
    ReadingTrueFalseRenderer(),
    ReadingShortAnswerRenderer(),
  };

  final samples = <Interaction>[
    const Interaction.showWord(id: 'a', wordId: 'w'),
    const Interaction.multipleChoice(
      id: 'b',
      prompt: 'p',
      options: ['x', 'y'],
      correctIndex: 0,
    ),
    const Interaction.fillBlank(id: 'c', sentence: '_', answer: 'a'),
    const Interaction.translateSentence(
      id: 'd',
      source: 's',
      expected: 'e',
    ),
    const Interaction.listenAndPick(
      id: 'e',
      audioAsset: 'w',
      prompt: 'p',
      options: ['a'],
      correctIndex: 0,
    ),
    const Interaction.typeTheWord(
      id: 'f',
      audioAsset: 'w',
      prompt: 'p',
      expected: 'e',
    ),
    const Interaction.listenOnly(id: 'g', transcript: 'hi'),
    const Interaction.reorderSentence(
      id: 'h',
      scrambled: ['b', 'a'],
      correct: ['a', 'b'],
    ),
    const Interaction.readingMcq(
      id: 'i',
      prompt: 'p',
      options: ['a'],
      correctIndex: 0,
    ),
    const Interaction.readingTrueFalse(
      id: 'j',
      statement: 's',
      answer: true,
    ),
    const Interaction.readingShortAnswer(
      id: 'k',
      prompt: 'p',
      expectedAnswer: 'a',
    ),
  ];

  test('every Interaction variant resolves a renderer', () {
    for (final interaction in samples) {
      final renderer = lookupRenderer(renderers, interaction);
      expect(renderer.handlesType, isNotNull);
      // Must not throw; runtimeType is the private impl.
      expect(interaction.runtimeType.toString(), contains(r'_$'));
    }
  });

  test('interactionCorrectAnswerLabel covers all variants', () {
    for (final interaction in samples) {
      // ListenOnly has no correctness verdict (listen-and-continue), so
      // its label is intentionally null. Every other variant must produce
      // a usable label so the mistake log has something to display.
      final isListenOnly = interaction.runtimeType.toString() ==
          const Interaction.listenOnly().runtimeType.toString();
      if (isListenOnly) {
        expect(interactionCorrectAnswerLabel(interaction), isNull);
        continue;
      }
      expect(interactionCorrectAnswerLabel(interaction), isNotNull);
    }
  });
}
