import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:turna/application/anki_import/adaptation/adaptation_input_builder.dart';
import 'package:turna/application/anki_official/contract/official_anki_dto.dart';

/// P5 budget gate: the model sees a bounded, structure-only view — never the
/// deck, never template source (plan §11.1).
void main() {
  OfficialAnkiProjectionSchema schema({
    List<String> fields = const ['Expression', 'Meaning', 'Audio', 'Image'],
    List<List<String>> samples = const [],
    OfficialAnkiTemplateFacts? facts,
  }) {
    return OfficialAnkiProjectionSchema(
      notetypeId: 7,
      name: 'Basic',
      kind: 'normal',
      fieldNames: fields,
      templateNames: const ['Card 1', 'Card 2'],
      schemaFingerprint: 'fp',
      samples: [
        for (var i = 0; i < samples.length; i++)
          OfficialAnkiProjectionSample(noteId: i, fields: samples[i]),
      ],
      templateFacts: facts,
    );
  }

  String userContent(AdaptationInput input) =>
      input.messages.last['content'] as String;

  test('the request never carries template source or stylesheets', () {
    final input = AdaptationInputBuilder.build(
      schema: schema(
        samples: const [
          ['kedi', 'cat', '[sound:kedi.mp3]', '<img src="kedi.png">'],
        ],
        facts: const OfficialAnkiTemplateFacts(
          hash: 'h',
          templates: [
            OfficialAnkiTemplateFact(
              ord: 0,
              name: 'Card 1',
              frontFields: [0, 2],
              backFields: [1, 3],
            ),
          ],
        ),
      ),
    );

    final content = userContent(input);
    for (final forbidden in ['qfmt', 'afmt', 'css', '<script', '</html']) {
      expect(
        content.toLowerCase().contains(forbidden),
        isFalse,
        reason: '模板源码/样式不得进 AI 输入',
      );
    }
    // What the model does need: face facts, field names, media histogram.
    expect(content, contains('frontFieldOrds'));
    expect(content, contains('Expression'));
    expect(content, contains('mediaByField'));
  });

  test('samples and long fields are clipped to the budget', () {
    final long = 'x' * 500;
    final input = AdaptationInputBuilder.build(
      schema: schema(
        samples: [
          for (var i = 0; i < 6; i++) [long, long, long, long],
        ],
      ),
      budget: const AdaptationInputBudget(
        sampleLimit: 2,
        fieldCharLimit: 20,
        sampleCharLimit: 60,
      ),
    );

    expect(input.sampleCount, lessThanOrEqualTo(2));
    final content = userContent(input);
    expect(content.contains('x' * 21), isFalse, reason: '超长字段必须截断');
    expect(content, contains('…'));
  });

  test('the media histogram counts audio and images per field', () {
    final input = AdaptationInputBuilder.build(
      schema: schema(
        samples: const [
          ['kedi', 'cat', '[sound:a.mp3][sound:b.mp3]', '<img src="p.png">'],
          ['kopek', 'dog', '[sound:c.mp3]', ''],
        ],
      ),
    );

    final payload = jsonDecode(userContent(input)) as Map<String, Object?>;
    final media = (payload['mediaByField'] as List).cast<Map<String, Object?>>();
    expect(media, hasLength(2));
    expect(media[0]['fieldIndex'], 2);
    expect(media[0]['audio'], 3, reason: '两段样本共三段音频');
    expect(media[1]['fieldIndex'], 3);
    expect(media[1]['images'], 1);
  });

  test('the same schema produces the same request (deterministic)', () {
    final first = AdaptationInputBuilder.build(
      schema: schema(samples: const [
        ['kedi', 'cat', '', ''],
      ]),
    );
    final second = AdaptationInputBuilder.build(
      schema: schema(samples: const [
        ['kedi', 'cat', '', ''],
      ]),
    );

    expect(jsonEncode(first.messages), jsonEncode(second.messages));
    expect(first.characterCount, second.characterCount);
  });

  test('the system prompt states the local rules it will be judged by', () {
    final input = AdaptationInputBuilder.build(schema: schema());
    final system = input.messages.first['content'] as String;

    expect(system, contains('answer'));
    expect(system, contains('front'));
    expect(system, contains('original'));
    expect(
      system.toLowerCase(),
      contains('untrusted'),
      reason: '牌组内容是数据，不是指令（注入防护）',
    );
  });
}
