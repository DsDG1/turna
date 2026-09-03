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
import 'package:turna/application/anki_official/official_anki_composition.dart';
import 'package:turna/application/anki_official/storage/official_anki_database.dart';
import 'package:turna/application/anki_official/storage/official_anki_source_dao.dart';
import 'package:turna/data/anki_unification_dao.dart';
import 'package:turna/data/course_database.dart';

import '../../../helpers/in_memory_course_db.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  ensureSqliteLibForTestHost();

  group('OfficialAnkiLockReconciler', () {
    late CourseDatabase db;
    late OfficialAnkiDatabase catalog;
    late FakeOfficialAnkiEngine engine;
    late CardIntroductionStore store;

    setUp(() async {
      db = CourseDatabase(NativeDatabase.memory());
      catalog = OfficialAnkiDatabase.memory();
      OfficialAnkiCompositionRoot.readOnlyCatalog = catalog;
      await GetIt.instance.reset();
      GetIt.instance.registerSingleton<CourseDatabase>(db);
      engine = FakeOfficialAnkiEngine();
      engine.seedPackage(packagePath: 'x.apkg', notes: 5, cards: 5);
      store = CardIntroductionStore(dao: AnkiUnificationDao(db));
      CardIntroductionStore.debugOverride = store;

      OfficialAnkiSourceDao(catalog).upsertSource(
        sourceId: 'src-lr',
        profileId: 'p1',
        sourceHash: 'h1',
        sourceSize: 1,
        displayName: 'LR',
        state: 'active',
        backendCommit: 'c1',
        nowMillis: 1,
      );
    });

    tearDown(() async {
      CardIntroductionStore.debugOverride = null;
      OfficialAnkiCompositionRoot.readOnlyCatalog = null;
      catalog.close();
      await GetIt.instance.reset();
      await db.close();
    });

    test('reconcileSource suspends exactly the unintroduced cards', () async {
      OfficialAnkiSourceDao(catalog).upsertCardBatch(
        sourceId: 'src-lr',
        cards: const [
          OfficialAnkiCardDescriptor(cardId: 1, noteId: 1, deckId: 1, templateOrd: 0),
          OfficialAnkiCardDescriptor(cardId: 2, noteId: 2, deckId: 1, templateOrd: 0),
          OfficialAnkiCardDescriptor(cardId: 3, noteId: 3, deckId: 1, templateOrd: 0),
        ],
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

    test('reconcile is a no-op when everything is introduced and never restores a user suspension', () async {
      OfficialAnkiSourceDao(catalog).upsertCardBatch(
        sourceId: 'src-lr',
        cards: const [
          OfficialAnkiCardDescriptor(cardId: 1, noteId: 1, deckId: 1, templateOrd: 0),
          OfficialAnkiCardDescriptor(cardId: 2, noteId: 2, deckId: 1, templateOrd: 0),
        ],
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

    test('reconcile is fail-closed without an engine or projection rows', () async {
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
        cardIds: const [1, 2],
      );
      await OfficialAnkiLockReconciler(engine: engine).unlockCards(
        sourceId: 'src-lr',
        cardIds: const [1],
      );
      expect(engine.suspended, {2});
    });

    test('audit reports unintroduced-vs-suspended counts', () {
      OfficialAnkiSchedulerAudit.reset();
      OfficialAnkiSchedulerAudit.officialSchedulerBurySuspend = 2;
      final snap = OfficialAnkiSchedulerAudit.snapshot();
      expect(snap['officialSchedulerBurySuspend'], 2);
    });
  });
}
