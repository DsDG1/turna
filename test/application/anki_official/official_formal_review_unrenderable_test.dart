// Wave 2 red tests (maintainability plan §6.2-2): render failures are
// structured and visible. A non-empty scheduler queue with zero successful
// renders is Blocked (never "no due"), partial failures stay attached to a
// Ready batch, no implicit answer/bury/suspend happens, and live-queue
// rebuilds surface a newly unrenderable current card instead of swallowing
// it.

import 'package:flutter_test/flutter_test.dart';
import 'package:turna/application/anki/formal_review_launcher.dart';
import 'package:turna/application/anki/official_study_batch_assembler.dart';
import 'package:turna/application/anki/official_formal_review_production_loader.dart';
import 'package:turna/application/anki_official/engine/official_anki_engine_fake.dart';
import 'package:turna/domain/anki/canonical_card_key.dart';
import 'package:turna/application/anki_official/engine/official_anki_review_session.dart';
import 'package:turna/application/anki_official/migration/official_anki_production_router.dart';
import 'package:turna/application/anki_official/official_anki_feature_flags.dart';
import 'package:turna/application/anki_official/review/official_formal_review_coordinator.dart';

const _flags = OfficialAnkiFeatureFlags(
  engine: true,
  import: true,
  catalogReady: true,
  runtimeCapable: true,
  platformReady: true,
  renderer: true,
  scheduler: true,
);

OfficialFormalReviewProductionLoader _loader(
  FakeOfficialAnkiEngine engine, {
  Set<int> cards = const {1, 2},
}) {
  return OfficialFormalReviewProductionLoader(
    flags: _flags,
    engine: engine,
    resolveTarget: (importId) async => OfficialAnkiRoutedSource(
      importId: importId,
      sourceId: importId,
      deckId: 1,
      cardIds: cards,
    ),
    sessionFactory: ({
      required engine,
      required allowedCardIds,
    }) async =>
        OfficialReviewSession(
      engine: engine,
      flags: _flags,
      allowedCardIds: allowedCardIds,
      profileId: 'profile-test',
    ),
    introducedCardIds: (sourceId) => cards,
    activePlacementCardIds: (sourceId) => cards,
    profileId: 'profile-test',
  );
}

