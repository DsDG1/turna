// Package imports:
import 'package:flutter_test/flutter_test.dart';

// Project imports:
import 'package:turna/application/anki/anki_card_adapter.dart';
import 'package:turna/application/anki/anki_models.dart';
import 'package:turna/domain/course/interaction.dart';

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

      test('detects MCQ notetype with Option A/B/C/D fields', () {
        final notetype = AnkiNotetype(
          id: 7,
          name: 'Multiple Choice',
          fieldNames: [
            'Question',
            'Option A',
            'Option B',
            'Option C',
            'Option D',
            'Answer',
          ],
        );

        final mapping = AnkiCardAdapter.inferMapping(notetype);
        expect(mapping.type, NotetypeMappingType.multipleChoice);
        expect(mapping.frontFieldIndex, 0);
        expect(mapping.backFieldIndex, 5);
      });

      test('multi-select notetype name still maps to multipleChoice', () {
        // Notetype-level multiSelect was collapsed: single vs multi is
        // resolved per card at adapt time, so inference always emits
        // multipleChoice (import UI has one "choice" option).
        final notetype = AnkiNotetype(
          id: 8,
          name: '多选题',
          fieldNames: ['题目', '选项A', '选项B', '选项C', '选项D', '答案'],
        );

        final mapping = AnkiCardAdapter.inferMapping(notetype);
        expect(mapping.type, NotetypeMappingType.multipleChoice);
        expect(mapping.reason, contains('per card'));
      });
    });

    group('choice helpers', () {
      test('parseCorrectIndices handles letters, numbers, and lists', () {
        const options = ['apple', 'banana', 'cherry', 'date'];
        expect(AnkiCardAdapter.parseCorrectIndices('B', options), [1]);
        expect(AnkiCardAdapter.parseCorrectIndices('1', options), [0]);
        expect(AnkiCardAdapter.parseCorrectIndices('A,C', options), [0, 2]);
        expect(AnkiCardAdapter.parseCorrectIndices('banana', options), [1]);
        expect(AnkiCardAdapter.parseCorrectIndices('AC', options), [0, 2]);
      });

      test('extractEmbeddedOptions parses A/B/C lines', () {
        const front = 'What is 2+2?\nA. 3\nB. 4\nC. 5\nD. 6';
        final embedded = AnkiCardAdapter.extractEmbeddedOptions(front);
        expect(embedded, isNotNull);
        expect(embedded!.prompt, 'What is 2+2?');
        expect(embedded.options, ['3', '4', '5', '6']);
      });

      test('extractEmbeddedOptions parses inline A./B./C./D. without newlines',
          () {
        // Mirrors Chinese quiz Anki cards after HTML strip: options jammed
        // into one paragraph (the screenshot regression).
        const front = '导论 习近平新时代中国特色社会主义思想，把马克思主义基本原理同中国具体实际相结合、同中华优秀传统文化相结合'
            'A. 使马克思主义这个魂脉和中华优秀传统文化这个根脉内在贯通、相互成就'
            'B. 用中华文明充实马克思主义的文化生命'
            'C. 用马克思主义进一步激活中华文明的基因'
            'D. 是中华民族的文化主体性最有力的体现';
        final embedded = AnkiCardAdapter.extractEmbeddedOptions(front);
        expect(embedded, isNotNull);
        expect(embedded!.options, hasLength(4));
        expect(embedded.options[0], startsWith('使马克思主义'));
        expect(embedded.options[1], startsWith('用中华文明'));
        expect(embedded.options[3], contains('文化主体性'));
        expect(embedded.prompt, contains('导论'));
        expect(embedded.prompt, isNot(contains('A.')));
      });

      test('parseCorrectIndices strips 答案： prefix and glued ABCD', () {
        const options = ['甲', '乙', '丙', '丁'];
        expect(
          AnkiCardAdapter.parseCorrectIndices('答案：ABCD', options),
          [0, 1, 2, 3],
        );
      });

      test('parseCorrectIndices does not treat "0" as a 0-based option', () {
        // Regression: a teacher using "0" as a "no answer" sentinel was
        // getting option A marked correct via the 0-based fallback branch.
        // Numeric answers are 1-based; out-of-range and 0 produce an empty
        // correctIndices list so the prompt surfaces as failed instead of
        // silently passing on option A.
        const options = ['apple', 'banana', 'cherry', 'date'];
        expect(AnkiCardAdapter.parseCorrectIndices('0', options), isEmpty);
        expect(AnkiCardAdapter.parseCorrectIndices('5', options), isEmpty);
        expect(AnkiCardAdapter.parseCorrectIndices('-1', options), isEmpty);
        // "4" still maps to the 4th option (options[3]) — 1-based contract.
        expect(AnkiCardAdapter.parseCorrectIndices('4', options), [3]);
        // "1,0" → option A is correct; the 0 token is dropped.
        expect(
          AnkiCardAdapter.parseCorrectIndices('1,0', options),
          [0],
        );
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
        expect(result.wordId, 'anki-test-c1');
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
        expect(mcq.options, isNot(contains('—')));
        expect(result.wordEntry, isNotNull);
        expect(result.wordEntry!.term, 'merhaba');
        expect(result.wordEntry!.translation, 'hello');
      });

      test('wordEntry falls back to FillBlank without enough distractors', () {
        final note = AnkiNote(
          id: 98,
          mid: 2,
          fields: ['merhaba', 'hello'],
        );
        final card = AnkiCardData(id: 2, nid: 98, did: 1);

        final result = adapter.adapt(
          note,
          card,
          importId: 'abc',
          mapping: const NotetypeMapping(
            type: NotetypeMappingType.wordEntry,
            frontFieldIndex: 0,
            backFieldIndex: 1,
          ),
          distractors: const [], // no deck mates
        );

        expect(result.interaction, isA<FillBlank>());
        expect(result.wordEntry, isNotNull);
      });

      test('adapts note option fields to MultipleChoice', () {
        final notetype = AnkiNotetype(
          id: 10,
          name: 'MCQ',
          fieldNames: [
            'Question',
            'Option A',
            'Option B',
            'Option C',
            'Option D',
            'Answer',
          ],
        );
        final note = AnkiNote(
          id: 501,
          mid: 10,
          fields: [
            'Capital of France?',
            'London',
            'Paris',
            'Berlin',
            'Madrid',
            'B',
          ],
        );
        final card = AnkiCardData(id: 5010, nid: 501, did: 1);

        final result = adapter.adapt(
          note,
          card,
          importId: 'mcq',
          mapping: const NotetypeMapping(
            type: NotetypeMappingType.multipleChoice,
            frontFieldIndex: 0,
            backFieldIndex: 5,
          ),
          notetype: notetype,
        );

        expect(result.interaction, isA<MultipleChoice>());
        final mcq = result.interaction as MultipleChoice;
        expect(mcq.prompt, 'Capital of France?');
        expect(mcq.options, ['London', 'Paris', 'Berlin', 'Madrid']);
        expect(mcq.correctIndex, 1); // B → Paris
      });

      test('adapts multi-select answer keys A,C', () {
        final notetype = AnkiNotetype(
          id: 11,
          name: '多选',
          fieldNames: ['题干', '选项A', '选项B', '选项C', '选项D', '答案'],
        );
        final note = AnkiNote(
          id: 502,
          mid: 11,
          fields: [
            'Which are fruits?',
            'apple',
            'car',
            'banana',
            'desk',
            'A,C'
          ],
        );
        final card = AnkiCardData(id: 5020, nid: 502, did: 1);

        final result = adapter.adapt(
          note,
          card,
          importId: 'ms',
          mapping: const NotetypeMapping(
            type: NotetypeMappingType.multiSelect,
            frontFieldIndex: 0,
            backFieldIndex: 5,
          ),
          notetype: notetype,
        );

        expect(result.interaction, isA<MultiSelect>());
        final ms = result.interaction as MultiSelect;
        expect(ms.correctIndices, [0, 2]);
        expect(ms.options, ['apple', 'car', 'banana', 'desk']);
      });

      test('auto-decides MCQ from embedded A/B/C options in front', () {
        final note = AnkiNote(
          id: 503,
          mid: 1,
          fields: [
            '2 + 2 = ?\nA. 3\nB. 4\nC. 5',
            'B',
          ],
        );
        final card = AnkiCardData(id: 5030, nid: 503, did: 1);

        final result = adapter.adapt(
          note,
          card,
          importId: 'emb',
          mapping: const NotetypeMapping(
            type: NotetypeMappingType.ankiCard,
            frontFieldIndex: 0,
            backFieldIndex: 1,
          ),
        );

        expect(result.interaction, isA<MultipleChoice>());
        final mcq = result.interaction as MultipleChoice;
        expect(mcq.prompt, '2 + 2 = ?');
        expect(mcq.options, ['3', '4', '5']);
        expect(mcq.correctIndex, 1);
      });

      test('inline multi-select ABCD becomes MultiSelect with real options',
          () {
        // Regression for screenshot: stem+options in one block, answer ABCD,
        // must NOT invent deck-distractor choices like unrelated passages.
        final front = '题目9 多项选择题 导论 把马克思主义基本原理同中国具体实际相结合'
            'A. 魂脉和根脉内在贯通、相互成就'
            'B. 用中华文明充实马克思主义的文化生命'
            'C. 用马克思主义进一步激活中华文明的基因'
            'D. 是中华民族的文化主体性最有力的体现';
        final note = AnkiNote(
          id: 504,
          mid: 1,
          fields: [front, '答案：ABCD'],
        );
        final card = AnkiCardData(id: 5040, nid: 504, did: 1);

        final result = adapter.adapt(
          note,
          card,
          importId: 'ss',
          mapping: const NotetypeMapping(
            type: NotetypeMappingType.ankiCard,
            frontFieldIndex: 0,
            backFieldIndex: 1,
          ),
          // Poison distractors: old path would use these as fake options.
          distractors: const [
            '在新民主主义革命时期，中国共产党与国民党实行过两次合作',
            '构建新安全格局是应对国家安全形势新变化',
            '面对夕阳西下，有的人脱口而出',
          ],
        );

        expect(result.interaction, isA<MultiSelect>());
        final ms = result.interaction as MultiSelect;
        expect(ms.options, hasLength(4));
        expect(ms.options[0], contains('魂脉'));
        expect(ms.options[1], contains('中华文明'));
        expect(ms.correctIndices, [0, 1, 2, 3]);
        expect(ms.prompt, isNot(contains('A.')));
        // Must not surface deck distractors as choices.
        expect(ms.options.join(), isNot(contains('新民主主义')));
      });

      test('single-choice evidence rejects a multi-answer key', () {
        final note = AnkiNote(
          id: 505,
          mid: 1,
          fields: [
            '题目 3 单项选择题\nA. 甲\nB. 乙\nC. 丙\nD. 丁',
            '答案：ACD',
          ],
        );
        final card = AnkiCardData(id: 5050, nid: 505, did: 1);

        final result = adapter.adapt(
          note,
          card,
          importId: 'single-conflict',
          mapping: const NotetypeMapping(
            type: NotetypeMappingType.ankiCard,
            frontFieldIndex: 0,
            backFieldIndex: 1,
          ),
        );

        expect(result.interaction, isA<AnkiCard>());
        expect(result.interaction, isNot(isA<MultiSelect>()));
      });

      test('one note type can mix single and multi choice card-by-card', () {
        final notetype = AnkiNotetype(
          id: 12,
          name: '单选与多选混合题',
          fieldNames: const [
            '题干',
            '选项A',
            '选项B',
            '选项C',
            '选项D',
            '答案',
          ],
        );
        const singleMapping = NotetypeMapping(
          type: NotetypeMappingType.multipleChoice,
          frontFieldIndex: 0,
          backFieldIndex: 5,
        );
        const multiMapping = NotetypeMapping(
          type: NotetypeMappingType.multiSelect,
          frontFieldIndex: 0,
          backFieldIndex: 5,
        );

        final single = adapter.adapt(
          AnkiNote(
            id: 507,
            mid: 12,
            fields: const ['单项选择题：选出一个', '甲', '乙', '丙', '丁', 'B'],
          ),
          AnkiCardData(id: 5070, nid: 507, did: 1),
          importId: 'mixed',
          // Even a note-type-level multi mapping must not override this card.
          mapping: multiMapping,
          notetype: notetype,
        );
        final multi = adapter.adapt(
          AnkiNote(
            id: 508,
            mid: 12,
            fields: const ['多项选择题：选择所有正确项', '甲', '乙', '丙', '丁', 'A,C'],
          ),
          AnkiCardData(id: 5080, nid: 508, did: 1),
          importId: 'mixed',
          // Even a note-type-level single mapping must not override this card.
          mapping: singleMapping,
          notetype: notetype,
        );

        expect(single.interaction, isA<MultipleChoice>());
        expect((single.interaction as MultipleChoice).correctIndex, 1);
        expect(multi.interaction, isA<MultiSelect>());
        expect((multi.interaction as MultiSelect).correctIndices, [0, 2]);
      });

      test('complete answer-key count resolves unspecified choice type', () {
        final notetype = AnkiNotetype(
          id: 13,
          name: '选择题',
          fieldNames: const ['题干', '选项A', '选项B', '选项C', '答案'],
        );
        const mapping = NotetypeMapping(
          type: NotetypeMappingType.multipleChoice,
          frontFieldIndex: 0,
          backFieldIndex: 4,
        );

        final result = adapter.adapt(
          AnkiNote(
            id: 509,
            mid: 13,
            fields: const ['以下哪些符合条件？', '甲', '乙', '丙', 'A,C'],
          ),
          AnkiCardData(id: 5090, nid: 509, did: 1),
          importId: 'answer-count',
          mapping: mapping,
          notetype: notetype,
        );

        expect(result.interaction, isA<MultiSelect>());
        expect((result.interaction as MultiSelect).correctIndices, [0, 2]);
      });

      test('answer prose containing option letters is not treated as a key',
          () {
        final note = AnkiNote(
          id: 506,
          mid: 1,
          fields: [
            'Which statement is correct?\nA. Alpha\nB. Beta\nC. Gamma',
            'The explanation discusses A and C, but does not provide a key.',
          ],
        );
        final card = AnkiCardData(id: 5060, nid: 506, did: 1);

        final result = adapter.adapt(
          note,
          card,
          importId: 'prose-answer',
          mapping: const NotetypeMapping(
            type: NotetypeMappingType.ankiCard,
            frontFieldIndex: 0,
            backFieldIndex: 1,
          ),
        );

        expect(result.interaction, isA<AnkiCard>());
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

      test('extracts quoted media tags and CSS URLs with Unicode names', () {
        final media = AnkiCardAdapter.extractMedia(
          "<img src='图片 1.png'><audio src=\"音频 1.mp3\"></audio>"
              "<div style=\"background:url('背景.png')\"></div>",
          'imp1',
        );
        expect(
            media.images,
            containsAll([
              'anki://imp1/图片 1.png',
              'anki://imp1/背景.png',
            ]));
        expect(media.audios, ['anki://imp1/音频 1.mp3']);
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
        final note =
            AnkiNote(id: 1, mid: 1, fields: ['capital of France?', 'Paris']);
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
        final note =
            AnkiNote(id: 2, mid: 1, fields: ['capital of France?', 'Paris']);
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

        final result =
            adapter.adapt(note, card, importId: 't', mapping: mapping);

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

        final result =
            adapter.adapt(note, card, importId: 't', mapping: mapping);

        expect(result.interaction, isA<AnkiCard>());
      });

      test('empty answer stays a flip card', () {
        final note = AnkiNote(id: 7, mid: 1, fields: ['prompt only', '']);
        final card = AnkiCardData(id: 7, nid: 7, did: 1);

        final result =
            adapter.adapt(note, card, importId: 't', mapping: mapping);

        expect(result.interaction, isA<AnkiCard>());
      });

      test('multi-line answer stays a flip card', () {
        final note = AnkiNote(
          id: 8,
          mid: 1,
          fields: ['list', 'line one<br>line two'],
        );
        final card = AnkiCardData(id: 8, nid: 8, did: 1);

        final result =
            adapter.adapt(note, card, importId: 't', mapping: mapping);

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
