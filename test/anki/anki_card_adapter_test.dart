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
      test('adapts to AnkiCard for generic mapping with long answer', () {
        final note = AnkiNote(
          id: 12345,
          mid: 1,
          fields: [
            'What is Dart?',
            'A programming language optimized for building multi-platform '
                'applications with a focus on user interfaces',
          ],
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
        expect(ankiCard.back, contains('A programming language'));
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
            'Back <img src="back.jpg"> — a long explanation that cannot be '
                'answered by typing or picking, so the card stays a flip card',
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
        expect(ankiCard.back, startsWith('Back'));
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
          fields: [
            '<b>Bold</b> text<br>line2',
            '<i>A long answer that stays a flip card because typing or '
                'picking it would be impractical for the learner</i>',
          ],
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
        expect(ankiCard.back, startsWith('A long answer'));
      });
    });

    group('auto-decide (ankiCard mapping)', () {
      const mapping = NotetypeMapping(
        type: NotetypeMappingType.ankiCard,
        frontFieldIndex: 0,
        backFieldIndex: 1,
      );

      test('short answer + enough distractors → MultipleChoice', () {
        final note = AnkiNote(id: 1, mid: 1, fields: ['capital of France?', 'Paris']);
        final card = AnkiCardData(id: 1, nid: 1, did: 1);

        final result = adapter.adapt(
          note,
          card,
          importId: 't',
          mapping: mapping,
          distractors: const ['London', 'Berlin', 'Madrid', 'Paris'],
        );

        expect(result.interaction, isA<MultipleChoice>());
        final mcq = result.interaction as MultipleChoice;
        expect(mcq.prompt, 'capital of France?');
        expect(mcq.options.length, 4);
        expect(mcq.options[mcq.correctIndex], 'Paris');
        expect(mcq.options, isNot(contains('—')));
      });

      test('short answer + few distractors → type-the-answer FillBlank', () {
        final note = AnkiNote(id: 2, mid: 1, fields: ['capital of France?', 'Paris']);
        final card = AnkiCardData(id: 2, nid: 2, did: 1);

        final result = adapter.adapt(
          note,
          card,
          importId: 't',
          mapping: mapping,
          distractors: const ['London'],
        );

        expect(result.interaction, isA<FillBlank>());
        final fb = result.interaction as FillBlank;
        expect(fb.sentence, contains('_____'));
        expect(fb.answer, 'Paris');
      });

      test('front audio + short answer + distractors → ListenAndPick', () {
        final note = AnkiNote(
          id: 3,
          mid: 1,
          fields: ['[sound:word.mp3]', 'apple'],
        );
        final card = AnkiCardData(id: 3, nid: 3, did: 1);

        final result = adapter.adapt(
          note,
          card,
          importId: 'imp',
          mapping: mapping,
          distractors: const ['pear', 'plum', 'fig'],
        );

        expect(result.interaction, isA<ListenAndPick>());
        final lap = result.interaction as ListenAndPick;
        expect(lap.audioAsset, 'anki://imp/word.mp3');
        expect(lap.options[lap.correctIndex], 'apple');
      });

      test('front audio + short answer + few distractors → TypeTheWord', () {
        final note = AnkiNote(
          id: 4,
          mid: 1,
          fields: ['[sound:word.mp3]', 'apple'],
        );
        final card = AnkiCardData(id: 4, nid: 4, did: 1);

        final result = adapter.adapt(
          note,
          card,
          importId: 'imp',
          mapping: mapping,
        );

        expect(result.interaction, isA<TypeTheWord>());
        final ttw = result.interaction as TypeTheWord;
        expect(ttw.audioAsset, 'anki://imp/word.mp3');
        expect(ttw.expected, 'apple');
      });

      test('cloze markers in front → FillBlank', () {
        final note = AnkiNote(
          id: 5,
          mid: 1,
          fields: ['The {{c1::cat}} sat on the mat', 'irrelevant'],
        );
        final card = AnkiCardData(id: 5, nid: 5, did: 1);

        final result = adapter.adapt(note, card, importId: 't', mapping: mapping);

        expect(result.interaction, isA<FillBlank>());
        expect((result.interaction as FillBlank).answer, 'cat');
      });

      test('long answer stays a flip card', () {
        final note = AnkiNote(
          id: 6,
          mid: 1,
          fields: [
            'Explain photosynthesis',
            'Photosynthesis is the process by which plants convert light '
                'energy into chemical energy stored in glucose molecules',
          ],
        );
        final card = AnkiCardData(id: 6, nid: 6, did: 1);

        final result = adapter.adapt(note, card, importId: 't', mapping: mapping);

        expect(result.interaction, isA<AnkiCard>());
      });

      test('empty answer stays a flip card', () {
        final note = AnkiNote(id: 7, mid: 1, fields: ['prompt only', '']);
        final card = AnkiCardData(id: 7, nid: 7, did: 1);

        final result = adapter.adapt(note, card, importId: 't', mapping: mapping);

        expect(result.interaction, isA<AnkiCard>());
      });

      test('multi-line answer stays a flip card', () {
        final note = AnkiNote(
          id: 8,
          mid: 1,
          fields: ['list', 'line one<br>line two'],
        );
        final card = AnkiCardData(id: 8, nid: 8, did: 1);

        final result = adapter.adapt(note, card, importId: 't', mapping: mapping);

        expect(result.interaction, isA<AnkiCard>());
      });
    });

    group('template rendering', () {
      final notetype = AnkiNotetype(
        id: 1,
        name: 'Basic (and reversed)',
        fieldNames: const ['Front', 'Back'],
        templateNames: const ['Card 1', 'Card 2'],
        templates: const [
          AnkiTemplate(
            name: 'Card 1',
            qfmt: '{{Front}}',
            afmt: '{{FrontSide}}<hr id="answer">{{Back}}',
          ),
          AnkiTemplate(
            name: 'Card 2',
            qfmt: '{{Back}}',
            afmt: '{{FrontSide}}<hr id="answer">{{Front}}',
          ),
        ],
      );
      const mapping = NotetypeMapping(
        type: NotetypeMappingType.ankiCard,
        frontFieldIndex: 0,
        backFieldIndex: 1,
      );

      test('forward card renders Front → Back', () {
        final note = AnkiNote(id: 10, mid: 1, fields: ['merhaba', 'hello']);
        final card = AnkiCardData(id: 10, nid: 10, did: 1, ord: 0);

        final result = adapter.adapt(
          note,
          card,
          importId: 't',
          mapping: mapping,
          notetype: notetype,
        );

        final fb = result.interaction as FillBlank;
        expect(fb.sentence, contains('merhaba'));
        expect(fb.answer, 'hello');
      });

      test('reversed card renders Back → Front (direction-correct)', () {
        final note = AnkiNote(id: 11, mid: 1, fields: ['merhaba', 'hello']);
        final card = AnkiCardData(id: 11, nid: 11, did: 1, ord: 1);

        final result = adapter.adapt(
          note,
          card,
          importId: 't',
          mapping: mapping,
          notetype: notetype,
        );

        final fb = result.interaction as FillBlank;
        expect(fb.sentence, contains('hello'));
        expect(fb.answer, 'merhaba');
      });

      test('falls back to field indexes when template missing for ord', () {
        final note = AnkiNote(
          id: 12,
          mid: 1,
          fields: [
            'question',
            'a long enough answer that it stays a flip card for the '
                'purposes of this fallback test case here',
          ],
        );
        final card = AnkiCardData(id: 12, nid: 12, did: 1, ord: 5);

        final result = adapter.adapt(
          note,
          card,
          importId: 't',
          mapping: mapping,
          notetype: notetype,
        );

        final ankiCard = result.interaction as AnkiCard;
        expect(ankiCard.front, 'question');
        expect(ankiCard.back, startsWith('a long enough answer'));
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
