import 'package:flutter_test/flutter_test.dart';
import 'package:turna/application/anki_import/recognition/facts/card_facts.dart';
import 'package:turna/application/anki_import/recognition/facts/notetype_facts.dart';
import 'package:turna/application/anki_import/recognition/facts/text_metrics.dart';
import 'package:turna/application/anki_import/recognition/lexicon/field_roles.dart';
import 'package:turna/application/anki_import/recognition/recognize/binding.dart';
import 'package:turna/application/anki_import/recognition/recognize/recognizer.dart';
import 'package:turna/application/anki_import/recognition/recognize/result.dart';
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

    test('a front-only field cannot bind as the response', () {
      final facts = NotetypeFacts.fromSchema(_schema(
        fieldNames: const ['答案', '正面'],
        samples: const [
          ['cat', '猫'],
          ['dog', '狗'],
        ],
        templateFacts: _faces(front: const [0], back: const [1]),
      ));
      final result = const RoleBindingSolver().bind(facts);
      expect(result[FieldRole.prompt]?.fieldName, '答案');
      expect(result[FieldRole.response]?.fieldName, '正面');
    });

    test('without template facts the lexicon still owns the names', () {
      final facts = NotetypeFacts.fromSchema(_schema(
        fieldNames: const ['答案', '正面'],
        samples: const [
          ['cat', '猫'],
        ],
      ));
      final result = const RoleBindingSolver().bind(facts);
      expect(result[FieldRole.response]?.fieldName, '答案');
      expect(result[FieldRole.prompt]?.fieldName, '正面');
    });

    test('reversed templates leave both-face fields on soft scores', () {
      final facts = NotetypeFacts.fromSchema(_schema(
        fieldNames: const ['答案', '正面'],
        samples: const [
          ['cat', '猫'],
          ['dog', '狗'],
        ],
        templateFacts: OfficialAnkiTemplateFacts(
          hash: 'h',
          templates: const [
            OfficialAnkiTemplateFact(
              ord: 0,
              name: 'Card 1',
              frontFields: [0],
              backFields: [0, 1],
            ),
            OfficialAnkiTemplateFact(
              ord: 1,
              name: 'Card 2',
              frontFields: [1],
              backFields: [1, 0],
            ),
          ],
        ),
      ));
      final result = const RoleBindingSolver().bind(facts);
      expect(result[FieldRole.prompt]?.fieldName, '正面');
      expect(result[FieldRole.response]?.fieldName, '答案');
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

  group('choice row measurement', () {
    test('rates parse and alignment independently', () {
      final stats = measureChoiceRows([
        ('题干\nA. 甲\nB. 乙', 'A'),
        ('题干\nA. 丙\nB. 丁', '这份答案无论如何都无法与选项对齐'),
        ('普通正面', '普通背面'),
      ]);
      expect(stats.totalRows, 3);
      expect(stats.parseRows, 2);
      expect(stats.alignedRows, 1);
      expect(stats.parseRate, closeTo(2 / 3, 0.001));
      expect(stats.alignRate, 0.5);
    });

    test('loose unlabeled pools only count once the answer aligns', () {
      final stats = measureChoiceRows([
        ('甲\n乙\n丙', 'B'),
        ('一段\n散文\n分行', '这是一段较长的散文背文，不是选项'),
      ]);
      expect(stats.totalRows, 2);
      expect(stats.parseRows, 1);
      expect(stats.alignedRows, 1);
    });
  });

  group('recognizer choice intelligence', () {
    const recognizer = CardRecognizer();

    test('A6 refuses a deck whose answers only sometimes align', () {
      final result = recognizer.recognizeFacts(NotetypeFacts.fromSchema(_schema(
        fieldNames: const ['Question', 'Answer'],
        samples: const [
          ['题干一\nA. 甲\nB. 乙', 'A'],
          ['题干二\nA. 丙\nB. 丁', 'B'],
          ['题干三\nA. 戊\nB. 己', '这份答案无法对齐'],
          ['题干四\nA. 庚\nB. 辛', '同样无法对齐的答案'],
        ],
      )));
      // parseRate 1.0 but alignRate 0.5 < 0.6 → the iron law owns it.
      expect(result.archetype, CardArchetype.richHtml);
    });

    test('unlabeled line pools with bare-label answers recognize as choice',
        () {
      final result = recognizer.recognizeFacts(NotetypeFacts.fromSchema(_schema(
        fieldNames: const ['Question', 'Answer'],
        samples: const [
          ['北京\n上海\n广州\n深圳', 'B'],
          ['春天\n夏天\n秋天\n冬天', 'C'],
          ['红色\n绿色\n蓝色\n黄色', 'A'],
        ],
      )));
      expect(result.archetype, CardArchetype.choice);
      expect(result.band, RecognitionBand.auto);
    });

    test('A6b recognizes options-on-back layouts at review band', () {
      final result = recognizer.recognizeFacts(NotetypeFacts.fromSchema(_schema(
        fieldNames: const ['Question', 'Answer'],
        samples: const [
          ['中国的首都是哪里？请从下列选项中选择正确的城市。', 'A. 北京\nB. 上海\nC. 广州\n答案：A'],
          ['下列哪条河流最长？请认真思考后作答。', 'A. 黄河\nB. 长江\nC. 珠江\n答案：B'],
          ['一年有几个季节？请选择正确的数字。', 'A. 两个\nB. 三个\nC. 四个\n答案：C'],
        ],
      )));
      expect(result.archetype, CardArchetype.choice);
      expect(result.band, RecognitionBand.review);
    });

    test('partially option-looking unaligned deck keeps fidelity, not flip',
        () {
      // 1/3 option-looking rows with unalignable answers: below the old
      // 0.60 iron-law floor this deck silently auto-flipped via A8.
      final result = recognizer.recognizeFacts(NotetypeFacts.fromSchema(_schema(
        fieldNames: const ['Question', 'Answer'],
        samples: const [
          ['以下哪个说法正确？\nA. 甲说法\nB. 乙说法\nC. 丙说法', '这道题需要结合材料进行论述分析作答'],
          ['Na', '钠'],
          ['Fe', '铁'],
        ],
      )));
      expect(result.archetype, CardArchetype.richHtml);
      expect(result.band, RecognitionBand.auto);
    });

    test('unresolved option signal blocks the silent auto pair', () {
      // 1/4 fronts mention A/B without being a choice: likeRate 0.25
      // blocks the corroboration bonus, so the pair lands in review
      // instead of silently auto-flipping.
      final result = recognizer.recognizeFacts(NotetypeFacts.fromSchema(_schema(
        fieldNames: const ['Front', 'Back'],
        samples: const [
          ['选项 A 和 B 的区别是什么？', '区别在于用途不同，需要结合上下文具体分析才能理解其中的差异'],
          ['Na', '钠'],
          ['Fe', '铁'],
          ['Cu', '铜'],
        ],
      )));
      expect(result.archetype, CardArchetype.basicPair);
      expect(result.band, RecognitionBand.review);
    });

    test('a layout table yields to an aligned choice', () {
      final result = recognizer.recognizeFacts(NotetypeFacts.fromSchema(_schema(
        fieldNames: const ['Question', 'Answer'],
        samples: const [
          ['北京\n上海\n广州\n深圳', 'B'],
          ['春天\n夏天\n秋天\n冬天', 'C'],
          ['红色\n绿色\n蓝色\n黄色', 'A'],
        ],
        templateFacts: _faces(
          front: const [0],
          back: const [0, 1],
          complexHtml: true,
        ),
      )));
      expect(result.archetype, CardArchetype.choice);
    });

    test('a layout table yields to {{type:}}', () {
      final result = recognizer.recognizeFacts(NotetypeFacts.fromSchema(_schema(
        fieldNames: const ['Front', 'Back'],
        samples: const [
          ['cat', '猫'],
        ],
        templateFacts: _faces(
          front: const [0],
          back: const [0, 1],
          complexHtml: true,
          typeIn: true,
        ),
      )));
      expect(result.archetype, CardArchetype.typeIn);
    });

    test('a script template stays fidelity over a short pair', () {
      final result = recognizer.recognizeFacts(NotetypeFacts.fromSchema(_schema(
        fieldNames: const ['Front', 'Back'],
        samples: const [
          ['cat', '猫'],
          ['dog', '狗'],
        ],
        templateFacts: _faces(
          front: const [0],
          back: const [0, 1],
          script: true,
          complexHtml: true,
        ),
      )));
      expect(result.archetype, CardArchetype.richHtml);
      expect(result.confidence, 1);
    });

    test('a layout table with no competing signal stays fidelity', () {
      final result = recognizer.recognizeFacts(NotetypeFacts.fromSchema(_schema(
        fieldNames: const ['Front', 'Back'],
        samples: const [
          ['这是一段较长的正面说明，用来确认没有短对信号。', '这是一段较长的背面说明，同样不是短答案。'],
          ['另一段正面说明继续保持句子长度，避免被当成词对。', '另一段背面说明同样写成完整的句子。'],
        ],
        templateFacts: _faces(
          front: const [0],
          back: const [0, 1],
          complexHtml: true,
        ),
      )));
      expect(result.archetype, CardArchetype.richHtml);
      expect(result.confidence, closeTo(0.70, 0.001));
      expect(result.band, RecognitionBand.review);
    });

    test('a table inside a field does not beat an aligned choice', () {
      final result = recognizer.recognizeFacts(NotetypeFacts.fromSchema(_schema(
        fieldNames: const ['Question', 'Answer', 'Notes'],
        samples: const [
          ['北京\n上海\n广州\n深圳', 'B', '<table><tr><td>注</td></tr></table>'],
          ['春天\n夏天\n秋天\n冬天', 'C', '<table><tr><td>注</td></tr></table>'],
          ['红色\n绿色\n蓝色\n黄色', 'A', '<audio src="a.mp3"></audio>'],
        ],
      )));
      expect(result.archetype, CardArchetype.choice);
    });

    test('a script inside a field still keeps fidelity', () {
      final result = recognizer.recognizeFacts(NotetypeFacts.fromSchema(_schema(
        fieldNames: const ['Question', 'Answer', 'Notes'],
        samples: const [
          ['北京\n上海\n广州\n深圳', 'B', '<script>bad()</script>'],
          ['春天\n夏天\n秋天\n冬天', 'C', '<script>bad()</script>'],
          ['红色\n绿色\n蓝色\n黄色', 'A', '<script>bad()</script>'],
        ],
      )));
      expect(result.archetype, CardArchetype.richHtml);
    });
  });
}

OfficialAnkiTemplateFacts _faces({
  required List<int> front,
  required List<int> back,
  bool script = false,
  bool complexHtml = false,
  bool typeIn = false,
}) {
  return OfficialAnkiTemplateFacts(
    hash: 'h',
    templates: [
      OfficialAnkiTemplateFact(
        ord: 0,
        name: 'Card 1',
        frontFields: front,
        backFields: back,
        script: script,
        complexHtml: complexHtml,
        typeIn: typeIn,
      ),
    ],
  );
}

OfficialAnkiProjectionSchema _schema({
  required List<String> fieldNames,
  required List<List<String>> samples,
  String kind = 'normal',
  OfficialAnkiTemplateFacts? templateFacts,
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
    templateFacts: templateFacts,
  );
}
