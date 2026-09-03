import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:turna/application/anki_official/contract/official_anki_dto.dart';
import 'package:turna/application/anki_official/engine/official_anki_engine_fake.dart';
import 'package:turna/application/anki_official/engine/official_anki_review_session.dart';
import 'package:turna/application/anki_official/engine/official_formal_due_repository.dart';
import 'package:turna/application/anki_official/introduction/card_introduction_store.dart';
import 'package:turna/application/anki_official/official_anki_feature_flags.dart';
import 'package:turna/application/anki_official/review/formal_review_launcher.dart';
import 'package:turna/application/anki_official/review/official_anki_routed_source.dart';
import 'package:turna/application/anki_official/review/official_formal_review_production_loader.dart';
import 'package:turna/application/anki_official/official_anki_composition.dart';
import 'package:turna/application/anki_official/storage/official_anki_database.dart';
import 'package:turna/application/anki_official/storage/official_anki_source_dao.dart';
import 'package:turna/data/anki_unification_dao.dart';
import 'package:turna/data/course_database.dart';
import 'package:turna/domain/anki/canonical_card_key.dart';
import 'package:turna/domain/anki/card_presentation.dart';

import '../../helpers/in_memory_course_db.dart';

// Regression for the invisible-imported-history bug: cards that arrived
// with reps>0 used to be seeded unintroduced and could never enter formal
// review. Seeding them with studiedCardIds (the publish path does this via
// the prop:reps>=1 collection search) must make them reviewable with no
// course submit ever happening.
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

  test('imported-history card enters the formal review batch', () async {
    const importId = 'src-imported-history';
    final dao = AnkiUnificationDao(db);
    final store = CardIntroductionStore(dao: dao);
    await store.seedOfficialProjection(
      sourceId: importId,
      cardIds: const [1, 2],
      studiedCardIds: const {1},
    );
    CardIntroductionStore.debugOverride = store;

    // The catalog ledger a real v2 publish writes: the lock reconciler
    // reads the source's card ids from the five-table ledger and suspends
    // card 2 (no imported history, no course submit) before the queue is
    // fetched.
    OfficialAnkiSourceDao(catalog).upsertSource(
      sourceId: importId,
      profileId: 'profile-default-01',
      sourceHash: 'fp',
      sourceSize: 1,
      displayName: 'imported-history.apkg',
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
    engine.seedPackage(packagePath: 'imported-history.apkg', notes: 2, cards: 2);

    final loader = OfficialFormalReviewProductionLoader(
      flags: flags,
      engine: engine,
      resolveTarget: (_) async => const OfficialAnkiRoutedSource(
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

    final result = await loader.load(
      importId: importId,
      courseId: 'anki-$importId',
    );

    expect(result, isA<OfficialFormalReviewReady>());
    final ready = result as OfficialFormalReviewReady;
    expect(
      ready.batch.items.map((item) => item.cardKey.cardId),
      [1],
      reason: 'card 1 carries imported history (reps>=1), so the reconciler '
          'leaves it unlocked; card 2 is a genuinely fresh card and stays '
          'scheduler-suspended',
    );
    expect(engine.suspended, {2});
  });
}
