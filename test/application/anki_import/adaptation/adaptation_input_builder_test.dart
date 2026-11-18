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

  group('stratified diverse sampling and full-sample media histogram', () {
    test(
        'stratified sampling picks audio, image, cloze/extra, and length '
        'buckets even beyond index 30', () {
      final samples = <List<String>>[
        for (var i = 0; i < 31; i++) ['term $i', 'meaning $i', '', ''],
        // Index 31 (beyond 30): audio, short length
        ['audio term', 'audio meaning', '[sound:a1.mp3]', ''],
        // Index 32 (beyond 30): image, short length
        ['image term', 'image meaning', '', '<img src="p1.png">'],
        // Index 33 (beyond 30): cloze, short length
        ['{{c1::cloze}} term', 'cloze answer', '', ''],
        // Index 34 (beyond 30): extra non-trivial fields (>2), short length
        ['extra t', 'extra m', 'extra p', 'extra n'],
        // Index 35 (beyond 30): medium length (41..160 plain chars)
        ['medium ${'m' * 60}', 'medium meaning', '', ''],
        // Index 36 (beyond 30): long length (>160 plain chars)
        ['long ${'l' * 170}', 'long meaning', '', ''],
      ];

      // Default budget (sampleLimit: 3): picks audio, image, cloze from >30.
      final compactInput = AdaptationInputBuilder.build(
        schema: schema(samples: samples),
      );
      final compactPayload =
          jsonDecode(userContent(compactInput)) as Map<String, Object?>;
      final compactRows = (compactPayload['samples'] as List)
          .cast<Map<String, Object?>>()
          .map((row) => (row['fields'] as List).cast<String>())
          .toList();

      expect(compactInput.sampleCount, 3);
      expect(compactRows.any((f) => f[2].contains('[sound:a1.mp3]')), isTrue);
      expect(compactRows.any((f) => f[3].contains('<img src="p1.png">')), isTrue);
      expect(compactRows.any((f) => f[0].contains('{{c1::cloze}}')), isTrue);

      // Larger budget (sampleLimit: 6): also covers medium and long buckets >30.
      final diverseInput = AdaptationInputBuilder.build(
        schema: schema(samples: samples),
        budget: const AdaptationInputBudget(
          sampleLimit: 6,
          fieldCharLimit: 250,
          sampleCharLimit: 5000,
        ),
      );
      final diversePayload =
          jsonDecode(userContent(diverseInput)) as Map<String, Object?>;
      final diverseRows = (diversePayload['samples'] as List)
          .cast<Map<String, Object?>>()
          .map((row) => (row['fields'] as List).cast<String>())
          .toList();

      expect(diverseInput.sampleCount, 6);
      expect(diverseRows.any((f) => f[2].contains('[sound:a1.mp3]')), isTrue);
      expect(diverseRows.any((f) => f[3].contains('<img src="p1.png">')), isTrue);
      expect(diverseRows.any((f) => f[0].contains('{{c1::cloze}}')), isTrue);
      expect(diverseRows.any((f) => f[0].startsWith('medium ')), isTrue);
      expect(diverseRows.any((f) => f[0].startsWith('long ')), isTrue);
    });

    test(
        'stratified sampling prioritizes extra-field samples beyond index 30 '
        'when no cloze exists', () {
      final samples = <List<String>>[
        for (var i = 0; i < 32; i++) ['term $i', 'meaning $i', '', ''],
        ['extra word', 'extra meaning', 'pronunciation', 'usage note'],
      ];

      final input = AdaptationInputBuilder.build(
        schema: schema(samples: samples),
      );
      final payload = jsonDecode(userContent(input)) as Map<String, Object?>;
      final rows = (payload['samples'] as List)
          .cast<Map<String, Object?>>()
          .map((row) => (row['fields'] as List).cast<String>())
          .toList();

      expect(rows.any((f) => f[0] == 'extra word'), isTrue);
    });

    test(
        'mediaByField reflects full schema.samples beyond the first 3 and '
        'pool caps at 30 unique samples', () {
      final samples = <List<String>>[
        // First 31 samples have zero media (and some duplicates).
        for (var i = 0; i < 31; i++) ['plain ${i % 28}', 'meaning $i', '', ''],
        // 5 media-bearing samples beyond index 30 (and far beyond index 3).
        ['a1', 'm1', '[sound:s1.mp3][sound:s2.mp3]', ''],
        ['a2', 'm2', '[sound:s3.mp3]', '<img src="i1.png">'],
        ['a3', 'm3', '[sound:s4.mp3]', '<img src="i2.png">'],
        ['a4', 'm4', '[sound:s5.mp3]', ''],
        ['i3', 'm5', '', '<img src="i3.png">'],
      ];

      final defaultInput = AdaptationInputBuilder.build(
        schema: schema(samples: samples),
      );
      expect(defaultInput.sampleCount, 3);
      final payload =
          jsonDecode(userContent(defaultInput)) as Map<String, Object?>;
      final media =
          (payload['mediaByField'] as List).cast<Map<String, Object?>>();

      expect(media, hasLength(2));
      expect(media[0], {'fieldIndex': 2, 'audio': 5, 'images': 0});
      expect(media[1], {'fieldIndex': 3, 'audio': 0, 'images': 3});

      final maxPoolInput = AdaptationInputBuilder.build(
        schema: schema(samples: samples),
        budget: const AdaptationInputBudget(
          sampleLimit: 40,
          fieldCharLimit: 200,
          sampleCharLimit: 10000,
        ),
      );
      expect(maxPoolInput.sampleCount, 30);
    });
  });
}
