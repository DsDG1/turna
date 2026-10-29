import 'package:flutter_test/flutter_test.dart';
import 'package:turna/application/anki_import/recognition/lexicon/field_roles.dart';
import 'package:turna/application/anki_import/recognition/recognize/result.dart';
import 'package:turna/application/anki_official/contract/official_anki_dto.dart';
import 'package:turna/application/anki_official/projection/official_anki_mapping_suggestion.dart';
import 'package:turna/application/anki_official/projection/official_anki_projection_payloads.dart';
import 'package:turna/domain/anki/adaptation/card_adaptation_plan.dart';

/// P2 gate: the flip payload carries every media occurrence, in order, on the
/// face it was proven to belong to (ADR 0057 §5).
void main() {
  final payloads = OfficialAnkiProjectionPayloads();

  OfficialAnkiFieldCandidate bind(FieldRole role, int index) =>
      OfficialAnkiFieldCandidate(
        role: role,
        fieldIndex: index,
        fieldName: 'f$index',
        confidence: 1,
        evidence: const [],
      );

  OfficialAnkiProjectionRow row(List<String> fields, {int ordinal = 0}) =>
      OfficialAnkiProjectionRow(
        cardId: 7,
        noteId: 70,
        noteGuid: 'guid-7',
        notetypeId: 1,
        deckId: 10,
        deckPath: const ['Deck'],
        templateOrdinal: ordinal,
        tags: const [],
        fields: fields,
        sourceFingerprint: 'fp-7',
      );

  OfficialAnkiProjectedItem item(OfficialAnkiProjectionKind kind) =>
      OfficialAnkiProjectedItem(
        kind: kind,
        cardId: 7,
        wordId: 'w-7',
        sectionId: 's',
        unitId: 'u',
        lessonId: 'l',
        sectionName: 'S',
        unitName: 'U',
        lessonName: 'L',
        payload: const {},
        sourceFingerprint: 'fp-7',
      );

  OfficialAnkiMappingSuggestion mapping({
    List<OfficialAnkiTemplateFaceFacts> faces =
        const <OfficialAnkiTemplateFaceFacts>[],
  }) {
    return OfficialAnkiMappingSuggestion(
      candidates: [
        bind(FieldRole.prompt, 0),
        bind(FieldRole.response, 1),
        bind(FieldRole.audio, 2),
        bind(FieldRole.image, 3),
      ],
      status: OfficialAnkiMappingStatus.manual,
      archetype: 'basicPair',
      templateFaces: faces,
    );
  }

  Map<String, Object?> payloadFor(
    List<String> fields,
    OfficialAnkiMappingSuggestion suggestion, {
    OfficialAnkiProjectionKind kind = OfficialAnkiProjectionKind.flip,
    CardAdaptationPlan? plan,
  }) {
    final values = payloads.values(row(fields), suggestion, plan: plan);
    return payloads.interactionJson(
      kind: kind,
      item: item(kind),
      values: values,
      sourceId: 'src-1',
    );
  }

  test('media splits onto the proven face, keeping order and duplicates', () {
    final json = payloadFor(
      [
        'hello',
        'merhaba',
        '[sound:a.mp3][sound:b.mp3]',
        '<img src="answer.png">',
      ],
      mapping(
        faces: const [
          OfficialAnkiTemplateFaceFacts(
            ordinal: 0,
            frontFieldOrds: [0, 2],
            backFieldOrds: [1, 3],
          ),
        ],
      ),
    );

    expect(json['frontAudioAssets'], ['a.mp3', 'b.mp3']);
    expect(json['frontImageAssets'], isEmpty);
    expect(json['backImageAssets'], ['answer.png']);
    expect(json['backAudioAssets'], isEmpty);
    expect(
      json['audioAssets'],
      isEmpty,
      reason: '已证面的媒体不再进 legacy 全量表',
    );
  });

  test('without face facts media is deferred, never put on the front', () {
    final json = payloadFor(
      ['hello', 'merhaba', '[sound:a.mp3]', '<img src="pic.png">'],
      mapping(),
    );

    expect(json['frontAudioAssets'], isEmpty);
    expect(json['frontImageAssets'], isEmpty);
    expect(
      json['audioAssets'],
      ['a.mp3'],
      reason: '面未证时只进 legacy 表，渲染器把它锁在答案面',
    );
    expect(json['imageAssets'], ['pic.png']);
  });

  test('a field rendered on no face contributes nothing', () {
    final json = payloadFor(
      ['hello', 'merhaba', '[sound:a.mp3]', '<img src="hidden.png">'],
      mapping(
        faces: const [
          OfficialAnkiTemplateFaceFacts(
            ordinal: 0,
            frontFieldOrds: [0],
            backFieldOrds: [1],
          ),
        ],
      ),
    );

    expect(json['frontAudioAssets'], isEmpty);
    expect(json['backImageAssets'], isEmpty);
    expect(json['audioAssets'], isEmpty);
    expect(json['imageAssets'], isEmpty);
  });

  group('per-template direction', () {
    // Template 0 reads Expression→Meaning; template 1 is the reverse card.
    const faces = [
      OfficialAnkiTemplateFaceFacts(
        ordinal: 0,
        frontFieldOrds: [0, 2],
        backFieldOrds: [1, 3],
      ),
      OfficialAnkiTemplateFaceFacts(
        ordinal: 1,
        frontFieldOrds: [1],
        backFieldOrds: [0, 2, 3],
        direction: 'responseToPrompt',
      ),
    ];
    const fields = ['hello', 'merhaba', '[sound:a.mp3]', '<img src="pic.png">'];

    test('the forward template keeps prompt on the front', () {
      final values = payloads.values(row(fields, ordinal: 0), mapping(faces: faces));

      expect(values.target, 'hello');
      expect(values.native, 'merhaba');
      expect(values.frontAudio, ['a.mp3']);
      expect(values.backImages, ['pic.png']);
    });

    test('the reverse template swaps the faces, not just the text', () {
      final values = payloads.values(row(fields, ordinal: 1), mapping(faces: faces));

      expect(values.target, 'merhaba', reason: '反向卡正面是释义');
      expect(values.native, 'hello');
      expect(
        values.frontAudio,
        isEmpty,
        reason: '方向反转后音频在背面，不能留在正面',
      );
      expect(values.backAudio, ['a.mp3']);
    });

    test('without per-template facts the notetype direction is assumed', () {
      final values = payloads.values(row(fields, ordinal: 1), mapping());

      expect(values.target, 'hello');
      expect(values.native, 'merhaba');
    });
  });

  test('a basicPair notetype keeps its constrained variants explicit', () {
    final values = payloads.values(
      row(const ['cloze: {{c1::kedi}} burada', 'kedi', '', '']),
      mapping(),
    );

    expect(values.archetype, CardArchetype.cloze);
    expect(values.variant, CardContentVariant.cloze);
  });

  test('a plain pair carries no variant', () {
    final values = payloads.values(
      row(const ['hello', 'merhaba', '', '']),
      mapping(),
    );

    expect(values.variant, CardContentVariant.none);
  });

  group('opt-in payloads never leak the answer', () {
    const faces = [
      OfficialAnkiTemplateFaceFacts(
        ordinal: 0,
        frontFieldOrds: [0, 2, 3],
        backFieldOrds: [1],
      ),
    ];

    test('dictation carries audio and the expected text, no prompt', () {
      final json = payloadFor(
        ['hello', 'merhaba', '[sound:word.mp3]', '<img src="pic.png">'],
        mapping(faces: faces),
        kind: OfficialAnkiProjectionKind.dictation,
      );

      expect(json['runtimeType'], 'dictation');
      expect(json['audioAssets'], ['word.mp3']);
      expect(json['expected'], 'hello');
      expect(
        json.containsKey('prompt'),
        isFalse,
        reason: '听写不给文字题面，否则等于把答案写在题面上',
      );
      expect(json.containsKey('hint'), isTrue);
      expect(json['hint'], isNull, reason: '发音/释义提示同样会泄题');
    });

    test('image recall carries the prompt image and the answer text', () {
      final json = payloadFor(
        ['hello', 'merhaba', '[sound:word.mp3]', '<img src="pic.png">'],
        mapping(faces: faces),
        kind: OfficialAnkiProjectionKind.imageRecall,
      );

      expect(json['runtimeType'], 'imageRecall');
      expect(json['imageAssets'], ['pic.png']);
      expect(json['answerText'], 'hello');
      expect(json.containsKey('hint'), isTrue);
      expect(json['hint'], isNull);
    });
  });

  group('plan layout owns the flip faces', () {
    CardAdaptationPlan layoutPlan() => const CardAdaptationPlan(
          planId: 'plan-layout',
          revision: 1,
          scope: AdaptationScope(
            sourceId: 'src-1',
            notetypeId: 7,
            templateOrdinal: 0,
          ),
          bindings: <String, int>{'prompt': 0, 'answer': 1},
          front: <AdaptationBlock>[
            AdaptationBlock(kind: 'text', fieldIndex: 0),
            AdaptationBlock(kind: 'imageGroup', fieldIndex: 3),
          ],
          back: <AdaptationBlock>[
            AdaptationBlock(kind: 'text', fieldIndex: 1),
            AdaptationBlock(kind: 'audioGroup', fieldIndex: 2),
          ],
        );

    test('blocks decide the text and the media of each face', () {
      final json = payloadFor(
        ['hello', 'merhaba', '[sound:a.mp3]', '<img src="pic.png">'],
        mapping(
          faces: const [
            OfficialAnkiTemplateFaceFacts(
              ordinal: 0,
              frontFieldOrds: [0, 3],
              backFieldOrds: [1, 2],
            ),
          ],
        ),
        plan: layoutPlan(),
      );

      expect(json['front'], 'hello');
      expect(json['back'], 'merhaba');
      expect(json['frontImageAssets'], ['pic.png']);
      expect(json['frontAudioAssets'], isEmpty);
      expect(json['backAudioAssets'], ['a.mp3']);
      expect(
        json['audioAssets'],
        isEmpty,
        reason: '方案接管时不再退 legacy 全量表',
      );
      expect(json['imageAssets'], isEmpty);
    });

    test('without a plan the role extraction still drives the faces', () {
      final json = payloadFor(
        ['hello', 'merhaba', '[sound:a.mp3]', '<img src="pic.png">'],
        mapping(
          faces: const [
            OfficialAnkiTemplateFaceFacts(
              ordinal: 0,
              frontFieldOrds: [0, 3],
              backFieldOrds: [1, 2],
            ),
          ],
        ),
      );

      expect(json['front'], 'hello');
      expect(json['frontImageAssets'], ['pic.png']);
      expect(json['backAudioAssets'], ['a.mp3']);
    });
  });

  group('officialAnkiTemplateDirection', () {
    test('front renders the answer role: reversed', () {
      expect(
        officialAnkiTemplateDirection(
          frontFieldOrds: const [1],
          promptFieldOrd: 0,
          responseFieldOrd: 1,
        ),
        'responseToPrompt',
      );
    });

    test('front renders the prompt role: forward', () {
      expect(
        officialAnkiTemplateDirection(
          frontFieldOrds: const [0],
          promptFieldOrd: 0,
          responseFieldOrd: 1,
        ),
        'promptToResponse',
      );
    });

    test('both roles on the front is not a reversal', () {
      expect(
        officialAnkiTemplateDirection(
          frontFieldOrds: const [0, 1],
          promptFieldOrd: 0,
          responseFieldOrd: 1,
        ),
        'promptToResponse',
      );
    });

    test('unknown bindings fall back to the notetype direction', () {
      expect(
        officialAnkiTemplateDirection(
          frontFieldOrds: const [2],
          promptFieldOrd: null,
          responseFieldOrd: null,
        ),
        'promptToResponse',
      );
    });
  });
}
