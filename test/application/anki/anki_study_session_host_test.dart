import 'package:flutter_test/flutter_test.dart';
import 'package:turna/application/anki/anki_study_session_host.dart';
import 'package:turna/application/anki/unification/in_memory_anki_unification_store.dart';
import 'package:turna/domain/anki/canonical_card_key.dart';
import 'package:turna/domain/anki/card_presentation.dart';
import 'package:turna/domain/anki/study_models.dart';
import 'package:turna/domain/review/recall_outcome.dart';

void main() {
  const profile = 'profile-a';
  const courseId = 'course-1';
  const sourceId = 'src-1';

  CanonicalCardKey officialKey(int cardId) => CanonicalCardKey(
        backend: AnkiBackendKind.official,
        profileId: profile,
        sourceId: sourceId,
        cardId: cardId,
      );

  CanonicalCardKey turnaKey(int cardId) => CanonicalCardKey(
        backend: AnkiBackendKind.legacyTurna,
        profileId: profile,
        sourceId: sourceId,
        cardId: cardId,
      );

  FlipCardPresentation flipFor(CanonicalCardKey key) => FlipCardPresentation(
        cardKey: key,
        frontText: 'front-${key.cardId}',
        backText: 'back-${key.cardId}',
        sourceFingerprint: 'fp',
      );

  group('AnkiStudySessionHost', () {
    test('learn and review of the same card share one commit per answer',
        () async {
      final official = _FakeStudyLedger(owner: StudyLedgerOwner.officialAnki);
      final turna = _FakeStudyLedger(owner: StudyLedgerOwner.turnaFsrs);
      final store = InMemoryAnkiUnificationStore();
      final host = AnkiStudySessionHost(
        resolver: StudyLedgerResolver(official: official, turna: turna),
        introductionRepository: store,
      );
      final key = officialKey(1);

      final learn = await host.driveFlip(
        item: AnkiStudySessionHost.itemFor(
          key: key,
          presentation: flipFor(key),
          mode: StudyMode.learn,
          courseId: courseId,
        ),
        outcome: RecallOutcome.remembered,
      );
      expect(official.commits, 1);
      expect(turna.commits, 0);
      expect(learn.phase, StudyCardPhase.readyForNext);
      expect((await store.stateFor(courseId, key)).isIntroduced, isTrue);

      final review = await host.driveFlip(
        item: AnkiStudySessionHost.itemFor(
          key: key,
          presentation: flipFor(key),
          mode: StudyMode.review,
          courseId: courseId,
        ),
        outcome: RecallOutcome.forgotten,
      );
      expect(official.commits, 2);
      expect(turna.commits, 0);
      expect(review.lastReceipt?.eventId, isNot(learn.lastReceipt?.eventId));
    });

    test('Official write failure does not fall back to Turna', () async {
      final official = _FakeStudyLedger(owner: StudyLedgerOwner.officialAnki)
        ..failOnce = true;
      final turna = _FakeStudyLedger(owner: StudyLedgerOwner.turnaFsrs);
      final host = AnkiStudySessionHost(
        resolver: StudyLedgerResolver(official: official, turna: turna),
      );
      final key = officialKey(7);
      final controller = await host.driveFlip(
        item: AnkiStudySessionHost.itemFor(
          key: key,
          presentation: flipFor(key),
          mode: StudyMode.review,
          courseId: courseId,
        ),
        outcome: RecallOutcome.remembered,
      );
      expect(controller.phase, StudyCardPhase.recoverableError);
      expect(official.commits, 0);
      expect(turna.commits, 0);
    });

    test('missing Official ledger does not call Turna', () async {
      final turna = _FakeStudyLedger(owner: StudyLedgerOwner.turnaFsrs);
      final host = AnkiStudySessionHost(
        resolver: StudyLedgerResolver(turna: turna),
      );
      final key = officialKey(8);
      final controller = await host.driveFlip(
        item: AnkiStudySessionHost.itemFor(
          key: key,
          presentation: flipFor(key),
          mode: StudyMode.review,
          courseId: courseId,
        ),
        outcome: RecallOutcome.remembered,
      );
      expect(controller.phase, StudyCardPhase.recoverableError);
      expect(turna.commits, 0);
    });

    test('practice commits 0 ledger writes', () async {
      final official = _FakeStudyLedger(owner: StudyLedgerOwner.officialAnki);
      final turna = _FakeStudyLedger(owner: StudyLedgerOwner.turnaFsrs);
      final host = AnkiStudySessionHost(
        resolver: StudyLedgerResolver(official: official, turna: turna),
      );
      final key = officialKey(3);
      final controller = await host.driveFlip(
        item: AnkiStudySessionHost.itemFor(
          key: key,
          presentation: flipFor(key),
          mode: StudyMode.practice,
          courseId: courseId,
        ),
        outcome: RecallOutcome.remembered,
      );
      expect(official.commits, 0);
      expect(turna.commits, 0);
      expect(controller.lastReceipt?.ledgerOwner, StudyLedgerOwner.none);
      expect(controller.phase, StudyCardPhase.readyForNext);
    });

    test('undo restores exactly one event', () async {
      final turna = _FakeStudyLedger(owner: StudyLedgerOwner.turnaFsrs);
      final host = AnkiStudySessionHost(
        resolver: StudyLedgerResolver(turna: turna),
      );
      final key = turnaKey(4);
      final controller = await host.driveFlip(
        item: AnkiStudySessionHost.itemFor(
          key: key,
          presentation: flipFor(key),
          mode: StudyMode.review,
          courseId: courseId,
        ),
        outcome: RecallOutcome.remembered,
      );
      expect(turna.commits, 1);
      expect(controller.rememberedCount, 1);
      expect(await controller.undoLast(), isTrue);
      expect(turna.undos, 1);
      expect(controller.rememberedCount, 0);
      expect(turna.commits, 1);
      expect(controller.canRedo, isTrue);

      expect(await controller.redoLast(), isTrue);
      expect(controller.rememberedCount, 1);
      expect(controller.canRedo, isFalse);
    });

    test('buryCurrent and suspendCurrent delegate to ledger and advance card', () async {
      final official = _FakeStudyLedger(owner: StudyLedgerOwner.officialAnki);
      final host = AnkiStudySessionHost(
        resolver: StudyLedgerResolver(official: official),
      );
      final key1 = officialKey(10);
      final key2 = officialKey(20);
      final items = [
        AnkiStudySessionHost.itemFor(
          key: key1,
          presentation: flipFor(key1),
          mode: StudyMode.review,
          courseId: courseId,
        ),
        AnkiStudySessionHost.itemFor(
          key: key2,
          presentation: flipFor(key2),
          mode: StudyMode.review,
          courseId: courseId,
        ),
      ];

      final controller = host.open(items);
      await controller.start();
      expect(controller.currentIndex, 0);
      expect(controller.currentItem?.cardKey, key1);

      // Bury current card 10 -> advances to card 20
      expect(await controller.buryCurrent(), isTrue);
      expect(controller.currentIndex, 1);
      expect(controller.currentItem?.cardKey, key2);

      // Suspend current card 20 -> completes session
      expect(await controller.suspendCurrent(), isTrue);
      expect(controller.isComplete, isTrue);
    });
  });
}

