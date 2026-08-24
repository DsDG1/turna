// Official formal-review fidelity tests (plan 34 R2-1 / OS-11): rendered
// HTML with markup must become FidelityCardPresentation — stripping rich
// HTML into a flip card is not an accepted downgrade. Plain-text cards
// stay flip. Typed answers and CSS ride along with the fidelity face.

import 'package:flutter_test/flutter_test.dart';
import 'package:turna/application/anki_official/contract/official_anki_dto.dart';
import 'package:turna/application/anki_official/engine/official_anki_engine_fake.dart';
import 'package:turna/application/anki_official/review/official_formal_review_coordinator.dart';
import 'package:turna/domain/anki/canonical_card_key.dart';
import 'package:turna/domain/anki/card_presentation.dart';

void main() {
  late FakeOfficialAnkiEngine engine;

  setUp(() {
    engine = FakeOfficialAnkiEngine();
    engine.seedPackage(packagePath: 'x.apkg', notes: 3, cards: 3);
  });

  OfficialAnkiRenderedCard rendered(
    int cardId, {
    String questionHtml = '',
    String answerHtml = '',
  }) {
    return OfficialAnkiRenderedCard(
      cardId: cardId,
      questionHtml: questionHtml,
      answerHtml: answerHtml,
      questionDisplayHtml: questionHtml,
      answerDisplayHtml: answerHtml,
      css: '.card { color: red; }',
      templateOrdinal: 2,
      bodyClass: 'card card1',
    );
  }

  test('HTML markup becomes FidelityCardPresentation, never a stripped flip',
      () async {
    engine.renders[1] = rendered(
      1,
      questionHtml: '<div>Merhaba <b>dünya</b></div>',
      answerHtml: '<div>hello <i>world</i></div>',
    );
    final renderer = OfficialFormalReviewRenderer(engine: engine);

    final face = await renderer.render(sourceId: 'src-a', cardId: 1);

    expect(face.presentation, isA<FidelityCardPresentation>());
    expect(face.htmlCard.frontHtml, contains('<b>dünya</b>'));
    expect(face.htmlCard.backHtml, contains('<i>world</i>'));
    expect(face.htmlCard.css, '.card { color: red; }');
    final fidelity = face.presentation as FidelityCardPresentation;
    expect(fidelity.templateRef.ordinal, 2);
    expect(fidelity.cardKey.cardId, 1);
  });

  test('cloze/MathJax/entity markers also require the fidelity surface',
      () async {
    engine.renders[1] = rendered(1, questionHtml: '{{c1::osman}}');
    engine.renders[2] = rendered(2, questionHtml: r'\(\sqrt{2}\)');
    engine.renders[3] = rendered(3, questionHtml: 'café &amp; crème');
    final renderer = OfficialFormalReviewRenderer(engine: engine);

    for (final cardId in [1, 2, 3]) {
      final face = await renderer.render(sourceId: 'src-a', cardId: cardId);
      expect(face.presentation, isA<FidelityCardPresentation>(),
          reason: 'card $cardId carries markup and must not be stripped');
    }
  });

  test('genuinely plain text stays a flip card', () async {
    engine.renders[1] =
        rendered(1, questionHtml: 'plain question', answerHtml: 'plain answer');
    final renderer = OfficialFormalReviewRenderer(engine: engine);

    final face = await renderer.render(sourceId: 'src-a', cardId: 1);

    expect(face.presentation, isA<FlipCardPresentation>());
    final flip = face.presentation as FlipCardPresentation;
    expect(flip.frontText, 'plain question');
    expect(flip.backText, 'plain answer');
  });

  test('the cardKey is canonical (official backend, source, card)', () async {
    final renderer = OfficialFormalReviewRenderer(engine: engine);
    final face = await renderer.render(
      sourceId: 'src-4f8b2c9d1e',
      cardId: 1,
    );
    expect(
      face.presentation.cardKey,
      const CanonicalCardKey(
        backend: AnkiBackendKind.official,
        profileId: '',
        sourceId: 'src-4f8b2c9d1e',
        cardId: 1,
      ),
    );
  });
}
