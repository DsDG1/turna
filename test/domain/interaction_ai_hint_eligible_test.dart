// Regression: [interactionAiHintEligible] previously returned true for
// [ShowWord], but a ShowWord card already displays its word/expression —
// there is nothing for the in-lesson AI hint assistant to "explain". The
// AI button should not appear on ShowWord. Audio-only types (ListenAndPick,
// TypeTheWord, ListenOnly) also opt out (no text prompt).

import 'package:flutter_test/flutter_test.dart';
import 'package:turna/domain/course/interaction.dart';

void main() {
  group('interactionAiHintEligible', () {
    test('ShowWord is NOT eligible (already displayed)', () {
      expect(
        interactionAiHintEligible(const Interaction.showWord(wordId: 'w-1')),
        isFalse,
      );
    });

    test('audio-only types are NOT eligible', () {
      expect(
        interactionAiHintEligible(const Interaction.listenAndPick(
          audioAsset: 'a.mp3',
          prompt: 'p',
          options: ['a', 'b'],
          correctIndex: 0,
        )),
        isFalse,
      );
      expect(
        interactionAiHintEligible(const Interaction.typeTheWord(
          audioAsset: 'a.mp3',
          prompt: 'p',
          expected: 'evet',
        )),
        isFalse,
      );
      expect(
        interactionAiHintEligible(const Interaction.listenOnly(transcript: '')),
        isFalse,
      );
    });

    test('text-prompt types ARE eligible', () {
      expect(
        interactionAiHintEligible(const Interaction.multipleChoice(
          prompt: 'p',
          options: ['a', 'b'],
          correctIndex: 0,
        )),
        isTrue,
      );
      expect(
        interactionAiHintEligible(const Interaction.multiSelect(
          prompt: 'p',
          options: ['a', 'b', 'c'],
          correctIndices: [0, 2],
        )),
        isTrue,
      );
      expect(
        interactionAiHintEligible(const Interaction.fillBlank(
          sentence: 'Merhaba ___',
          answer: 'dünya',
        )),
        isTrue,
      );
      expect(
        interactionAiHintEligible(const Interaction.translateSentence(
          source: 'hello',
          expected: 'merhaba',
        )),
        isTrue,
      );
      expect(
        interactionAiHintEligible(const Interaction.reorderSentence(
          scrambled: ['b', 'a'],
          correct: ['a', 'b'],
        )),
        isTrue,
      );
      expect(
        interactionAiHintEligible(const Interaction.readingMcq(
          prompt: 'p',
          options: ['a', 'b'],
          correctIndex: 0,
        )),
        isTrue,
      );
      expect(
        interactionAiHintEligible(const Interaction.readingTrueFalse(
          statement: 's',
          answer: true,
        )),
        isTrue,
      );
      expect(
        interactionAiHintEligible(const Interaction.readingShortAnswer(
          prompt: 'p',
          expectedAnswer: 'yes',
        )),
        isTrue,
      );
    });
  });
}
