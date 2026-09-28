import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:turna/application/anki_official/contract/official_anki_dto.dart';
import 'package:turna/application/anki_official/engine/official_anki_engine_fake.dart';
import 'package:turna/application/anki_official/engine/official_anki_review_session.dart';
import 'package:turna/application/anki_official/engine/official_formal_due_repository.dart';
import 'package:turna/application/anki_official/introduction/card_introduction_store.dart';
import 'package:turna/application/anki_official/official_anki_feature_flags.dart';
import 'package:turna/application/anki_official/official_anki_composition.dart';
import 'package:turna/application/anki_official/review/formal_review_launcher.dart';
import 'package:turna/application/anki_official/review/official_anki_routed_source.dart';
import 'package:turna/application/anki_official/review/official_formal_review_production_loader.dart';
import 'package:turna/application/anki_official/storage/official_anki_database.dart';
import 'package:turna/application/anki_official/storage/official_anki_source_dao.dart';
import 'package:turna/data/anki_unification_dao.dart';
import 'package:turna/data/course_database.dart';
import 'package:turna/domain/anki/canonical_card_key.dart';
import 'package:turna/domain/anki/card_introduction_state.dart';
import 'package:turna/domain/anki/card_presentation.dart';

import '../../helpers/in_memory_course_db.dart';

