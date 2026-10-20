import 'package:flutter_test/flutter_test.dart';
import 'package:turna/application/anki_official/engine/official_anki_engine_fake.dart';
import 'package:turna/application/anki_official/engine/official_anki_review_session.dart';
import 'package:turna/application/anki_official/engine/official_formal_due_repository.dart';
import 'package:turna/application/anki_official/engine/official_formal_due_snapshot_builder.dart';
import 'package:turna/application/anki_official/official_anki_feature_flags.dart';
import 'package:turna/application/anki_official/review/official_anki_review_ledger.dart';
import 'package:turna/application/study_session/study_ledger_adapters.dart';
import 'package:turna/domain/anki/canonical_card_key.dart';
import 'package:turna/domain/review/recall_outcome.dart';

/// The due badge is driven by [OfficialFormalDueRepository], not by the
/// scheduler: a review session only writes the engine. These tests lock the
/// fold that makes the count move the moment a card is graded, so the Play Hub
/// does not depend on a full refresh happening (it had no reliable trigger).
void main() {
  const profile = 'profile-default-01';
  const sourceId = 'src-fold';
  const flags = OfficialAnkiFeatureFlags(
    engine: true,
    import: true,
    catalogReady: true,
    runtimeCapable: true,
    platformReady: true,
    renderer: true,
    scheduler: true,
  );

  CanonicalCardKey key(int id) => CanonicalCardKey(
        backend: AnkiBackendKind.official,
        profileId: profile,
        sourceId: sourceId,
        cardId: id,
      );

  OfficialFormalDueRepository seedRepository({required Set<int> due}) {
    final repo = OfficialFormalDueRepository.instance..resetForTest();
    repo.commit(
      const OfficialFormalDueSnapshotBuilder().build(
        sources: [
          OfficialFormalDueSourceInput(
            importId: sourceId,
            schedulerDueCardIds: due,
            schedulerDueSynced: true,
            activePlacementCardIds: due,
          ),
        ],
      ),
      basedOnGeneration: repo.generation,
    );
    return repo;
  }

  /// Opens a 2-card Official session and parks it on an answerable card:
  /// `answerAndConfirm` only accepts `showingAnswer`, so the question has to be
  /// flipped first (and flipped again for every following card).
  Future<(OfficialStudyLedger, OfficialReviewSession)> openLedger() async {
    final engine = FakeOfficialAnkiEngine()
      ..seedPackage(packagePath: 'fold.apkg', notes: 2, cards: 2);
    final session = OfficialReviewSession(
      engine: engine,
      flags: flags,
      allowedCardIds: {1, 2},
    );
    await session.openDeck(1);
    session.showAnswer();
    return (OfficialStudyLedger(OfficialAnkiReviewLedger(session)), session);
  }

  setUp(() => OfficialFormalDueRepository.instance.resetForTest());
  tearDown(() => OfficialFormalDueRepository.instance.resetForTest());

  test('a graded card leaves the due snapshot without a refresh', () async {
    final repo = seedRepository(due: {1, 2});
    expect(repo.snapshot.introducedOfficialDue, 2);

    final (ledger, _) = await openLedger();
    await ledger.commit(key(1), RecallOutcome.remembered,
        idempotencyKey: 'fold-1');

    expect(
      repo.schedulerDueCardIdsFor(sourceId),
      {2},
      reason: 'the answered card is no longer owed — the count has to fall '
          'right away instead of waiting for the next full refresh',
    );
    expect(repo.snapshot.introducedOfficialDue, 1);
  });

  test('the snapshot empties as the queue drains', () async {
    final repo = seedRepository(due: {1, 2});
    final (ledger, session) = await openLedger();

    await ledger.commit(key(1), RecallOutcome.remembered,
        idempotencyKey: 'fold-2');
    expect(repo.schedulerDueCardIdsFor(sourceId), {2});

    session.showAnswer();
    await ledger.commit(key(2), RecallOutcome.remembered,
        idempotencyKey: 'fold-3');
    expect(
      repo.schedulerDueCardIdsFor(sourceId),
      isEmpty,
      reason: 'the fold has to survive consecutive answers, not just the first',
    );
    expect(repo.snapshot.introducedOfficialDue, 0);
  });
}