void main() {
  late FakeOfficialAnkiEngine engine;

  setUp(() {
    engine = FakeOfficialAnkiEngine();
    engine.seedPackage(packagePath: 'x.apkg', notes: 2, cards: 2);
  });

  test('queue non-empty + every render failing → Blocked, not NoDue', () async {
    engine.failRender = true;
    final result = await _loader(engine).load(importId: 'src-a', courseId: 'c');

    expect(result, isA<OfficialFormalReviewBlocked>(),
        reason: 'the scheduler still owes these cards; empty items must not '
            'masquerade as "no due"');
    final blocked = result as OfficialFormalReviewBlocked;
    expect(blocked.sourceId, 'src-a');
    expect(blocked.schedulerCardCount, 2,
        reason: 'the queue really had cards');
    expect(blocked.failures, hasLength(2));
    expect(blocked.failures.map((f) => f.cardId), {1, 2});
    expect(blocked.failures.first.code, 'renderFailed');
    expect(blocked.failures.first.sourceId, 'src-a');
    expect(blocked.failures.first.stage, isNotNull);
  });

  test('partial render failure → Ready keeps failures for the summary', () async {
    engine.failRenderFor = {2};
    final result = await _loader(engine).load(importId: 'src-a', courseId: 'c');

    expect(result, isA<OfficialFormalReviewReady>());
    final ready = result as OfficialFormalReviewReady;
    expect(ready.batch.items.map((i) => i.cardKey.cardId), {1});
    expect(ready.batch.failures, hasLength(1));
    expect(ready.batch.failures.single.cardId, 2);
    expect(ready.batch.failures.single.recoverable, isNotNull);
  });

  test('Blocked never answers, buries, or suspends anything', () async {
    engine.failRender = true;
    final before = engine.officialAnswers;
    final result = await _loader(engine).load(importId: 'src-a', courseId: 'c');
    expect(result, isA<OfficialFormalReviewBlocked>());

    expect(engine.officialAnswers, before);
    expect(engine.suspended, isEmpty);
    expect(engine.buried, isEmpty);
  });

  test('retry after render recovery enters the same source session', () async {
    engine.failRender = true;
    final first = await _loader(engine).load(importId: 'src-a', courseId: 'c');
    expect(first, isA<OfficialFormalReviewBlocked>());

    engine.failRender = false;
    final second = await _loader(engine).load(importId: 'src-a', courseId: 'c');
    expect(second, isA<OfficialFormalReviewReady>());
    final ready = second as OfficialFormalReviewReady;
    expect(ready.batch.items, isNotEmpty);
    expect(
      ready.batch.items.every((i) => i.cardKey.sourceId == 'src-a'),
      isTrue,
      reason: 'retry keeps the real source identity',
    );
  });

  test('live rebuild with a newly unrenderable current card is surfaced',
      () async {
    // Direct live-queue construction (the loader's restrictAllowedCards
    // keeps failed cards out of the session's allowed set, so mid-session
    // blocks surface through queues that did not restrict — same class,
    // same code path).
    engine.seedPackage(packagePath: 'y.apkg', notes: 3, cards: 3);
    final session = OfficialReviewSession(
      engine: engine,
      flags: _flags,
      allowedCardIds: const {1, 2, 3},
      profileId: 'profile-test',
    );
    await session.openDeck(1);
    final renderer = OfficialFormalReviewRenderer(
      engine: engine,
      profileId: 'profile-test',
    );
    CanonicalCardKey key(int id) => CanonicalCardKey(
          backend: AnkiBackendKind.official,
          profileId: 'profile-test',
          sourceId: 'src-a',
          cardId: id,
        );
    final liveQueue = OfficialFormalReviewLiveQueue(
      session: session,
      sourceId: 'src-a',
      courseId: 'c',
      renderer: renderer,
      assembler: const OfficialStudyBatchAssembler(profileId: 'profile-test'),
      items: [],
      activePlacementCardKeys: {for (final id in const [1, 2, 3]) key(id)},
      introducedCardKeys: {for (final id in const [1, 2, 3]) key(id)},
    );

    // Card 2 cannot render. The first rebuild collects the failure while
    // card 1 stays current and playable.
    engine.failRenderFor = {2};
    var rebuild = await liveQueue.rebuildFromLiveQueue();
    expect(rebuild, isA<OfficialLiveQueueRebuilt>());
    expect(liveQueue.items.map((i) => i.cardKey.cardId), {1, 3});
    expect(liveQueue.renderFailures.map((f) => f.cardId), {2});

    // Answering card 1 makes the scheduler move current onto the card that
    // cannot render — the rebuild must surface the block, keep the items
    // and lock scoring instead of pretending the session completed.
    expect(session.current!.cardId, 1);
    session.showAnswer();
    await session.answerAndConfirm('good', expectedCardId: 1);
    expect(session.current!.cardId, 2,
        reason: 'precondition: the scheduler now owes the unrenderable card');

    rebuild = await liveQueue.rebuildFromLiveQueue();
    expect(rebuild, isA<OfficialLiveQueueBlockedOnCurrentCard>(),
        reason: 'a failing current card must be visible and lock scoring, '
            'not silently dropped from the batch');
    final blocked = rebuild as OfficialLiveQueueBlockedOnCurrentCard;
    expect(blocked.failure.cardId, 2);
    expect(liveQueue.currentBlockedFailure?.cardId, 2);
    expect(liveQueue.items, isNotEmpty,
        reason: 'the previous UI snapshot stays — no empty "complete"');
    expect(engine.officialAnswers, 1,
        reason: 'only the user-confirmed answer happened');

    // Recovery: retry re-renders the SAME card in the SAME session.
    engine.failRenderFor = {};
    final recovered = await liveQueue.retryCurrentCard();
    expect(recovered, isA<OfficialLiveQueueRebuilt>());
    expect(liveQueue.currentBlockedFailure, isNull);
    expect(liveQueue.items, isNotEmpty);
  });

  test('an empty queue is genuinely NoDue', () async {
    // A fresh engine with no seeded cards serves an empty queue.
    final result = await _loader(FakeOfficialAnkiEngine())
        .load(importId: 'src-a', courseId: 'c');
    expect(result, isA<OfficialFormalReviewNoDue>());
  });
}
