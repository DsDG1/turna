import 'package:flutter_test/flutter_test.dart';
import 'package:turna/application/anki_import/recognition/facts/card_facts.dart';
import 'package:turna/application/anki_import/recognition/facts/notetype_facts.dart';
import 'package:turna/application/anki_import/recognition/facts/text_metrics.dart';
import 'package:turna/application/anki_import/recognition/lexicon/field_roles.dart';
import 'package:turna/application/anki_import/recognition/recognize/binding.dart';
import 'package:turna/application/anki_official/contract/official_anki_dto.dart';

void main() {
  group('field name normalization and lexicon', () {
    test('strips separators and lowercases', () {
      expect(normalizeFieldName('Vocab-Kanji'), 'vocabkanji');
      expect(normalizeFieldName(' Back_Extra '), 'backextra');
    });

    test('exact hits resolve structural synonyms in en and zh', () {
      expect(exactRoleFor('Front'), FieldRole.prompt);
      expect(exactRoleFor('正面'), FieldRole.prompt);
      expect(exactRoleFor('BACK'), FieldRole.response);
      expect(exactRoleFor('答案'), FieldRole.response);
      expect(exactRoleFor('Audio'), FieldRole.audio);
      expect(exactRoleFor('遮图'), FieldRole.image);
      // Direction-ambiguous tokens stay out of the exact lists.
      expect(exactRoleFor('Word'), isNull);
      expect(exactRoleFor('单词'), isNull);
    });

    test('contains hits respect role priority on ties', () {
      final backExtra = containsRolesFor('Back Extra');
      expect(backExtra, isNotEmpty);
      expect(backExtra.first, FieldRole.response);
      expect(containsRolesFor('vocabkanji'), isEmpty);
    });
  });

  group('text metrics', () {
    test('shortText collapses tags and sound markers', () {
      expect(CardText.shortText('<b>Hi</b> [sound:a.mp3]'), 'Hi');
      expect(CardText.shortText('  a\n  b  '), 'a b');
    });

    test('isShortAnswer and isSentence', () {
      expect(CardText.isShortAnswer('cat'), isTrue);
      expect(CardText.isShortAnswer('x' * 61), isFalse);
      expect(CardText.isShortAnswer('line\nbreak'), isFalse);
      expect(CardText.isSentence('这是一个句子。'), isTrue);
      expect(CardText.isSentence('cat'), isFalse);
    });

    test('media extraction prefers audio then image', () {
      expect(CardText.extractMediaFilename('[sound:a.mp3]'), 'a.mp3');
      expect(CardText.extractMediaFilename('<img src="pic.png">'), 'pic.png');
      expect(CardText.extractMediaFilename('[anki:play:audio:a.mp3]'), 'a.mp3');
      expect(CardText.extractMediaFilename('../evil.mp3'), isNull);
    });
  });

  group('card facts rates', () {
    test('rates only count non-empty values', () {
      final facts = CardFacts.of(['', 'a', 'b']);
      expect(facts.nonEmptyCount, 2);
      expect(facts.rateOf((v) => v.startsWith('a')), 0.5);
      expect(facts.clozeMarkerRate, 0);
    });

    test('cloze marker and option detection', () {
      expect(CardFacts.of(['{{c1::x}}']).anyContainsClozeMarker, isTrue);
      expect(CardFacts.of(['Q?\nA. x\nB. y']).looksLikeOptionsRate, 1.0);
      expect(CardFacts.of(['plain']).looksLikeOptionsRate, 0.0);
    });
  });

  group('role binding solver', () {
    test('greedy resolves cross claims without double assignment', () {
      final facts = NotetypeFacts.fromSchema(_schema(
        fieldNames: const ['Audio', 'Notes', 'Definition'],
        samples: const [
          ['[sound:a.mp3]', 'note text', 'a meaning'],
          ['[sound:b.mp3]', 'other note', 'another meaning'],
        ],
      ));
      final result = const RoleBindingSolver().bind(facts);
      expect(result[FieldRole.audio]?.fieldName, 'Audio');
      // Definition wins response through the lexicon; Notes has no
      // positive claim and becomes the positional prompt fallback.
      expect(result[FieldRole.response]?.fieldName, 'Definition');
      expect(result[FieldRole.prompt]?.fieldName, 'Notes');
      // One field never holds two roles.
      final indices = [
        for (final binding in result.values) binding.fieldIndex,
      ];
      expect(indices.toSet().length, indices.length);
    });

    test('cloze notetypes skip the response fallback', () {
      final facts = NotetypeFacts.fromSchema(_schema(
        fieldNames: const ['Text', 'Extra'],
        kind: 'cloze',
        samples: const [
          ['The {{c1::sun}}', ''],
        ],
      ));
      final result = const RoleBindingSolver().bind(facts);
      expect(result.containsKey(FieldRole.response), isFalse);
      expect(result[FieldRole.prompt]?.fieldName, 'Text');
    });
  });
}

OfficialAnkiProjectionSchema _schema({
  required List<String> fieldNames,
  required List<List<String>> samples,
  String kind = 'normal',
}) {
  return OfficialAnkiProjectionSchema(
    notetypeId: 1,
    name: 'Probe',
    kind: kind,
    fieldNames: fieldNames,
    templateNames: const ['Card 1'],
    schemaFingerprint: 'fp',
    samples: [
      for (var i = 0; i < samples.length; i++)
        OfficialAnkiProjectionSample(noteId: i + 1, fields: samples[i]),
    ],
  );
}
