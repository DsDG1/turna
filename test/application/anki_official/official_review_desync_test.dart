// Regression tests for the second-card "当前卡片无法安全写入" desync:
// the live queue REPLACES the session's items list after every commit (P3:
// never mutates a shared list in place), so advancing by index+1 would
// skip the scheduler's refreshed current and the next answer would hit
// schedulingContextStale. Advancement must follow
// OfficialReviewSession.current — these tests drive the full controller +
// ledger + live-queue pipeline the page wires in production.

import 'package:flutter_test/flutter_test.dart';
import 'package:turna/application/anki_official/review/official_study_batch_assembler.dart';
import 'package:turna/application/anki_official/contract/official_anki_dto.dart';
import 'package:turna/application/anki_official/engine/official_anki_engine_fake.dart';
import 'package:turna/application/anki_official/engine/official_anki_review_session.dart';
import 'package:turna/application/anki_official/official_anki_feature_flags.dart';
import 'package:turna/application/anki_official/review/official_formal_review_coordinator.dart';
import 'package:turna/application/study_session/anki_study_session_host.dart';
import 'package:turna/application/study_session/study_ledger_adapters.dart';
import 'package:turna/application/study_session/study_session_controller.dart';
import 'package:turna/domain/anki/canonical_card_key.dart';
import 'package:turna/domain/anki/study_models.dart';
import 'package:turna/domain/review/official_anki_review_ledger.dart';
import 'package:turna/domain/review/recall_outcome.dart';

const _flags = OfficialAnkiFeatureFlags(
  engine: true,
  import: true,
  catalogReady: true,
  runtimeCapable: true,
  platformReady: true,
  renderer: true,
  scheduler: true,
);

CanonicalCardKey _key(int cardId) => CanonicalCardKey(
      backend: AnkiBackendKind.official,
      profileId: 'profile-test',
      sourceId: 'src-a',
      cardId: cardId,
    );

/// Models the scheduler's learning step reinsertion: an `again` answer
/// keeps the card owed (it rejoins the queue) instead of finishing it.
class _LearningReinsertEngine extends FakeOfficialAnkiEngine {
  @override
  Future<OfficialAnswerResult> answerCard({
    required String sessionId,
    required int queueEpoch,
    required String answerToken,
    required int cardId,
    required String rating,
    required int millisecondsTaken,
    int? answeredAtMillis,
    String? clientMutationId,
  }) async {
    final result = await super.answerCard(
      sessionId: sessionId,
      queueEpoch: queueEpoch,
      answerToken: answerToken,
      cardId: cardId,
      rating: rating,
      millisecondsTaken: millisecondsTaken,
      answeredAtMillis: answeredAtMillis,
      clientMutationId: clientMutationId,
    );
    if (rating == 'again' && result.committed) {
      answeredIds.remove(cardId);
    }
    return result;
  }
}

/// Wires the production pipeline: real session + real ledger + live queue
/// + shared-host controller, with onEffects rebuilding the batch exactly
/// like AnkiReviewSessionPage does.
class _Harness {
  _Harness(this.engine)
      : session = OfficialReviewSession(
          engine: engine,
          flags: _flags,
          allowedCardIds: const {1, 2, 3},
          profileId: 'profile-test',
        );

  final FakeOfficialAnkiEngine engine;
  final OfficialReviewSession session;
  late final OfficialFormalReviewLiveQueue queue;
  late final StudySessionController controller;