// Two introductions of one invariant: the loader reconciles the scheduler
// lock from durable records (no in-memory hydration) and the queue itself is
// the gate — an introduced card 1 enters the batch, a never-introduced card 2
// stays scheduler-suspended.
//
//  * imported history (merged from official_formal_review_imported_history_
//    test.dart): cards arriving with reps>0 are seeded studied via the publish
//    path (seedOfficialProjection) and must be reviewable with no course
//    submit ever happening (invisible-imported-history regression).
//  * cold restart: a fresh process with only durable introduction rows —
//    successor of the "暂无待复习的 Anki 卡片" regression.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  ensureSqliteLibForTestHost();

  const flags = OfficialAnkiFeatureFlags(
    engine: true,
    import: true,
    catalogReady: true,
    runtimeCapable: true,
    platformReady: true,
    renderer: true,
    scheduler: true,
    projection: true,
    courseEntry: true,
    officialFirstImport: true,
  );

  late CourseDatabase db;
  late OfficialAnkiDatabase catalog;

  setUp(() {
    OfficialFormalDueRepository.instance.resetForTest();
    CardIntroductionStore.debugOverride = null;
    db = CourseDatabase(NativeDatabase.memory());
    catalog = OfficialAnkiDatabase.memory();
    OfficialAnkiCompositionRoot.readOnlyCatalog = catalog;
  });

  tearDown(() async {
    CardIntroductionStore.debugOverride = null;
    OfficialFormalDueRepository.instance.resetForTest();
    OfficialAnkiCompositionRoot.readOnlyCatalog = null;
    catalog.close();
    await GetIt.instance.reset();
    await db.close();
  });

  Future<
      ({
        OfficialFormalReviewLoadResult result,
        FakeOfficialAnkiEngine engine
      })> loadReconciledBatch({
    required String importId,
    required String packagePath,
    required Future<void> Function(
      AnkiUnificationDao dao,
      CardIntroductionStore store,
    ) seedIntroduction,
  }) async {
    final dao = AnkiUnificationDao(db);
    final store = CardIntroductionStore(dao: dao);
    await seedIntroduction(dao, store);
    CardIntroductionStore.debugOverride = store;

    // The catalog ledger a real v2 publish writes: the lock reconciler reads
    // the source's card ids from the five-table ledger and suspends
    // card 2 (no introduction, no course submit) before the queue is fetched.
    OfficialAnkiSourceDao(catalog).upsertSource(
      sourceId: importId,
      profileId: 'profile-default-01',
      sourceHash: 'fp',
      sourceSize: 1,
      displayName: packagePath,
      state: 'active',
      backendCommit: 'test',
      nowMillis: 1,
    );
    OfficialAnkiSourceDao(catalog).replaceCards(
      sourceId: importId,
      cards: const [
        OfficialAnkiCardDescriptor(
            cardId: 1, noteId: 1, deckId: 1, templateOrd: 0, noteGuid: 'g1'),
        OfficialAnkiCardDescriptor(
            cardId: 2, noteId: 2, deckId: 1, templateOrd: 0, noteGuid: 'g2'),
      ],
    );
    // The course tree view the loader's read path resolves the course from.
    await db.customStatement(
      "INSERT INTO anki_course_tree_view "
      "(source_id, card_id, note_id, deck_id, word_id, section_key, section_id, "
      " unit_id, lesson_id, lesson_key, presentation_kind, source_hash, "
      " mapping_version, rebuilt_at_millis) VALUES "
      "('$importId', 1, 1, 1, 'w1', 'sk', 's', 'u', 'l', 'lk', 'flip', 'fp', 1, 1),"
      "('$importId', 2, 2, 1, 'w2', 'sk', 's', 'u', 'l', 'lk', 'flip', 'fp', 1, 1)",
    );
    GetIt.instance.registerSingleton<CourseDatabase>(db);

    final engine = FakeOfficialAnkiEngine();
    engine.seedPackage(packagePath: packagePath, notes: 2, cards: 2);

    final loader = OfficialFormalReviewProductionLoader(
      flags: flags,
      engine: engine,
      resolveTarget: (_) async => OfficialAnkiRoutedSource(
        importId: importId,
        sourceId: importId,
        deckId: 1,
        cardIds: {1, 2},
      ),
      presentationsForCards: ({
        required String sourceId,
        required Iterable<OfficialReviewQueueCard> cards,
      }) async {
        return {
          for (final card in cards)
            CanonicalCardKey(
              backend: AnkiBackendKind.official,
              profileId: 'profile-default-01',
              sourceId: sourceId,
              cardId: card.cardId,
            ): FlipCardPresentation(
              cardKey: CanonicalCardKey(
                backend: AnkiBackendKind.official,
                profileId: 'profile-default-01',
                sourceId: sourceId,
                cardId: card.cardId,
              ),
              frontText: 'front-${card.cardId}',
              backText: 'back-${card.cardId}',
              sourceFingerprint: 't',
            ),
        };
      },
      sessionFactory: ({
        required engine,
        required allowedCardIds,
      }) async {
        return OfficialReviewSession(
          engine: engine,
          flags: flags,
          allowedCardIds: allowedCardIds,
        );
      },
    );

    return (
      result: await loader.load(
        importId: importId,
        courseId: 'anki-$importId',
      ),
      engine: engine,
    );
  }

  test('imported-history card (reps>=1) enters the formal review batch',
      () async {
    const importId = 'src-imported-history';
    final run = await loadReconciledBatch(
      importId: importId,
      packagePath: 'imported-history.apkg',
      seedIntroduction: (dao, store) async {
        await store.seedOfficialProjection(
          sourceId: importId,
          cardIds: const [1, 2],
          studiedCardIds: const {1},
        );
      },
    );

    final result = run.result;
    expect(result, isA<OfficialFormalReviewReady>());
    final ready = result as OfficialFormalReviewReady;
    expect(
      ready.batch.items.map((item) => item.cardKey.cardId),
      [1],
      reason: 'card 1 carries imported history (reps>=1), so the reconciler '
          'leaves it unlocked; card 2 is a genuinely fresh card and stays '
          'scheduler-suspended',
    );
    expect(run.engine.suspended, {2});
  });

  test(
      'a cold process needs no hydration — the loader reconciles the lock '
      'and the queue is the gate', () async {
    const importId = 'src-hydration';
    final run = await loadReconciledBatch(
      importId: importId,
      packagePath: 'hydration.apkg',
      seedIntroduction: (dao, store) async {
        await dao.upsertIntroduction(
          courseId: 'official-anki-$importId',
          key: const CanonicalCardKey(
            backend: AnkiBackendKind.official,
            profileId: 'profile-default-01',
            sourceId: importId,
            cardId: 1,
          ),
          status: CardIntroductionStatus.introduced,
          introducedBy: CardIntroducedBy.course,
        );
      },
    );

    final result = run.result;
    expect(result, isA<OfficialFormalReviewReady>());
    final ready = result as OfficialFormalReviewReady;
    expect(
      ready.batch.items.map((item) => item.cardKey.cardId),
      [1],
      reason: 'the loader reconciled the lock before fetching the queue, so '
          'card 2 never reached it',
    );
    expect(ready.batch.session.current?.cardId, 1);
    expect(run.engine.suspended, {2},
        reason: 'the lock suspension is the durable record of "course not '
            'completed yet"');
  });
}
