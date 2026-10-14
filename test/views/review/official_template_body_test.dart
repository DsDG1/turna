import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:turna/application/anki_official/contract/official_anki_dto.dart';
import 'package:turna/application/anki_official/engine/official_anki_engine_fake.dart';
import 'package:turna/application/anki_official/official_anki_feature_flags.dart';
import 'package:turna/application/anki_official/official_anki_paths.dart';
import 'package:turna/application/anki_official/render/official_anki_av_coordinator.dart';
import 'package:turna/application/anki_official/render/official_anki_media_resolver.dart';
import 'package:turna/application/anki_official/render/official_anki_present_ack.dart';
import 'package:turna/application/anki_official/render/official_anki_render_facade.dart';
import 'package:turna/application/anki_official/render/official_anki_render_state.dart';
import 'package:turna/application/anki_official/render/official_anki_typed_answer_controller.dart';
import 'package:turna/domain/anki/canonical_card_key.dart';
import 'package:turna/domain/anki/card_presentation.dart';
import 'package:turna/domain/anki/presentation_receipt.dart';
import 'package:turna/domain/review/review_item.dart';
import 'package:turna/views/anki_official/official_anki_canonical_card_view.dart';
import 'package:turna/views/anki_official/official_anki_reviewer_view.dart';
import 'package:turna/views/anki_official/official_anki_reviewer_stage.dart';
import 'package:turna/views/review/components/official_template_webview_body.dart';