class _FakeStudyLedger implements StudyLedger {
  _FakeStudyLedger({required this.owner});

  final StudyLedgerOwner owner;
  int commits = 0;
  int undos = 0;
  bool failOnce = false;
  final List<String> idempotencyKeys = [];
  final Map<String, StudyEventReceipt> _byKey = {};

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
    if (failOnce) {
      failOnce = false;
      throw StateError('ledger unavailable');
    }
    final existing = _byKey[idempotencyKey];
    if (existing != null) return existing;
    commits++;
    idempotencyKeys.add(idempotencyKey);
    final receipt = StudyEventReceipt(
      eventId: 'e-$commits',
      idempotencyKey: idempotencyKey,
      cardKey: key,
      ledgerOwner: owner,
      outcome: outcome,
      reviewedAt: DateTime.now(),
    );
    _byKey[idempotencyKey] = receipt;
    return receipt;
  }

  @override
  Future<bool> undo(StudyEventReceipt receipt) async {
    undos++;
    _byKey.remove(receipt.idempotencyKey);
    return true;
  }

  @override
  Future<bool> redo(StudyEventReceipt receipt) async {
    _byKey[receipt.idempotencyKey] = receipt;
    return true;
  }

  @override
  Future<bool> bury(CanonicalCardKey key) async => true;

  @override
  Future<bool> suspend(CanonicalCardKey key) async => true;
}
