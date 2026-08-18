import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:turna/application/anki_official/contract/official_anki_dto.dart';
import 'package:turna/application/anki_official/contract/official_anki_errors.dart';
import 'package:turna/application/anki_official/engine/official_anki_engine_fake.dart';
import 'package:turna/application/anki_official/engine/official_anki_review_session.dart';
import 'package:turna/application/anki_official/engine/official_anki_scheduler_audit.dart';
import 'package:turna/application/anki_official/official_anki_feature_flags.dart';
import 'package:turna/application/anki_official/official_anki_paths.dart';
import 'package:turna/application/anki_official/render/official_anki_av_coordinator.dart';
import 'package:turna/application/anki_official/render/official_anki_media_resolver.dart';
import 'package:turna/application/anki_official/render/official_anki_present_ack.dart';
import 'package:turna/application/anki_official/render/official_anki_render_facade.dart';
import 'package:turna/application/anki_official/render/official_anki_render_state.dart';
import 'package:turna/application/anki_official/render/official_anki_typed_answer_controller.dart';
import 'package:turna/views/anki_official/official_anki_review_page.dart';

import 'official_anki_reviewer_behavior_test.dart';

const _flags = OfficialAnkiFeatureFlags(
  engine: true,
  import: true,
  catalogReady: true,
  runtimeCapable: true,
  platformReady: true,
  renderer: true,
  scheduler: true,
);

Future<OfficialAnkiReviewerController> officialFormalReviewPresenter(
  FakeOfficialAnkiEngine fake,
) async {
  final facade = OfficialAnkiRenderFacade(
    info: await fake.engineInfo(),
    engine: fake,
  );
  final root = Directory.systemTemp.createTempSync('turna-formal-presenter-');
  addTearDown(() {
    if (root.existsSync()) {
      root.deleteSync(recursive: true);
    }
  });
  return OfficialAnkiReviewerController(
    facade: facade,
    av: OfficialAnkiAvCoordinator(
      resolver: OfficialAnkiMediaResolver(root),
      player: RecordingOfficialAnkiAvPlayer(),
    ),
    typed: OfficialAnkiTypedAnswerController(facade),
  );
}

