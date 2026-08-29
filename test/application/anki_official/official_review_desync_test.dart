// Regression tests for the second-card "当前卡片无法安全写入" desync:
// the live queue rebuilds the shared items list in place after every
// commit, so advancing by index+1 skipped the scheduler's refreshed
// current and the next answer hit schedulingContextStale. Advancement
// must follow OfficialReviewSession.current — these tests drive the full
// controller + ledger + live-queue pipeline the page wires in production.

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
    final items = <StudyItem>[];
    queue = OfficialFormalReviewLiveQueue(
      session: session,
      sourceId: 'src-a',
      courseId: 'course-a',
      renderer: OfficialFormalReviewRenderer(
        engine: engine,
        profileId: 'profile-test',
      ),
      assembler: const OfficialStudyBatchAssembler(profileId: 'profile-test'),
      items: items,
      activePlacementCardKeys: {for (final id in [1, 2, 3]) _key(id)},
    );
    await queue.rebuildFromLiveQueue();
    final officialLedger = OfficialStudyLedger(
      OfficialAnkiReviewLedger(session),
    );
    final host = AnkiStudySessionHost(
      resolver: StudyLedgerResolver(official: officialLedger),
      onEffects: (item, receipt) => queue.rebuildFromLiveQueue(),
      onEffectsUndone: (receipt) => queue.rebuildFromLiveQueue(),
    );
    controller = host.openOfficialReview(
      items,
      officialLedger: officialLedger,
    );
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
  /// the scheduler's current after the rebuild, never index+1.
  Future<void> advanceFromScheduler() async {
    final currentCardId = session.current?.cardId;
    String? nextItemId;
    if (currentCardId != null) {
      for (final item in controller.items) {
        if (item.cardKey.cardId == currentCardId) {
          nextItemId = item.sessionItemId;
          break;
        }
      }
    }
    await controller.advanceTo(nextItemId);
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
}
