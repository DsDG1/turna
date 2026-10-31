// Domain tests for Interaction: AI-hint eligibility, answer labels, grammar point extraction, and json fallback.

import 'package:flutter_test/flutter_test.dart';
import 'package:turna/domain/course/interaction.dart';

void main() {
  group('Interaction.fromJson unknown-type fallback', () {
    test('degrades unknown runtimeType to ShowWord with diagnostic wordId', () {
      final interaction = Interaction.fromJson(const {
        'runtimeType': 'futureUnknownType',
        'prompt': 'ignored',
      });
      expect(interaction, isA<ShowWord>());
      final wordId = (interaction as ShowWord).wordId;
      expect(wordId.startsWith(unknownInteractionWordIdPrefix), isTrue);
      expect(wordId, '$unknownInteractionWordIdPrefix${'futureUnknownType'}');
    });

    test('degrades missing runtimeType to ShowWord', () {
      final interaction = Interaction.fromJson(const <String, dynamic>{
        'prompt': 'no type here',
      });
      expect(interaction, isA<ShowWord>());
      expect(
        (interaction as ShowWord).wordId,
        '$unknownInteractionWordIdPrefix${'unknown'}',
      );
    });

    test('known types still parse unchanged', () {
      final interaction = Interaction.fromJson(const {
        'runtimeType': 'multipleChoice',
        'prompt': 'Pick one',
        'options': <String>['a', 'b'],
        'correctIndex': 0,
      });
      expect(interaction, isA<MultipleChoice>());
      final mc = interaction as MultipleChoice;
      expect(mc.prompt, 'Pick one');
      expect(mc.options, ['a', 'b']);
      expect(mc.correctIndex, 0);
    });

    test('readAloud parses with its wire discriminator', () {
      final interaction = Interaction.fromJson(const {
        'runtimeType': 'readAloud',
        'id': 'ra-1',
        'targetText': 'Merhaba!',
        'prompt': '读出这句话',
      });
      expect(interaction, isA<ReadAloud>());
      final ra = interaction as ReadAloud;
      expect(ra.targetText, 'Merhaba!');
      expect(ra.prompt, '读出这句话');
      expect(ra.grammarPointId, isNull);
    });

    test('readAloud missing targetText degrades to the sentinel', () {
      // A readAloud without its required field is a malformed item: the
      // fallback ShowWord must swallow it so the lesson still loads, with
      // the sentinel wordId the validator reports.
      final interaction = Interaction.fromJson(const {
        'runtimeType': 'readAloud',
        'id': 'ra-broken',
      });
      expect(interaction, isA<ShowWord>());
      expect(
        (interaction as ShowWord).wordId,
        '$unknownInteractionWordIdPrefix${'readAloud'}',
      );
    });
  });

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

    test('ReadAloud is NOT eligible (task is speaking, not comprehension)', () {
      expect(
        interactionAiHintEligible(
          const Interaction.readAloud(targetText: 'Merhaba!'),
        ),
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

  group('interactionCorrectAnswerLabel', () {
    test('ListenOnly returns null regardless of transcript / audioAsset', () {
      expect(
        interactionCorrectAnswerLabel(
          const Interaction.listenOnly(
            id: 'lo1',
            transcript: '',
            audioAsset: 'assets/audio/some/audio.mp3',
          ),
        ),
        isNull,
      );
      expect(
        interactionCorrectAnswerLabel(
          const Interaction.listenOnly(
            id: 'lo2',
            transcript: 'spoken words',
            audioAsset: 'assets/audio/some/audio.mp3',
          ),
        ),
        isNull,
        reason: 'ListenOnly is listen-and-continue; no correct answer.',
      );
    });
  });

  group('interactionGrammarPointId', () {
    test('reads optional field on all variants used', () {
      const mc = Interaction.multipleChoice(
        id: 'a',
        prompt: 'p',
        options: ['x', 'y'],
        correctIndex: 0,
        grammarPointId: 'gp.a',
      );
      const fb = Interaction.fillBlank(
        id: 'b',
        sentence: '___',
        answer: 'x',
        grammarPointId: 'gp.b',
      );
      const bare = Interaction.multipleChoice(
        id: 'c',
        prompt: 'p',
        options: ['x'],
        correctIndex: 0,
      );

      expect(interactionGrammarPointId(mc), 'gp.a');
      expect(interactionGrammarPointId(fb), 'gp.b');
      expect(interactionGrammarPointId(bare), isNull);
    });
  });
}
