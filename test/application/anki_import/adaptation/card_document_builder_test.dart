import 'package:flutter_test/flutter_test.dart';
import 'package:turna/application/anki_import/adaptation/card_document_builder.dart';
import 'package:turna/application/anki_official/contract/official_anki_dto.dart';
import 'package:turna/domain/anki/adaptation/card_adaptation_plan.dart';

/// P4/P6 layout gate: the plan's blocks decide what lands on which face, and an
/// unrenderable block sends the whole card back to the original (ADR 0057 §5).
void main() {
  OfficialAnkiProjectionRow row(List<String> fields) =>
      OfficialAnkiProjectionRow(
        cardId: 7,
        noteId: 70,
        noteGuid: 'g',
        notetypeId: 1,
        deckId: 10,
        deckPath: const ['Deck'],
        templateOrdinal: 0,
        tags: const [],
        fields: fields,
        sourceFingerprint: 'fp',
      );

  AdaptationBlock block(String kind, int fieldIndex, {String? selection}) =>
      AdaptationBlock(
        kind: kind,
        fieldIndex: fieldIndex,
        selection: selection ?? 'all',
      );

  CardAdaptationPlan plan({
    List<AdaptationBlock>? front,
    List<AdaptationBlock>? back,
  }) =>
      CardAdaptationPlan(
        planId: 'p',
        revision: 1,
        scope: const AdaptationScope(
          sourceId: 'src',
          notetypeId: 1,
          templateOrdinal: 0,
        ),
        bindings: const {'prompt': 0, 'answer': 1},
        front: front ?? const [],
        back: back ?? const [],
      );

  test('each block contributes text or media to its own face', () {
    final document = buildCardDocument(
      plan: plan(
        front: [block('text', 0), block('imageGroup', 3)],
        back: [block('text', 1), block('audioGroup', 2)],
      ),
      row: row([
        'merhaba',
        '你好',
        '[sound:a.mp3][sound:b.mp3]',
        '<img src="pic.png">',
      ]),
    );

    expect(document.unsupported, isFalse);
    expect(document.front.text, 'merhaba');
    expect(document.front.images, ['pic.png']);
    expect(document.front.audio, isEmpty);
    expect(document.back.text, '你好');
    expect(document.back.audio, ['a.mp3', 'b.mp3']);
    expect(document.back.images, isEmpty);
  });

  test('selection=first keeps one occurrence of the field', () {
    final document = buildCardDocument(
      plan: plan(back: [block('audioGroup', 2, selection: 'first')]),
      row: row(['a', 'b', '[sound:x.mp3][sound:y.mp3]', '']),
    );

    expect(document.back.audio, ['x.mp3']);
  });

  test('several text blocks join in plan order', () {
    final document = buildCardDocument(
      plan: plan(front: [block('text', 0), block('text', 1)]),
      row: row(['one', 'two', '', '']),
    );

    expect(document.front.text, 'one\ntwo');
  });

  test('a field index the card does not have makes the layout unsupported', () {
    final document = buildCardDocument(
      plan: plan(front: [block('text', 9)]),
      row: row(['a', 'b']),
    );

    expect(document.unsupported, isTrue);
  });

  test('a text block over scripts or embedded media is unsupported', () {
    final document = buildCardDocument(
      plan: plan(front: [block('text', 0)]),
      row: row([
        '<script>alert(1)</script>',
        '',
      ]),
    );

    expect(
      document.unsupported,
      isTrue,
      reason: '纯文本渲染会破坏这些结构，宁可整张回原卡',
    );
  });

  test('a plan without blocks produces no document (role extraction wins)',
      () {
    final document = buildCardDocument(
      plan: plan(),
      row: row(['a', 'b']),
    );

    expect(document.front.isEmpty, isTrue);
    expect(document.back.isEmpty, isTrue);
  });
}
