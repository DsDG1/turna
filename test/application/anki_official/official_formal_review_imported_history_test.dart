import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:turna/application/anki_official/contract/official_anki_dto.dart';
import 'package:turna/application/anki_official/engine/official_anki_engine_fake.dart';
import 'package:turna/application/anki_official/engine/official_anki_review_session.dart';
import 'package:turna/application/anki_official/engine/official_formal_due_repository.dart';
import 'package:turna/application/anki_official/introduction/card_introduction_store.dart';
import 'package:turna/application/anki_official/official_anki_feature_flags.dart';
import 'package:turna/application/anki_official/migration/official_anki_production_router.dart';
import 'package:turna/application/anki_official/review/formal_review_launcher.dart';
import 'package:turna/application/anki_official/review/official_formal_review_production_loader.dart';
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

  setUp(() {
    OfficialFormalDueRepository.instance.resetForTest();
    CardIntroductionStore.debugOverride = null;
    db = CourseDatabase(NativeDatabase.memory());
  });

  tearDown(() async {
    CardIntroductionStore.debugOverride = null;
    OfficialFormalDueRepository.instance.resetForTest();
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
      reason: 'card 1 carries imported history (reps>=1) and is therefore '
          'introduced; card 2 is a genuinely fresh card and stays filtered',
    );
  });
}
