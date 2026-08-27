// Live formal-review tests (plan 34 R2-2 / OS-12): the shared session
// batch follows the scheduler's refreshed queue. After an answer the
// batch is rebuilt from the LIVE queue — learning reinsertion and
// cross-day reordering reach the page, and stale snapshots invalidate.

import 'package:flutter_test/flutter_test.dart';
import 'package:turna/application/anki_official/review/official_study_batch_assembler.dart';
import 'package:turna/application/anki_official/contract/official_anki_dto.dart';
import 'package:turna/application/anki_official/engine/official_anki_engine_fake.dart';
import 'package:turna/application/anki_official/engine/official_anki_review_session.dart';
import 'package:turna/application/anki_official/official_anki_feature_flags.dart';
import 'package:turna/application/anki_official/review/official_formal_review_coordinator.dart';
import 'package:turna/domain/anki/canonical_card_key.dart';
import 'package:turna/domain/anki/study_models.dart';

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

/// Models the scheduler's learning-step reinsertion: an `again` answer
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

void main() {
  late FakeOfficialAnkiEngine engine;
  late OfficialReviewSession session;

  setUp(() async {
    engine = FakeOfficialAnkiEngine();
    engine.seedPackage(packagePath: 'x.apkg', notes: 3, cards: 3);
    session = OfficialReviewSession(
      engine: engine,
      flags: _flags,
      // Production passes the source's formal-due set; the fetch window
      // sizes to it.
      allowedCardIds: {1, 2, 3},
      profileId: 'profile-test',
    );
    await session.openDeck(1);
  });

  OfficialFormalReviewLiveQueue buildQueue(List<StudyItem> items) {
    return OfficialFormalReviewLiveQueue(
      session: session,
      sourceId: 'src-a',
      courseId: 'course-a',
      renderer: OfficialFormalReviewRenderer(
        engine: engine,
        profileId: 'profile-test',
      ),
      assembler: const OfficialStudyBatchAssembler(profileId: 'profile-test'),
      items: items,
      activePlacementCardKeys: {
        for (final id in [1, 2, 3]) _key(id)
      },
      introducedCardKeys: {
        for (final id in [1, 2, 3]) _key(id)
      },
    );
  }

  test('rebuild maps the refreshed queue onto the shared items list', () async {
    final items = <StudyItem>[];
    final queue = buildQueue(items);
    await queue.rebuildFromLiveQueue();

    expect(items, isNotEmpty);
    // Every live item is a card the scheduler currently owes, in queue
    // order — not a frozen pre-assembled array.
    final liveIds = session.queue!.cards.map((c) => c.cardId).toList();
    expect(
      items.map((i) => i.cardKey.cardId).toList(),
      liveIds,
    );
  });

  test('answering removes the card and rebuild shrinks the batch', () async {
    final items = <StudyItem>[];
    final queue = buildQueue(items);
    await queue.rebuildFromLiveQueue();
    final before = items.length;
    expect(before, greaterThan(0));

    final current = session.current!;
    session.showAnswer();
    await session.answerAndConfirm(
      'good',
      expectedCardId: current.cardId,
    );
    await queue.rebuildFromLiveQueue();

    expect(items.length, before - 1,
        reason: 'the answered card left the queue and the batch must '
            'shrink with it');
  });

  test('learning reinsertion (again) keeps the card in the live batch',
      () async {
    engine = _LearningReinsertEngine();
    engine.seedPackage(packagePath: 'x.apkg', notes: 3, cards: 3);
    session = OfficialReviewSession(
      engine: engine,
      flags: _flags,
      allowedCardIds: {1, 2, 3},
      profileId: 'profile-test',
    );
    await session.openDeck(1);
    final items = <StudyItem>[];
    final queue = buildQueue(items);
    await queue.rebuildFromLiveQueue();
    final before = items.length;

    final current = session.current!;
    session.showAnswer();
    await session.answerAndConfirm(
      'again',
      expectedCardId: current.cardId,
    );
    await queue.rebuildFromLiveQueue();

    // 'again' reinserts the card as a learning step — the scheduler still
    // owes it, so the live batch keeps it (possibly elsewhere in order).
    final stillOwed =
        session.queue!.cards.any((c) => c.cardId == current.cardId);
    expect(stillOwed, isTrue,
        reason: 'fake engine models learning reinsertion for again');
    final ids = items.map((i) => i.cardKey.cardId).toSet();
    expect(ids.contains(current.cardId), isTrue,
        reason: 'reinserted card must stay in the rebuilt batch');
    expect(items.length, before,
        reason: 'one card answered, the same card reinserted');
  });

  test('currentSnapshot invalidates after a queue mutation', () async {
    final items = <StudyItem>[];
    final queue = buildQueue(items);
    await queue.rebuildFromLiveQueue();

    final snapshot = queue.currentSnapshot();
    expect(snapshot, isNotNull);
    final generationBefore = snapshot!.renderGeneration;

    final current = session.current!;
    session.showAnswer();
    await session.answerAndConfirm(
      'good',
      expectedCardId: current.cardId,
    );
    await queue.rebuildFromLiveQueue();

    final after = queue.currentSnapshot();
    expect(after, isNotNull);
    expect(after!.renderGeneration, greaterThan(generationBefore),
        reason: 'a snapshot from before the mutation is stale by '
            'generation');
    if (session.queue!.cards.isNotEmpty) {
      expect(after.cardId, isNot(current.cardId),
          reason: 'the next card comes from the refreshed current, not '
              'from index+1 of a fixed array');
    }
  });

  test('bury removes the card from the live batch', () async {
    final items = <StudyItem>[];
    final queue = buildQueue(items);
    await queue.rebuildFromLiveQueue();

    final current = session.current!;
    await session.buryOrSuspend(OfficialBuryOrSuspendAction.burySched);
    await queue.rebuildFromLiveQueue();

    final ids = items.map((i) => i.cardKey.cardId).toSet();
    expect(ids.contains(current.cardId), isFalse);
  });
}
