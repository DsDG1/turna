import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:turna/application/anki_official/contract/official_anki_dto.dart';
import 'package:turna/application/anki_official/engine/official_anki_engine_fake.dart';
import 'package:turna/application/anki_official/engine/official_anki_review_session.dart';
import 'package:turna/application/anki_official/engine/official_formal_due_repository.dart';
import 'package:turna/application/anki_official/introduction/card_introduction_store.dart';
import 'package:turna/application/anki_official/official_anki_composition.dart';
import 'package:turna/application/anki_official/official_anki_feature_flags.dart';
import 'package:turna/application/anki_official/review/formal_review_launcher.dart';
import 'package:turna/application/anki_official/review/official_anki_routed_source.dart';
import 'package:turna/application/anki_official/review/official_formal_review_coordinator.dart';
import 'package:turna/application/anki_official/review/official_formal_review_production_loader.dart';
import 'package:turna/application/anki_official/storage/official_anki_database.dart';
import 'package:turna/application/anki_official/storage/official_anki_source_dao.dart';
import 'package:turna/data/anki_unification_dao.dart';
import 'package:turna/data/course_database.dart';

import '../../helpers/in_memory_course_db.dart';

/// Behaviour receipt for the P0-2 render window — the piece the source guard
/// (`official_formal_review_render_window_guard_test.dart`) can only assert
/// textually.
///
/// The failure this pins down is not "the window is the wrong size" but the
/// two ways a window can be wired wrong and still look fine in a source read:
///
///  * **rendering everything anyway** — the constant exists, the `take` is
///    there, and some earlier branch still walks the whole queue;
///  * **truncating the session** — the batch is right (8 cards) but
///    `restrictAllowedCards` was handed the *assembled* ids, so card 9 onward
///    can never enter and the learner is stuck at 8/8 while the deck still has
///    12 due.
///
/// Twenty cards, one deck, all introduced, so eligibility is the whole queue
/// and any truncation is visible as `allowedCardIds.length == 8`.
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

  const cardCount = 20;
  const importId = 'src-window';

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

  test('a 20-card queue renders only the window and keeps all 20 allowed',
      () async {
    final dao = AnkiUnificationDao(db);
    final store = CardIntroductionStore(dao: dao);
    // Every card introduced: eligibility is the whole queue, so a batch of 8
    // can only come from the window and never from the eligibility filter.
    await store.seedOfficialProjection(
      sourceId: importId,
      cardIds: List<int>.generate(cardCount, (index) => index + 1),
      studiedCardIds: Set<int>.of(
        List<int>.generate(cardCount, (index) => index + 1),
      ),
    );
    CardIntroductionStore.debugOverride = store;

    OfficialAnkiSourceDao(catalog).upsertSource(
      sourceId: importId,
      profileId: 'profile-default-01',
      sourceHash: 'fp',
      sourceSize: 1,
      displayName: 'window.apkg',
      state: 'active',
      backendCommit: 'test',
      nowMillis: 1,
    );
    OfficialAnkiSourceDao(catalog).replaceCards(
      sourceId: importId,
      cards: List<OfficialAnkiCardDescriptor>.generate(
        cardCount,
        (index) => OfficialAnkiCardDescriptor(
          cardId: index + 1,
          noteId: index + 1,
          deckId: 1,
          templateOrd: 0,
          noteGuid: 'g${index + 1}',
        ),
      ),
    );
    await db.customStatement(
      'INSERT INTO anki_course_tree_view '
      "(source_id, card_id, note_id, deck_id, word_id, section_key, section_id, "
      ' unit_id, lesson_id, lesson_key, presentation_kind, source_hash, '
      ' mapping_version, rebuilt_at_millis) VALUES '
      '${List<String>.generate(cardCount, (index) {
        final id = index + 1;
        return "('$importId', $id, $id, 1, 'w$id', 'sk', 's', 'u', 'l', 'lk', "
            "'flip', 'fp', 1, 1)";
      }).join(',')}',
    );
    GetIt.instance.registerSingleton<CourseDatabase>(db);

    final engine = FakeOfficialAnkiEngine()
      ..seedPackage(
        packagePath: 'window.apkg',
        notes: cardCount,
        cards: cardCount,
      );

    final loader = OfficialFormalReviewProductionLoader(
      flags: flags,
      engine: engine,
      resolveTarget: (_) async => OfficialAnkiRoutedSource(
        importId: importId,
        sourceId: importId,
        deckId: 1,
        cardIds: Set<int>.of(
          List<int>.generate(cardCount, (index) => index + 1),
        ),
      ),
      // Deliberately NOT set: `presentationsForCards` is the test-only shim
      // that skips the render loop entirely, which is exactly the code path
      // this receipt is about.
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
      engine.renderCount,
      officialInitialRenderWindow,
      reason: 'first screen must cost the window, not the queue: 20 cards '
          'rendered would put the whole loader back on the critical path',
    );
    expect(
      ready.batch.items,
      hasLength(officialInitialRenderWindow),
      reason: 'the batch is built from what was rendered — 8 presentations '
          'mean 8 items',
    );
    expect(
      ready.batch.session.allowedCardIds,
      hasLength(cardCount),
      reason: 'the allowed set must be "eligible minus failures", not the '
          'assembled batch: hands the session 8 and cards 9-20 are gone for '
          'the rest of the review, while the deck still owes them',
    );
    expect(
      ready.batch.session.current?.cardId,
      1,
      reason: 'the window is taken in queue order, so the first card is still '
          'the first card',
    );
  });
}