  Future<void> start() async {
    await session.openDeck(1);
    final officialLedger = OfficialStudyLedger(
      OfficialAnkiReviewLedger(session),
    );
    // The loader's shape: the queue owns the initial batch (its own copy,
    // populated by a first rebuild), the controller snapshots it, and only
    // then does the page bind the replacement sink.
    queue = OfficialFormalReviewLiveQueue(
      session: session,
      sourceId: 'src-a',
      courseId: 'course-a',
      renderer: OfficialFormalReviewRenderer(
        engine: engine,
        profileId: 'profile-test',
      ),
      assembler: const OfficialStudyBatchAssembler(profileId: 'profile-test'),
      items: const [],
      activePlacementCardKeys: {for (final id in [1, 2, 3]) _key(id)},
    );
    await queue.rebuildFromLiveQueue();
    final host = AnkiStudySessionHost(
      resolver: StudyLedgerResolver(official: officialLedger),
      onEffects: (item, receipt) => queue.rebuildFromLiveQueue(),
      onEffectsUndone: (receipt) => queue.rebuildFromLiveQueue(),
    );
    controller = host.openOfficialReview(
      queue.items,
      officialLedger: officialLedger,
    );
    // Mirrors AnkiReviewSessionPage: the queue pushes rebuilt batches into
    // the controller by replacement.
    queue.itemsSink = controller.replaceItems;
    await controller.start();
  }

  /// Mirrors AnkiReviewSessionPage: reveal → session.showAnswer → rate.
  Future<void> rateCurrent(RecallOutcome outcome) async {
    AnkiStudySessionHost.presentBothSides(controller);
    await AnkiStudySessionHost.revealAndPresentAnswer(
      controller,
      onOfficialShowAnswer: session.showAnswer,
    );
    await controller.submitRecall(outcome);
  }

  /// Mirrors AnkiReviewSessionPage._advanceFromScheduler: the next card is
  /// the scheduler's current after the rebuild, never index+1; a miss is a
  /// structured desync.
  Future<void> advanceFromScheduler() async {
    final currentCardId = session.current?.cardId;
    if (currentCardId == null) {
      await controller.advanceTo(null);
      return;
    }
    for (final item in controller.items) {
      if (item.cardKey.cardId == currentCardId) {
        await controller.advanceTo(item.sessionItemId);
        return;
      }
    }
    controller.reportSchedulerDesync(currentCardId);
  }

  void expectSyncedWithScheduler() {
    expect(
      controller.currentItem!.cardKey.cardId,
      session.current!.cardId,
      reason: 'the shown card must always be the scheduler current',
    );
  }
}

