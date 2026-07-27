// Package imports:
import 'package:flutter_test/flutter_test.dart';

// Project imports:
import 'package:varnamala/application/anki/anki_card_adapter.dart';
import 'package:varnamala/application/anki/anki_models.dart';
import 'package:varnamala/domain/course/interaction.dart';

void main() {
  group('AnkiCardAdapter', () {
    late AnkiCardAdapter adapter;

    setUp(() {
      adapter = AnkiCardAdapter();
    });

    group('inferMapping', () {
      test('detects Cloze notetype', () {
        final notetype = AnkiNotetype(
          id: 1,
          name: 'Cloze',
          fieldNames: ['Text', 'Back Extra'],
          templateNames: ['Cloze'],
          isCloze: true,
        );

        final mapping = AnkiCardAdapter.inferMapping(notetype);
        expect(mapping.type, NotetypeMappingType.cloze);
      });

      test('detects Term/Translation pattern', () {
        final notetype = AnkiNotetype(
          id: 2,
          name: 'Basic',
          fieldNames: ['Term', 'Translation'],
          templateNames: ['Card 1'],
        );

        final mapping = AnkiCardAdapter.inferMapping(notetype);
        expect(mapping.type, NotetypeMappingType.wordEntry);
        expect(mapping.frontFieldIndex, 0);
        expect(mapping.backFieldIndex, 1);
      });

      test('detects Front/Back pattern as ankiCard', () {
        final notetype = AnkiNotetype(
          id: 3,
          name: 'Basic',
          fieldNames: ['Front', 'Back'],
          templateNames: ['Card 1'],
        );

        final mapping = AnkiCardAdapter.inferMapping(notetype);
        // Front/Back with term-like names → wordEntry
        expect(mapping.type, NotetypeMappingType.wordEntry);
      });

      test('detects Expression/Sentence pattern', () {
        final notetype = AnkiNotetype(
          id: 4,
          name: 'Sentence',
          fieldNames: ['Expression', 'Meaning', 'Reading'],
          templateNames: ['Card 1'],
        );

        final mapping = AnkiCardAdapter.inferMapping(notetype);
        expect(mapping.type, NotetypeMappingType.expression);
      });

      test('defaults to ankiCard for unknown fields', () {
        final notetype = AnkiNotetype(
          id: 5,
          name: 'Custom',
          fieldNames: ['Field1', 'Field2', 'Field3'],
          templateNames: ['Card 1'],
        );

        final mapping = AnkiCardAdapter.inferMapping(notetype);
        expect(mapping.type, NotetypeMappingType.ankiCard);
      });

      test('detects Chinese field names', () {
        final notetype = AnkiNotetype(
          id: 6,
          name: '单词',
          fieldNames: ['单词', '释义'],
          templateNames: ['Card 1'],
        );

        final mapping = AnkiCardAdapter.inferMapping(notetype);
        expect(mapping.type, NotetypeMappingType.wordEntry);
      });
    });

    group('adapt', () {
      test('adapts to AnkiCard for generic mapping', () {
        final note = AnkiNote(
          id: 12345,
          mid: 1,
          fields: ['What is Dart?', 'A programming language'],
        );
        final card = AnkiCardData(id: 1, nid: 12345, did: 1);

        final result = adapter.adapt(
          note,
          card,
          importId: 'test',
          mapping: const NotetypeMapping(
            type: NotetypeMappingType.ankiCard,
            frontFieldIndex: 0,
            backFieldIndex: 1,
          ),
        );

        expect(result.interaction, isA<AnkiCard>());
        final ankiCard = result.interaction as AnkiCard;
        expect(ankiCard.front, 'What is Dart?');
        expect(ankiCard.back, 'A programming language');
        expect(result.wordId, 'anki-test-n12345');
        expect(result.wordEntry, isNull);
      });

      test('adapts to MultipleChoice for wordEntry mapping', () {
        final note = AnkiNote(
          id: 99,
          mid: 2,
          fields: ['merhaba', 'hello'],
        );
        final card = AnkiCardData(id: 2, nid: 99, did: 1);

        final result = adapter.adapt(
          note,
          card,
          importId: 'abc',
          mapping: const NotetypeMapping(
            type: NotetypeMappingType.wordEntry,
            frontFieldIndex: 0,
            backFieldIndex: 1,
          ),
          distractors: ['goodbye', 'thanks', 'please'],
        );

        expect(result.interaction, isA<MultipleChoice>());
        final mcq = result.interaction as MultipleChoice;
        expect(mcq.prompt, 'merhaba');
        expect(mcq.options, contains('hello'));
        expect(mcq.options.length, 4);
        expect(result.wordEntry, isNotNull);
        expect(result.wordEntry!.term, 'merhaba');
        expect(result.wordEntry!.translation, 'hello');
      });

      test('extracts image and sound references as anki:// assets', () {
        final note = AnkiNote(
          id: 777,
          mid: 1,
          fields: [
            'Front <img src="pic.png">[sound:say.mp3]',
            'Back <img src="back.jpg">',
          ],
        );
        final card = AnkiCardData(id: 5, nid: 777, did: 1);

        final result = adapter.adapt(
          note,
          card,
          importId: 'imp1',
          mapping: const NotetypeMapping(
            type: NotetypeMappingType.ankiCard,
            frontFieldIndex: 0,
            backFieldIndex: 1,
          ),
        );

        final ankiCard = result.interaction as AnkiCard;
        expect(ankiCard.imageAssets,
            ['anki://imp1/pic.png', 'anki://imp1/back.jpg']);
        expect(ankiCard.audioAssets, ['anki://imp1/say.mp3']);
        // Media markup must not leak into the rendered text.
        expect(ankiCard.front, 'Front');
        expect(ankiCard.back, 'Back');
      });

      test('wordEntry mapping picks up front-field audio', () {
        final note = AnkiNote(
          id: 778,
          mid: 2,
          fields: ['merhaba[sound:merhaba.mp3]', 'hello'],
        );
        final card = AnkiCardData(id: 6, nid: 778, did: 1);

        final result = adapter.adapt(
          note,
          card,
          importId: 'imp2',
          mapping: const NotetypeMapping(
            type: NotetypeMappingType.wordEntry,
            frontFieldIndex: 0,
            backFieldIndex: 1,
          ),
          distractors: const ['a', 'b', 'c'],
        );

        expect(result.wordEntry!.audioAsset, 'anki://imp2/merhaba.mp3');
        expect(result.wordEntry!.term, 'merhaba');
      });

      test('adapts Cloze to FillBlank', () {
        final note = AnkiNote(
          id: 200,
          mid: 3,
          fields: ['The {{c1::cat}} sat on the mat'],
        );
        final card = AnkiCardData(id: 3, nid: 200, did: 1, ord: 0);

        final result = adapter.adapt(
          note,
          card,
          importId: 'xyz',
          mapping: const NotetypeMapping(
            type: NotetypeMappingType.cloze,
            frontFieldIndex: 0,
            backFieldIndex: 0,
          ),
        );

        expect(result.interaction, isA<FillBlank>());
        final fb = result.interaction as FillBlank;
        expect(fb.answer, 'cat');
        expect(fb.sentence, contains('_____'));
      });

      test('strips HTML from fields', () {
        final note = AnkiNote(
          id: 300,
          mid: 1,
          fields: ['<b>Bold</b> text<br>line2', '<i>Answer</i>'],
        );
        final card = AnkiCardData(id: 4, nid: 300, did: 1);

        final result = adapter.adapt(
          note,
          card,
          importId: 'html',
          mapping: const NotetypeMapping(
            type: NotetypeMappingType.ankiCard,
            frontFieldIndex: 0,
            backFieldIndex: 1,
          ),
        );

        final ankiCard = result.interaction as AnkiCard;
        expect(ankiCard.front, 'Bold text\nline2');
        expect(ankiCard.back, 'Answer');
      });
    });

    group('stripHtmlPublic', () {
      test('strips basic HTML tags', () {
        expect(
          AnkiCardAdapter.stripHtmlPublic('<b>hello</b>'),
          'hello',
        );
      });

      test('converts br to newline', () {
        expect(
          AnkiCardAdapter.stripHtmlPublic('line1<br>line2'),
          'line1\nline2',
        );
      });

      test('decodes HTML entities', () {
        expect(
          AnkiCardAdapter.stripHtmlPublic('&amp; &lt; &gt;'),
          '& < >',
        );
      });
    });
  });
}