void main() {
  Future<_Harness> mount(WidgetTester tester, {FakeOfficialAnkiEngine? engine}) async {
    OfficialAnkiSchedulerAudit.reset();
    final fake = engine ?? FakeOfficialAnkiEngine();
    if (engine == null) {
      fake.seedPackage(packagePath: 'x.apkg', notes: 2, cards: 2);
    }
    final session = OfficialReviewSession(engine: fake, flags: _flags);
    await session.openDeck(1);
    final paths = OfficialAnkiPaths(
      profileId: 'profile-formal-ack',
      profileRoot: Directory.systemTemp.createTempSync('turna-formal-ack-'),
    );
    addTearDown(() {
      if (paths.profileRoot.existsSync()) {
        paths.profileRoot.deleteSync(recursive: true);
      }
    });
    final presenter = await officialFormalReviewPresenter(fake);
    addTearDown(presenter.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: OfficialAnkiReviewPage(
          engine: fake,
          paths: paths,
          flags: _flags,
          session: session,
          presenter: presenter,
        ),
      ),
    );
    await tester.pump();
    return _Harness(fake: fake, session: session, presenter: presenter);
  }

  OfficialPresentAck ack(
    OfficialAnkiReviewerController presenter, {
    required String side,
    bool ok = true,
    String? code,
    int? cardId,
    int? generation,
  }) {
    return OfficialPresentAck(
      cardId: cardId ?? presenter.presentedCardId,
      generation: generation ?? presenter.presentGeneration,
      side: side,
      ok: ok,
      code: code,
    );
  }

  testWidgets('formal_review_does_not_enable_rating_before_answer_present_ack',
      (tester) async {
    final harness = await mount(tester);
    expect(find.byType(AppBar), findsOneWidget);
    expect(find.text('官方卡片预览'), findsNothing);
    expect(find.text('显示答案'), findsNothing);
    expect(find.byKey(const Key('official-review-show-answer')), findsOneWidget);
    expect(find.byKey(const Key('official-review-good')), findsNothing);

    harness.presenter.acceptPresent(ack(harness.presenter, side: 'question'));
    await tester.pump();
    await tester.tap(find.byKey(const Key('official-review-show-answer')));
    await tester.pump();
    expect(harness.session.phase, OfficialReviewPhase.showingQuestion);
    expect(harness.session.answerVisibleElapsed.isRunning, isFalse);
    expect(find.byKey(const Key('official-review-good')), findsNothing);
    expect(OfficialAnkiSchedulerAudit.officialSchedulerAnswers, 0);

    await tester.tap(find.byKey(const Key('official-review-show-answer')));
    await tester.pump();
    expect(find.byKey(const Key('official-review-good')), findsNothing);
  });

  testWidgets('formal_review_render_timeout_never_writes_scheduler',
      (tester) async {
    final harness = await mount(tester);
    harness.presenter.acceptPresent(ack(harness.presenter, side: 'question'));
    await tester.pump();
    await tester.tap(find.byKey(const Key('official-review-show-answer')));
    await tester.pump();
    harness.presenter.acceptPresent(
      ack(
        harness.presenter,
        side: 'answer',
        ok: false,
        code: 'RENDER_TIMEOUT',
      ),
    );
    await tester.pump();
    expect(find.byKey(const Key('official-review-good')), findsNothing);
    expect(find.byKey(const Key('official-review-render-error')), findsWidgets);
    expect(harness.session.phase, OfficialReviewPhase.showingQuestion);
    expect(OfficialAnkiSchedulerAudit.officialSchedulerAnswers, 0);
    expect(find.byType(AppBar), findsOneWidget);
  });

  testWidgets('formal_review_stale_ack_cannot_unlock_next_card', (tester) async {
    final harness = await mount(tester);
    harness.presenter.acceptPresent(ack(harness.presenter, side: 'question'));
    await tester.pump();
    await tester.tap(find.byKey(const Key('official-review-show-answer')));
    await tester.pump();
    final liveGeneration = harness.presenter.presentGeneration;
    final liveCardId = harness.presenter.presentedCardId;
    expect(
      harness.presenter.acceptPresent(
        ack(
          harness.presenter,
          side: 'answer',
          generation: liveGeneration - 1,
        ),
      ),
      isNull,
    );
    expect(
      harness.presenter.acceptPresent(
        ack(harness.presenter, side: 'answer', cardId: liveCardId + 99),
      ),
      isNull,
    );
    await tester.pump();
    expect(find.byKey(const Key('official-review-good')), findsNothing);
    expect(harness.session.phase, OfficialReviewPhase.showingQuestion);

    harness.presenter.acceptPresent(
      ack(harness.presenter, side: 'answer', generation: liveGeneration),
    );
    await tester.pump();
    expect(find.byKey(const Key('official-review-good')), findsOneWidget);
    expect(harness.session.phase, OfficialReviewPhase.showingAnswer);
  });

  testWidgets('formal_review_elapsed_starts_only_after_answer_present_ack',
      (tester) async {
    final harness = await mount(tester);
    harness.presenter.acceptPresent(ack(harness.presenter, side: 'question'));
    await tester.pump();
    await tester.tap(find.byKey(const Key('official-review-show-answer')));
    await tester.pump();
    expect(harness.session.answerVisibleElapsed.isRunning, isFalse);
    expect(harness.session.phase, OfficialReviewPhase.showingQuestion);

    harness.presenter.acceptPresent(ack(harness.presenter, side: 'answer'));
    await tester.pump();
    expect(harness.session.answerVisibleElapsed.isRunning, isTrue);
    expect(find.byKey(const Key('official-review-good')), findsOneWidget);
    await tester.tap(find.byKey(const Key('official-review-good')));
    await tester.pump();
    await tester.pump();
    expect(harness.fake.lastMillisecondsTaken, greaterThanOrEqualTo(0));
    expect(OfficialAnkiSchedulerAudit.officialSchedulerAnswers, 1);
    expect(find.byType(AppBar), findsOneWidget);
    expect(find.text('显示答案'), findsNothing);
  });

  testWidgets('formal_review_queue_error_is_not_congrats', (tester) async {
    OfficialAnkiSchedulerAudit.reset();
    final fake = _FailQueueEngine();
    fake.seedPackage(packagePath: 'x.apkg', notes: 1, cards: 1);
    final session = OfficialReviewSession(engine: fake, flags: _flags);
    final paths = OfficialAnkiPaths(
      profileId: 'profile-formal-error',
      profileRoot: Directory.systemTemp.createTempSync('turna-formal-error-'),
    );
    addTearDown(() {
      if (paths.profileRoot.existsSync()) {
        paths.profileRoot.deleteSync(recursive: true);
      }
    });
    final presenter = await officialFormalReviewPresenter(fake);
    addTearDown(presenter.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: OfficialAnkiReviewPage(
          engine: fake,
          paths: paths,
          flags: _flags,
          session: session,
          presenter: presenter,
        ),
      ),
    );
    await tester.pump();
    expect(find.byKey(const Key('official-review-congrats')), findsNothing);
    expect(find.byKey(const Key('official-review-retry')), findsOneWidget);
    expect(find.byKey(const Key('official-review-good')), findsNothing);
  });

  testWidgets('unrenderable_card_does_not_call_bury', (tester) async {
    final harness = await mount(tester);
    harness.presenter.acceptPresent(ack(harness.presenter, side: 'question'));
    await tester.pump();
    harness.presenter.onRenderFailure(
      code: 'UNRENDERABLE_CARD',
      side: 'question',
      generation: harness.presenter.presentGeneration,
    );
    await tester.pump();
    expect(harness.presenter.ui.offersRetryCurrentSide, isFalse);
    expect(find.byKey(const Key('official-review-good')), findsNothing);
    expect(find.byKey(const Key('official-review-show-answer')), findsOneWidget);
    final show = tester.widget<FilledButton>(
      find.byKey(const Key('official-review-show-answer')),
    );
    expect(show.onPressed, isNull);
    expect(harness.fake.buried, isEmpty);
    expect(OfficialAnkiSchedulerAudit.officialSchedulerBurySuspend, 0);
    expect(OfficialAnkiSchedulerAudit.officialSchedulerAnswers, 0);
  });

  testWidgets('fatal_code_disables_rating_and_keeps_webview', (tester) async {
    final harness = await mount(tester);
    harness.presenter.acceptPresent(ack(harness.presenter, side: 'question'));
    await tester.pump();
    await tester.tap(find.byKey(const Key('official-review-show-answer')));
    await tester.pump();
    harness.presenter.onRenderFailure(
      code: 'UNRENDERABLE_TEMPLATE',
      side: 'answer',
      generation: harness.presenter.presentGeneration,
    );
    await tester.pump();
    expect(find.byKey(const Key('official-review-stage')), findsOneWidget);
    expect(find.byKey(const Key('official-review-good')), findsNothing);
    expect(harness.fake.buried, isEmpty);
  });
}

class _Harness {
  const _Harness({
    required this.fake,
    required this.session,
    required this.presenter,
  });

  final FakeOfficialAnkiEngine fake;
  final OfficialReviewSession session;
  final OfficialAnkiReviewerController presenter;
}

class _FailQueueEngine extends FakeOfficialAnkiEngine {
  @override
  Future<OfficialReviewQueue> getReviewQueue({int fetchLimit = 1}) async {
    throw const OfficialAnkiException(
      code: OfficialAnkiErrorCode.internalError,
      messageKey: 'official_anki.internal_error',
      recoverable: true,
    );
  }
}
