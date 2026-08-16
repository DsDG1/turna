// Consolidated domain model tests for PosTag, LessonWordLink, and MistakeEntry.

import 'package:flutter_test/flutter_test.dart';
import 'package:turna/domain/course/interaction.dart';
import 'package:turna/domain/course/lesson_word_link.dart';
import 'package:turna/domain/course/mistake_entry.dart';
import 'package:turna/domain/course/pos_tag.dart';

void main() {
  group('PosTag.parse & labels', () {
    test('parses all 10 closed-set tags (case/whitespace tolerant)', () {
      for (final tag in PosTag.values) {
        expect(PosTag.parse(tag.name), tag);
        expect(PosTag.parse(' ${tag.name.toUpperCase()} '), tag);
      }
      expect(PosTag.values.length, 10);
    });

    test('null / empty / unknown -> null (never throws)', () {
      expect(PosTag.parse(null), isNull);
      expect(PosTag.parse(''), isNull);
      expect(PosTag.parse('   '), isNull);
      expect(PosTag.parse('bogus'), isNull);
    });

    test('posTagLabel maps to Chinese label or name', () {
      expect(posTagLabel(PosTag.noun), '名词');
      expect(posTagLabel(null), '');
      expect(posTagLabel(PosTag.determiner), '限定词');
    });

    test('closed set mirrors GUI pos_constants.py (10 classes)', () {
      final names = PosTag.values.map((t) => t.name).toSet();
      expect(
        names,
        {
          'noun',
          'verb',
          'adjective',
          'adverb',
          'pronoun',
          'preposition',
          'conjunction',
          'interjection',
          'numeral',
          'determiner',
        },
      );
    });
  });

  group('LessonWordLink', () {
    test('serializes and deserializes', () {
      final link = LessonWordLink(
        wordId: 'w-hello',
        lessonId: 'l-greetings-1',
        lessonName: 'Greetings',
        type: LinkType.word,
        firstSeenAt: DateTime(2026, 7, 9, 10, 30),
      );

      final json = link.toJson();
      final recovered = LessonWordLink.fromJson(json);

      expect(recovered.wordId, 'w-hello');
      expect(recovered.lessonId, 'l-greetings-1');
      expect(recovered.lessonName, 'Greetings');
      expect(recovered.type, LinkType.word);
      expect(recovered.firstSeenAt, link.firstSeenAt);
    });

    test('defaults to LinkType.word', () {
      final link = LessonWordLink(
        wordId: 'w-hello',
        lessonId: 'l-greetings-1',
        lessonName: 'Greetings',
        firstSeenAt: DateTime.utc(2026, 7, 9),
      );
      expect(link.type, LinkType.word);
    });
  });

  group('MistakeEntry grammar links', () {
    test('preserves grammarPointId through JSON', () {
      final entry = MistakeEntry(
        id: 'm1',
        lessonId: 'l-test',
        stageId: 'stage-check',
        interactionId: 'mc-1',
        grammarPointId: 'gp.greetings',
        userAnswer: 'Hapana',
        correctAnswer: 'Ndiyo',
        timestamp: DateTime.utc(2026, 1, 1),
        interactionSnapshot: const Interaction.multipleChoice(
          id: 'mc-1',
          prompt: 'Which means Yes?',
          options: ['Ndiyo', 'Hapana'],
          correctIndex: 0,
          grammarPointId: 'gp.greetings',
        ),
      );

      final decoded = MistakeEntry.fromJson(entry.toJson());
      expect(decoded.grammarPointId, 'gp.greetings');
      expect(
        interactionGrammarPointId(decoded.interactionSnapshot!),
        'gp.greetings',
      );
    });
  });
}