void main() {
  late FakeOfficialAnkiEngine engine;
  late OfficialAnkiReviewerController controller;
  late OfficialAnkiPaths paths;
  late OfficialAnkiFeatureFlags savedFlags;
  const presentation = FidelityCardPresentation(
    cardKey: CanonicalCardKey(
        backend: AnkiBackendKind.official,
        profileId: 'profile-default-01',
        sourceId: 'source-test',
        cardId: 1),
    templateRef: CanonicalTemplateRef(notetypeId: 1, ordinal: 0),
    sourceFingerprint: 'original',
  );

  setUp(() async {
    savedFlags = OfficialAnkiFeatureFlags.current;
    OfficialAnkiFeatureFlags.current =
        OfficialAnkiFeatureFlags.productionAndroid;
    engine = FakeOfficialAnkiEngine()
      ..seedPackage(packagePath: 'x.apkg', notes: 2, cards: 2);
    paths = OfficialAnkiPaths(
        profileId: 'profile-default-01',
        profileRoot:
            Directory.systemTemp.createTempSync('turna-official-body-'));
    final facade = OfficialAnkiRenderFacade(
        info: await engine.engineInfo(), engine: engine);
    controller = OfficialAnkiReviewerController(
        facade: facade,
        av: OfficialAnkiAvCoordinator(
            resolver: OfficialAnkiMediaResolver(paths.mediaFolder),
            player: _SilentAv()),
        typed: OfficialAnkiTypedAnswerController(facade));
  });
  tearDown(() async {
    await controller.dispose();
    paths.profileRoot.deleteSync(recursive: true);
    OfficialAnkiFeatureFlags.current = savedFlags;
  });

  Widget body(List<PresentationReceipt> receipts,
          {bool answer = false, int generation = 7}) =>
      MaterialApp(
          home: Scaffold(
              body: OfficialTemplateWebViewBody(
        presentation: presentation,
        content: const OfficialTemplateContent(
            frontHtml: 'projection', backHtml: 'projection'),
        isRevealed: answer,
        onReveal: () {},
        generation: generation,
        onPresented: receipts.add,
        controller: controller,
        paths: paths,
      )));

  Future<void> settleBoot(WidgetTester tester) async {
    await tester.pump();
    await tester.pump();
    await tester.pump();
  }

  void nativeAck(WidgetTester tester,
      {String side = 'question', int? generation}) {
    final view = tester.widget<OfficialAnkiReviewerView>(
        find.byType(OfficialAnkiReviewerView));
    view.onRenderComplete!(OfficialAnkiPresentResult(
        ok: true,
        generation: generation ?? controller.presentGeneration,
        side: side));
  }

  testWidgets('the script off-switch creates no native WebView or success ACK',
      (tester) async {
    await controller.loadAndShowQuestion(1);
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(
            body: OfficialAnkiReviewerStage(
      controller: controller,
      paths: paths,
      sourceId: 'source-test',
      allowJs: false,
    ))));
    await tester.pump();
    expect(find.byType(OfficialAnkiReviewerView), findsNothing);
    expect(controller.lastAck?.ok, isFalse);
    expect(controller.hasQuestionPresentAck, isFalse);
  });

  testWidgets(
      'formal review reuses full engine payload and waits for matching native ACKs',
      (tester) async {
    engine.renders[1] = const OfficialAnkiRenderedCard(
        cardId: 1,
        questionHtml: '<b>question</b>',
        answerHtml: '<b>answer</b>',
        questionDisplayHtml: '<b>question</b>',
        answerDisplayHtml: '<b>answer</b>',
        css: '.card {color:red}',
        templateOrdinal: 2,
        bodyClass: 'card card3');
    final receipts = <PresentationReceipt>[];
    await tester.pumpWidget(body(receipts));
    await settleBoot(tester);
    final view = tester.widget<OfficialAnkiReviewerView>(
        find.byType(OfficialAnkiReviewerView));
    expect(view.card, same(engine.renders[1]));
    expect(view.mediaRoot, paths.mediaFolder.path);
    expect(receipts.where((r) => r.ok), isEmpty);
    nativeAck(tester);
    await tester.pump();
    expect(receipts.where((r) => r.ok).single.side, PresentationSide.question);
    await tester.pumpWidget(body(receipts, answer: true));
    await settleBoot(tester);
    expect(receipts.where((r) => r.ok && r.side == PresentationSide.answer),
        isEmpty);
    nativeAck(tester, side: 'question');
    nativeAck(tester,
        side: 'answer', generation: controller.presentGeneration - 1);
    await tester.pump();
    expect(receipts.where((r) => r.ok && r.side == PresentationSide.answer),
        isEmpty);
    nativeAck(tester, side: 'answer');
    await tester.pump();
    final answer =
        receipts.where((r) => r.ok && r.side == PresentationSide.answer).single;
    expect(answer.generation, 7);
    expect(answer.renderer, PresentationRendererKind.officialTemplate);
  });

  testWidgets(
      'an ACK queued before a new study generation cannot acknowledge it',
      (tester) async {
    final receipts = <PresentationReceipt>[];
    await tester.pumpWidget(body(receipts));
    await settleBoot(tester);
    nativeAck(tester);
    await tester.pumpWidget(body(receipts, generation: 8));
    await settleBoot(tester);
    expect(receipts.where((r) => r.ok && r.generation == 8), isEmpty);
    expect(controller.phase, isNot(OfficialAnkiReviewerPhase.disposed));
  });

  testWidgets(
      'course completion requires answer ACK and resets when the card changes',
      (tester) async {
    Widget card(int id) => MaterialApp(
        home: Scaffold(
            body: OfficialAnkiCanonicalCardView(
                contextToken: 'official-canonical-link:source-test:$id',
                controller: controller,
                paths: paths)));
    await tester.pumpWidget(card(1));
    await settleBoot(tester);
    await controller.showAnswer(autoplay: false);
    await settleBoot(tester);
    FilledButton continueButton() => tester.widget<FilledButton>(
        find.byKey(const Key('official-canonical-continue')));
    expect(continueButton().onPressed, isNull);
    nativeAck(tester, side: 'answer');
    await tester.pump();
    expect(continueButton().onPressed, isNotNull);
    await tester.pumpWidget(card(2));
    await settleBoot(tester);
    expect(controller.presentedCardId, 2);
    expect(continueButton().onPressed, isNull);
  });
}

class _SilentAv implements OfficialAnkiAvPlayer {
  @override
  Future<void> playFile(String path) async {}
  @override
  Future<bool> speak(
          {required String text,
          String? lang,
          List<String> voices = const [],
          double? speed,
          List<String> otherArgs = const []}) async =>
      true;
  @override
  Future<void> stop() async {}
  @override
  Future<void> dispose() async {}
}
