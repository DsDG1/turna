import 'package:flutter_test/flutter_test.dart';
import 'package:turna/application/anki/anki_study_session_host.dart';
import 'package:turna/application/anki/formal_review_launcher.dart';
import 'package:turna/application/anki/official_study_batch_assembler.dart';
import 'package:turna/application/anki/study_ledger_adapters.dart';
import 'package:turna/application/anki_official/contract/official_anki_dto.dart';
import 'package:turna/application/anki_official/engine/official_anki_engine_fake.dart';
import 'package:turna/application/anki_official/engine/official_anki_review_session.dart';
import 'package:turna/application/anki_official/official_anki_feature_flags.dart';
import 'package:turna/domain/anki/canonical_card_key.dart';
import 'package:turna/domain/anki/card_presentation.dart';
import 'package:turna/domain/anki/study_models.dart';
import 'package:turna/domain/review/recall_outcome.dart';

void main() {
  const profile = 'profile-default-01';
  const sourceId = 'src-batch';
  const courseId = 'official-anki-src-batch';
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

  FlipCardPresentation flip(int id) => FlipCardPresentation(
        cardKey: key(id),
        frontText: 'f$id',
        backText: 'b$id',
        sourceFingerprint: 'fp',
      );

  OfficialReviewQueueCard queueCard(int id) => OfficialReviewQueueCard(
        cardId: id,
        noteId: id,
        deckId: 1,
        templateOrdinal: 0,
        queueKind: 'review',
        answerToken: 'tok-$id',
        labels: const OfficialReviewIntervalLabels(
          again: '1m',
          hard: '1d',
          good: '3d',
          easy: '7d',
        ),
      );

  group('OfficialStudyBatchAssembler', () {
    test('assembles only formal-due ∩ presentation cards', () {
      const assembler = OfficialStudyBatchAssembler();
      final items = assembler.assembleFromEligibility(
        sourceId: sourceId,
        courseId: courseId,
        queueCards: [queueCard(1), queueCard(2), queueCard(3), queueCard(4)],
        presentations: {
          key(1): flip(1),
          key(2): flip(2),
          key(4): flip(4),
        },
        activePlacementCardKeys: {key(1), key(2), key(3), key(4)},
        introducedCardKeys: {key(1), key(3), key(4)},
        buriedCardKeys: {key(4)},
      );

      expect(items.map((i) => i.cardKey.cardId), [1]);
      expect(items.single.mode, StudyMode.review);
      expect(items.single.ledgerOwner, StudyLedgerOwner.officialAnki);
      expect(items.single.capabilities.writesLedger, isTrue);
    });

    test('FormalReviewLauncher builds Official batch for shared host', () async {
      final engine = FakeOfficialAnkiEngine();
      engine.seedPackage(packagePath: 'batch.apkg', notes: 2, cards: 2);
      final session = OfficialReviewSession(
        engine: engine,
        flags: flags,
        allowedCardIds: {1, 2},
      );
      await session.openDeck(1);
      expect(session.queue?.cards, isNotEmpty);

      final batch = const FormalReviewLauncher().assembleOfficialBatch(
        session: session,
        sourceId: sourceId,
        courseId: courseId,
        queueCards: session.queue!.cards,
        presentations: {
          key(1): flip(1),
          key(2): flip(2),
        },
        activePlacementCardKeys: {key(1), key(2)},
        introducedCardKeys: {key(1), key(2)},
      );

      expect(batch.items, isNotEmpty);
      expect(
        batch.items.every((i) => i.ledgerOwner == StudyLedgerOwner.officialAnki),
        isTrue,
      );
      expect(batch.ledger, isA<OfficialStudyLedger>());
      expect(batch.session, same(session));
    });

    test('answering updates remaining conceptually via Official host', () async {
      final engine = FakeOfficialAnkiEngine();
      engine.seedPackage(packagePath: 'batch.apkg', notes: 2, cards: 2);
      final session = OfficialReviewSession(
        engine: engine,
        flags: flags,
        allowedCardIds: {1, 2},
      );
      await session.openDeck(1);

      final batch = const FormalReviewLauncher().assembleOfficialBatch(
        session: session,
        sourceId: sourceId,
        courseId: courseId,
        queueCards: [
          queueCard(1),
          queueCard(2),
        ],
        presentations: {
          key(1): flip(1),
          key(2): flip(2),
        },
        activePlacementCardKeys: {key(1), key(2)},
        introducedCardKeys: {key(1), key(2)},
      );
      expect(batch.items.length, 2);

      // Drive shared host with a counting Official ledger so remaining shrinks
      // without requiring live showAnswer/ACK coupling in this unit test.
      final ledger = _CountingOfficialLedger();
      final host = AnkiStudySessionHost(
        resolver: StudyLedgerResolver(official: ledger),
      );
      final controller = host.openOfficialReview(
        batch.items,
        officialLedger: ledger,
      );
      await controller.start();
      expect(controller.totalCount - controller.currentIndex, 2);

      AnkiStudySessionHost.presentBothSides(controller);
      await AnkiStudySessionHost.revealAndPresentAnswer(controller);
      await controller.submitRecall(RecallOutcome.remembered);
      expect(controller.phase, StudyCardPhase.readyForNext);
      expect(ledger.commits, 1);
      await controller.continueNext();
      expect(controller.totalCount - controller.currentIndex, 1);
      expect(controller.isComplete, isFalse);
    });
  });
}

class _CountingOfficialLedger implements StudyLedger {
  int commits = 0;

  @override
  Future<DueSnapshot> dueSnapshot(StudyScope scope) async {
    return const DueSnapshot(dueCardKeys: {});
  }

  @override
  Future<SchedulePreview> preview(
    CanonicalCardKey key,
    RecallOutcome outcome,
  ) async {
    return const SchedulePreview(intervalLabel: '1d');
  }

  @override
  Future<StudyEventReceipt> commit(
    CanonicalCardKey key,
    RecallOutcome outcome, {
    required String idempotencyKey,
  }) async {
    commits++;
    return StudyEventReceipt(
      eventId: 'official-$commits',
      idempotencyKey: idempotencyKey,
      cardKey: key,
      ledgerOwner: StudyLedgerOwner.officialAnki,
      outcome: outcome,
      reviewedAt: DateTime.now(),
    );
  }

  @override
  Future<bool> undo(StudyEventReceipt receipt) async => false;

  @override
  Future<bool> redo(StudyEventReceipt receipt) async => false;

  @override
  Future<bool> bury(CanonicalCardKey key) async => false;

  @override
  Future<bool> suspend(CanonicalCardKey key) async => false;
}
