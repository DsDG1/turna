// Unit tests for the user-facing question-type layer: the six plain chips
// must round-trip the internal mapping types, and 填空题 must disambiguate
// cloze vs type-the-answer from the notetype's own markers.

// Package imports:
import 'package:flutter_test/flutter_test.dart';

// Project imports:
import 'package:turna/application/anki/anki_card_adapter.dart';
import 'package:turna/application/anki/anki_models.dart';
import 'package:turna/application/anki/import_wizard/question_type.dart';

AnkiNotetype _notetype({bool isCloze = false}) => AnkiNotetype(
      id: 1,
      name: 'Basic',
      fieldNames: const ['Front', 'Back'],
      isCloze: isCloze,
    );

AnkiNote _note(List<String> fields, {int mid = 1}) => AnkiNote(
      id: mid * 1000,
      mid: mid,
      fields: fields,
    );

void main() {
  group('userQuestionTypeOf', () {
    test('maps canonical types to their chips', () {
      expect(userQuestionTypeOf(NotetypeMappingType.multipleChoice),
          UserQuestionType.choice);
      expect(userQuestionTypeOf(NotetypeMappingType.cloze),
          UserQuestionType.fillBlank);
      expect(userQuestionTypeOf(NotetypeMappingType.fillBlank),
          UserQuestionType.fillBlank);
      expect(userQuestionTypeOf(NotetypeMappingType.listenPick),
          UserQuestionType.listen);
      expect(userQuestionTypeOf(NotetypeMappingType.wordEntry),
          UserQuestionType.word);
      expect(userQuestionTypeOf(NotetypeMappingType.expression),
          UserQuestionType.sentence);
      expect(
          userQuestionTypeOf(NotetypeMappingType.ankiCard), UserQuestionType.flip);
    });

    test('collapses legacy aliases', () {
      expect(userQuestionTypeOf(NotetypeMappingType.multiSelect),
          UserQuestionType.choice);
      expect(userQuestionTypeOf(NotetypeMappingType.typeAnswer),
          UserQuestionType.fillBlank);
    });
  });

  group('resolveMappingType', () {
    test('direct types need no evidence', () {
      expect(
          resolveMappingType(
              UserQuestionType.choice, hasClozeMarkers: false),
          NotetypeMappingType.multipleChoice);
      expect(
          resolveMappingType(UserQuestionType.listen, hasClozeMarkers: false),
          NotetypeMappingType.listenPick);
      expect(resolveMappingType(UserQuestionType.word, hasClozeMarkers: false),
          NotetypeMappingType.wordEntry);
      expect(
          resolveMappingType(UserQuestionType.sentence,
              hasClozeMarkers: false),
          NotetypeMappingType.expression);
      expect(resolveMappingType(UserQuestionType.flip, hasClozeMarkers: false),
          NotetypeMappingType.ankiCard);
    });

    test('填空题 disambiguates by cloze markers', () {
      expect(
          resolveMappingType(UserQuestionType.fillBlank,
              hasClozeMarkers: true),
          NotetypeMappingType.cloze);
      expect(
          resolveMappingType(UserQuestionType.fillBlank,
              hasClozeMarkers: false),
          NotetypeMappingType.fillBlank);
    });

    test('round-trips every chip except 填空题 without markers', () {
      for (final type in UserQuestionType.values) {
        final resolved =
            resolveMappingType(type, hasClozeMarkers: type == UserQuestionType.fillBlank);
        expect(userQuestionTypeOf(resolved), type);
      }
    });
  });

  group('hasClozeMarkers', () {
    test('cloze notetype flag is enough', () {
      expect(
        hasClozeMarkers(
          _notetype(isCloze: true),
          const [],
        ),
        isTrue,
      );
    });

    test('detects {{c1:: in sampled fields', () {
      expect(
        hasClozeMarkers(_notetype(), [
          _note(const ['The {{c1::sun}} rises', 'answer']),
        ]),
        isTrue,
      );
    });

    test('ignores notes of other notetypes', () {
      expect(
        hasClozeMarkers(_notetype(), [
          _note(const ['{{c1::x}}'], mid: 2),
          _note(const ['plain', 'plain']),
        ]),
        isFalse,
      );
    });

    test('plain notes report false', () {
      expect(
        hasClozeMarkers(_notetype(), [
          _note(const ['merhaba', '你好']),
        ]),
        isFalse,
      );
    });
  });
}
