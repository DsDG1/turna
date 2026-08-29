// P1 tests: the course-completion gate is a scheduler suspension. The
// reconciler suspends exactly the ledger-unintroduced cards, never restores
// (user suspensions survive), and completion unlocking is caller-managed.

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:turna/application/anki_official/contract/official_anki_dto.dart';
import 'package:turna/application/anki_official/engine/official_anki_engine_fake.dart';
import 'package:turna/application/anki_official/engine/official_anki_lock_reconciler.dart';
import 'package:turna/application/anki_official/engine/official_anki_scheduler_audit.dart';
import 'package:turna/application/anki_official/introduction/card_introduction_store.dart';
import 'package:turna/application/anki_official/projection/official_anki_projection_projector.dart';
import 'package:turna/application/anki_official/projection/official_anki_projection_store.dart';
import 'package:turna/data/anki_unification_dao.dart';
import 'package:turna/data/course_database.dart';

import '../../../helpers/in_memory_course_db.dart';

OfficialAnkiProjectedItem _item(int cardId) {
  return OfficialAnkiProjectedItem(
    kind: OfficialAnkiProjectionKind.flip,
    cardId: cardId,
    wordId: 'official-anki-key-c$cardId',
    sectionId: 'official-anki-src-lr-s1',
    unitId: 'official-anki-src-lr-u1',
    lessonId: 'official-anki-src-lr-l1-p1',
    sectionName: 'S',
    unitName: 'U',
    lessonName: 'L',
    payload: const <String, Object?>{},
    sourceFingerprint: 'fp',
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  ensureSqliteLibForTestHost();

  group('OfficialAnkiLockReconciler', () {
    late CourseDatabase db;
    late FakeOfficialAnkiEngine engine;
    late CardIntroductionStore store;

    setUp(() async {
      db = CourseDatabase(NativeDatabase.memory());
      await GetIt.instance.reset();
      GetIt.instance.registerSingleton<CourseDatabase>(db);
      engine = FakeOfficialAnkiEngine();
      engine.seedPackage(packagePath: 'x.apkg', notes: 5, cards: 5);
      store = CardIntroductionStore(dao: AnkiUnificationDao(db));
      CardIntroductionStore.debugOverride = store;
    });

    tearDown(() async {
      CardIntroductionStore.debugOverride = null;
      await GetIt.instance.reset();
      await db.close();
    });

    test('reconcileSource suspends exactly the unintroduced cards',
        () async {
      await OfficialAnkiCourseProjectionStore(db).replaceOfficialProjection(
        sourceId: 'src-lr',
        plan: OfficialAnkiProjectionPlan(
          items: [_item(1), _item(2), _item(3)],
          issues: const [],
        ),
      );
      await store.markIntroducedCard(
        sourceId: 'src-lr',
        cardId: 2,
        wordId: 'official-anki-key-c2',
        lessonId: 'official-anki-src-lr-l1-p1',
      );

      final suspendedCount = await OfficialAnkiLockReconciler(
        engine: engine,
      ).reconcileSource(sourceId: 'src-lr');

      expect(suspendedCount, 2);
      expect(engine.suspended, {1, 3});
    });

    test('reconcile is a no-op when everything is introduced and never '
        'restores a user suspension', () async {
      await OfficialAnkiCourseProjectionStore(db).replaceOfficialProjection(
        sourceId: 'src-lr',
        plan: OfficialAnkiProjectionPlan(
          items: [_item(1), _item(2)],
          issues: const [],
        ),
      );
      await store.markIntroducedCard(
        sourceId: 'src-lr',
        cardId: 1,
        wordId: 'official-anki-key-c1',
        lessonId: 'official-anki-src-lr-l1-p1',
      );
      await store.markIntroducedCard(
        sourceId: 'src-lr',
        cardId: 2,
        wordId: 'official-anki-key-c2',
        lessonId: 'official-anki-src-lr-l1-p1',
      );
      // The user suspends an already-taught card from the review UI.
      await engine.buryOrSuspendCards(
        action: OfficialBuryOrSuspendAction.suspend,
        cardIds: const [2],
      );

      final suspendedCount = await OfficialAnkiLockReconciler(
        engine: engine,
      ).reconcileSource(sourceId: 'src-lr');

      expect(suspendedCount, 0, reason: 'nothing left to lock');
      expect(engine.suspended, {2}, reason: 'the user suspension survives');
    });

    test('reconcile is fail-closed without an engine or projection rows',
        () async {
      expect(
        await OfficialAnkiLockReconciler(
          engine: null,
        ).reconcileSource(sourceId: 'src-lr'),
        0,
        reason: 'no engine — the next refresh retries',
      );
      expect(
        await OfficialAnkiLockReconciler(
          engine: engine,
        ).reconcileSource(sourceId: 'src-never-published'),
        0,
      );
      expect(engine.suspended, isEmpty);
    });

    test('unlockCards restores the lock suspension', () async {
      await engine.buryOrSuspendCards(
        action: OfficialBuryOrSuspendAction.suspend,
        cardIds: const [1, 3],
      );

      await OfficialAnkiLockReconciler(engine: engine).unlockCards(
        sourceId: 'src-lr',
        cardIds: const [1, 3],
      );

      expect(engine.suspended, isEmpty);
    });

    test('unlockCards chunks past the bridge 100-id batch limit', () async {
      final cardIds = List<int>.generate(150, (i) => i + 1);
      final before = OfficialAnkiSchedulerAudit.officialSchedulerBurySuspend;
      await OfficialAnkiLockReconciler(engine: engine).unlockCards(
        sourceId: 'src-lr',
        cardIds: cardIds,
      );
      expect(
        OfficialAnkiSchedulerAudit.officialSchedulerBurySuspend - before,
        2,
        reason: '150 ids must split into 100 + 50 calls',
      );
    });

    test('unlockCards throws without an engine so the caller aborts marking',
        () async {
      await expectLater(
        OfficialAnkiLockReconciler(engine: null).unlockCards(
          sourceId: 'src-lr',
          cardIds: const [1],
        ),
        throwsStateError,
      );
    });
  });
}