void main() {
  test('second card commits after the first leaves the queue', () async {
    final h = _Harness(FakeOfficialAnkiEngine());
    h.engine.seedPackage(packagePath: 'x.apkg', notes: 3, cards: 3);
    await h.start();
    h.expectSyncedWithScheduler();

    // Card 1 answered good leaves the queue: the rebuilt batch shrinks to
    // [2, 3] and index+1 would land on card 3 while the scheduler owes 2.
    await h.rateCurrent(RecallOutcome.remembered);
    expect(h.controller.phase, StudyCardPhase.readyForNext);
    expect(h.engine.answeredIds, {1});
    await h.advanceFromScheduler();
    h.expectSyncedWithScheduler();

    await h.rateCurrent(RecallOutcome.remembered);
    expect(
      h.controller.phase,
      StudyCardPhase.readyForNext,
      reason: 'the second commit must not hit schedulingContextStale',
    );
    expect(h.engine.answeredIds, {1, 2});
    await h.advanceFromScheduler();
    h.expectSyncedWithScheduler();
  });

  test('again reinsertion keeps the card owed and later commits still '
      'follow the queue', () async {
    final h = _Harness(_LearningReinsertEngine());
    h.engine.seedPackage(packagePath: 'x.apkg', notes: 3, cards: 3);
    await h.start();

    await h.rateCurrent(RecallOutcome.forgotten);
    expect(h.controller.phase, StudyCardPhase.readyForNext);
    await h.advanceFromScheduler();
    h.expectSyncedWithScheduler();
    // The fake queue sorts by cardId, so the reinserted card 1 is current
    // again immediately — the real scheduler would place it at its new due
    // position. Either way the shown card must equal session.current.

    await h.rateCurrent(RecallOutcome.remembered);
    expect(h.controller.phase, StudyCardPhase.readyForNext);
    await h.advanceFromScheduler();
    h.expectSyncedWithScheduler();

    await h.rateCurrent(RecallOutcome.remembered);
    expect(h.controller.phase, StudyCardPhase.readyForNext);
    expect(h.engine.answeredIds, {1, 2});
  });

  test('bury via the onMutated hook rebuilds and advances to the scheduler '
      'current', () async {
    final h = _Harness(FakeOfficialAnkiEngine());
    h.engine.seedPackage(packagePath: 'x.apkg', notes: 3, cards: 3);
    await h.start();

    final ok = await h.controller.buryCurrent(
      onMutated: () => h.queue.rebuildFromLiveQueue(),
    );
    expect(ok, isTrue);
    expect(h.controller.phase, StudyCardPhase.readyForNext);
    await h.advanceFromScheduler();
    h.expectSyncedWithScheduler();

    await h.rateCurrent(RecallOutcome.remembered);
    expect(h.controller.phase, StudyCardPhase.readyForNext);
    expect(h.engine.buried, contains(1));
  });

  test('suspending the last owed card completes the session', () async {
    final h = _Harness(FakeOfficialAnkiEngine());
    h.engine.seedPackage(packagePath: 'x.apkg', notes: 3, cards: 3);
    await h.start();

    for (var i = 0; i < 2; i++) {
      await h.rateCurrent(RecallOutcome.remembered);
      await h.advanceFromScheduler();
    }

    final ok = await h.controller.suspendCurrent(
      onMutated: () => h.queue.rebuildFromLiveQueue(),
    );
    expect(ok, isTrue);
    expect(h.session.current, isNull);
    await h.advanceFromScheduler();
    expect(h.controller.isComplete, isTrue);
  });

  test('P3: rebuilds replace the controller items instead of mutating them',
      () async {
    final h = _Harness(FakeOfficialAnkiEngine());
    h.engine.seedPackage(packagePath: 'x.apkg', notes: 3, cards: 3);
    await h.start();
    final initialItems = h.controller.items;
    final initialIds = initialItems.map((i) => i.cardKey.cardId).toList();

    await h.rateCurrent(RecallOutcome.remembered);
    await pumpEventQueue();

    expect(identical(h.controller.items, initialItems), isFalse,
        reason: 'the rebuild hands the controller a NEW list — the shared-'
            'mutation contract is retired');
    expect(initialItems.map((i) => i.cardKey.cardId), initialIds,
        reason: 'the list the page originally held is untouched — nothing '
            'mutates a list it does not own');
    expect(h.controller.items.map((i) => i.cardKey.cardId), [2, 3]);
    expect(h.queue.items.map((i) => i.cardKey.cardId), [2, 3]);
  });

  test('P3: controller items are unmodifiable', () async {
    final h = _Harness(FakeOfficialAnkiEngine());
    h.engine.seedPackage(packagePath: 'x.apkg', notes: 3, cards: 3);
    await h.start();

    expect(
      () => h.controller.items.add(h.controller.items.first),
      throwsUnsupportedError,
      reason: 'in-place mutation was the retired desync vector',
    );
  });

  test('P3: reportSchedulerDesync surfaces a retryable desync state',
      () async {
    final h = _Harness(FakeOfficialAnkiEngine());
    h.engine.seedPackage(packagePath: 'x.apkg', notes: 3, cards: 3);
    await h.start();
    AnkiStudySessionHost.presentBothSides(h.controller);
    await AnkiStudySessionHost.revealAndPresentAnswer(
      h.controller,
      onOfficialShowAnswer: h.session.showAnswer,
    );
    await h.controller.submitRecall(RecallOutcome.remembered);
    expect(h.controller.phase, StudyCardPhase.readyForNext);

    // The scheduler owes a card the assembled batch does not hold.
    h.controller.reportSchedulerDesync(999);

    expect(h.controller.phase, StudyCardPhase.recoverableError);
    expect(h.controller.lastError, isA<StateError>());
    expect(
      (h.controller.lastError as StateError).message,
      contains('999'),
      reason: 'the fake missing-card-id sentinel is retired; the desync is '
          'reported through an explicit API',
    );
  });
}
