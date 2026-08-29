import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:turna/application/anki_official/contract/official_anki_contract.dart';
import 'package:turna/application/anki_official/contract/official_anki_dto.dart';
import 'package:turna/application/anki_official/contract/official_anki_errors.dart';
import 'package:turna/application/anki_official/engine/official_anki_capabilities.dart';
import 'package:turna/application/anki_official/engine/official_anki_engine_fake.dart';
import 'package:turna/application/anki_official/render/official_anki_render_facade.dart';

void main() {
  test('operation name and id stay aligned with operations.md', () {
    final doc = File('native/turna_anki_core/contract/operations.md').readAsStringSync();
    expect(OfficialAnkiOperation.idFor(OfficialAnkiOperation.renderCard), 10);
    expect(OfficialAnkiOperation.idFor(OfficialAnkiOperation.compareTypedAnswer), 22);
    expect(OfficialAnkiOperation.idFor(OfficialAnkiOperation.extractClozeForTyping), 23);
    expect(kOfficialAnkiContractMinor, 9);
    for (final name in OfficialAnkiOperation.productionNames) {
      expect(doc.contains('| ${OfficialAnkiOperation.idFor(name)} | $name |'), isTrue);
    }
  });

  test('rendered card DTO ignores unknown fields and reads both names', () {
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

    final snake = OfficialAnkiRenderedCard.fromJson({
      'card_id': 3,
      'question_html': 'raw',
      'answer_html': 'rawA',
      'question_text_without_av': 'disp',
      'answer_text_without_av': 'dispA',
      'css': '',
    });
    expect(snake.cardId, 3);
    expect(snake.questionDisplayHtml, 'disp');
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

  test('capability helper rejects old contract major', () {
    const caps = OfficialAnkiCapabilities(
      OfficialAnkiEngineInfo(
        abiVersion: 1,
        backendCommit: 'x',
        contractMajor: 2,
        contractMinor: 0,
        capabilities: {'RENDER_CARD'},
      ),
    );
    expect(
      () => caps.require(OfficialAnkiOperation.renderCard),
      throwsA(
        isA<OfficialAnkiException>().having(
          (e) => e.code,
          'code',
          OfficialAnkiErrorCode.contractVersionMismatch,
        ),
      ),
    );
  });

  test('ENGINE_INFO golden lists render capabilities', () {
    final jsonText = File(
      'native/turna_anki_core/contract/fixtures/response_engine_info.json',
    ).readAsStringSync();
    final decoded = jsonDecode(jsonText) as Map<String, dynamic>;
    final caps = (decoded['payload'] as Map)['capabilities'] as List;
    expect(caps, contains('RENDER_CARD'));
    expect(caps, contains('COMPARE_TYPED_ANSWER'));
    expect(caps, contains('EXTRACT_CLOZE_FOR_TYPING'));
    expect((decoded['payload'] as Map)['contractMinor'], 9);
    expect(caps, contains('GET_PROJECTION_SCHEMAS'));
  });
}
