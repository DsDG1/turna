import 'package:flutter_test/flutter_test.dart';
import 'package:turna/application/anki_official/contract/official_anki_contract.dart';
import 'package:turna/application/anki_official/contract/official_anki_dto.dart';
import 'package:turna/application/anki_official/contract/official_anki_errors.dart';
import 'package:turna/application/anki_official/engine/official_anki_capabilities.dart';
import 'package:turna/application/anki_official/engine/official_anki_engine_fake.dart';
import 'package:turna/application/anki_official/render/official_anki_render_facade.dart';

void main() {
  // The operations.md alignment and ENGINE_INFO golden assertions moved to
  // official_anki_contract_integrity_test.dart (doc 39 P2).

  test('rendered card DTO ignores unknown fields (camelCase only)', () {
    final card = OfficialAnkiRenderedCard.fromJson({
      'cardId': 9,
      'questionHtml': '[sound:a.mp3]Q',
      'answerHtml': 'A',
      'questionDisplayHtml': 'Q',
      'answerDisplayHtml': 'A',
      'css': '.card{}',
      'latexSvg': false,
      'isEmpty': false,
      'questionAvTags': [
        {'kind': 'sound_or_video', 'filename': 'a.mp3'},
      ],
      'answerAvTags': [
        {'kind': 'tts', 'fieldText': 'hi', 'lang': 'en'},
      ],
      'typedAnswer': {'marker': '[[type:Back]]', 'combining': true},
      'futureField': 'ignore',
    });
    expect(card.cardId, 9);
    expect(card.questionDisplayHtml, 'Q');
    expect(card.questionAvTags.single.filename, 'a.mp3');
    expect(card.answerAvTags.single.fieldText, 'hi');
    expect(card.typedAnswer?.marker, '[[type:Back]]');
    expect(card.templateOrdinal, 0);
    expect(card.bodyClass, 'card card1');

    final withClass = OfficialAnkiRenderedCard.fromJson({
      'cardId': 2,
      'questionHtml': '<img src="hello world.png">',
      'answerHtml': 'A',
      'questionDisplayHtml': '<img src="hello%20world.png">',
      'answerDisplayHtml': 'A',
      'css': 'url(hello world.png)',
      'templateOrdinal': 1,
      'bodyClass': 'card card2',
    });
    expect(withClass.questionHtml, contains('hello world.png'));
    expect(withClass.questionDisplayHtml, contains('hello%20world.png'));
    expect(withClass.questionHtml, isNot(withClass.questionDisplayHtml));
    expect(withClass.templateOrdinal, 1);
    expect(withClass.bodyClass, 'card card2');
    expect(withClass.bodyClass.contains('isWin'), isFalse);

    // Doc 39 P2: the dead snake aliases were deleted — a snake-only payload
    // now decodes to empty strings and id 0 rather than being honored.
    final snake = OfficialAnkiRenderedCard.fromJson({
      'card_id': 3,
      'question_html': 'raw',
      'answer_html': 'rawA',
      'css': '',
    });
    expect(snake.cardId, 0);
    expect(snake.questionHtml, '');
    expect(snake.questionDisplayHtml, '');
  });

  test('facade fail-closes when capability is missing', () async {
    final fake = FakeOfficialAnkiEngine();
    final info = await fake.engineInfo();
    final stripped = OfficialAnkiEngineInfo(
      abiVersion: info.abiVersion,
      backendCommit: info.backendCommit,
      contractMajor: info.contractMajor,
      contractMinor: info.contractMinor,
      capabilities: {'ENGINE_INFO'},
    );
    final facade = OfficialAnkiRenderFacade(info: stripped, engine: fake);
    await expectLater(
      facade.renderCard(cardId: 1),
      throwsA(
        isA<OfficialAnkiException>().having(
          (e) => e.code,
          'code',
          OfficialAnkiErrorCode.capabilityMissing,
        ),
      ),
    );
  });

  test('facade renders through the real engine entry point', () async {
    final fake = FakeOfficialAnkiEngine();
    fake.seedPackage(packagePath: 'x.apkg', notes: 1, cards: 1);
    final facade = OfficialAnkiRenderFacade(
      info: await fake.engineInfo(),
      engine: fake,
    );
    final card = await facade.renderCard(cardId: 1);
    expect(card.cardId, 1);
    expect(card.questionDisplayHtml, isNotEmpty);
    expect(fake.renderCount, 1);
  });

  test('capability helper no longer re-checks major (decode gates it)', () {
    // Doc 39 P2: the major check in OfficialAnkiCapabilities.require and
    // FfiOfficialAnkiEngine._call was deleted — responses with a wrong
    // envelope major already fail closed at OfficialAnkiEnvelopeResponse
    // .fromJson. require() is purely a capability gate now.
    const caps = OfficialAnkiCapabilities(
      OfficialAnkiEngineInfo(
        abiVersion: 1,
        backendCommit: 'x',
        contractMajor: 1,
        contractMinor: 0,
        capabilities: {'RENDER_CARD'},
      ),
    );
    caps.require(OfficialAnkiOperation.renderCard);
  });
}
