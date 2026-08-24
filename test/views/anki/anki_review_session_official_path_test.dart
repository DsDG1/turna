import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:streaming_shared_preferences/streaming_shared_preferences.dart';
import 'package:turna/application/anki/anki_deck_manager.dart';
import 'package:turna/application/anki/anki_review_content.dart';
import 'package:turna/application/anki/official_formal_review_production_loader.dart';
import 'package:turna/application/anki_official/contract/official_anki_dto.dart';
import 'package:turna/application/anki_official/engine/official_anki_engine_fake.dart';
import 'package:turna/application/anki_official/engine/official_anki_home_due.dart';
import 'package:turna/application/anki_official/engine/official_anki_review_session.dart';
import 'package:turna/application/anki_official/migration/official_anki_production_router.dart';
import 'package:turna/application/anki_official/official_anki_feature_flags.dart';
import 'package:turna/application/course_provider.dart';
import 'package:turna/application/lesson_link_store.dart';
import 'package:turna/application/srs_provider.dart';
import 'package:turna/data/anki_import_dao.dart';
import 'package:turna/data/anki_note_dao.dart';
import 'package:turna/data/course_database.dart';
import 'package:turna/data/course_repository.dart';
import 'package:turna/data/srs_state_dao.dart';
import 'package:turna/di/injection.dart';
import 'package:turna/domain/anki/canonical_card_key.dart';
import 'package:turna/domain/anki/card_presentation.dart';
import 'package:turna/domain/anki/study_models.dart';
import 'package:turna/domain/review/review_item.dart';
import 'package:turna/service/locator.dart';
import 'package:turna/l10n/app_strings.dart';
import 'package:turna/views/anki/anki_review_session_page.dart';

import '../../helpers/in_memory_course_db.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  ensureSqliteLibForTestHost();
  ensurePathProviderMockForTest();

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
  late SrsProvider srs;
  late AppPrefs appPrefs;
  late OfficialAnkiFeatureFlags savedFlags;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    final preferences = await StreamingSharedPreferences.instance;
    appPrefs = AppPrefs(preferences);
    await getIt.reset();
    OfficialAnkiHomeDue.reset();
    AnkiReviewSessionPage.debugOfficialBatchBuilder = null;
    AnkiReviewSessionPage.productionLoader =
        const OfficialFormalReviewProductionLoader();

    db = CourseDatabase(NativeDatabase.memory());
    srs = SrsProvider(appPrefs, LessonLinkStore(appPrefs), SrsStateDao(db));
    getIt.registerSingleton<CourseDatabase>(db);
    getIt.registerSingleton<AnkiDeckManager>(
      AnkiDeckManager(
        repo: CourseRepository(db),
        srsProvider: srs,
        importDao: AnkiImportDao(db),
        noteDao: AnkiNoteDao(db),
        appPrefs: appPrefs,
      ),
    );
    savedFlags = OfficialAnkiFeatureFlags.current;
    OfficialAnkiFeatureFlags.current = flags;
  });

  tearDown(() async {
    AnkiReviewSessionPage.debugOfficialBatchBuilder = null;
    AnkiReviewSessionPage.productionLoader =
        const OfficialFormalReviewProductionLoader();
    OfficialAnkiFeatureFlags.current = savedFlags;
    OfficialAnkiHomeDue.reset();
    await getIt.reset();
    await db.close();
  });

  testWidgets(
    'Official owner page uses productionLoader when debug seam is null',
    (tester) async {
      const importId = 'src-official-page';
      OfficialAnkiHomeDue.officialImportIds = {importId};

      final engine = FakeOfficialAnkiEngine();
      engine.seedPackage(packagePath: 'page.apkg', notes: 2, cards: 2);

      AnkiReviewSessionPage.productionLoader =
          OfficialFormalReviewProductionLoader(
        flags: flags,
        engine: engine,
        resolveTarget: (_) async => const OfficialAnkiRoutedSource(
          importId: importId,
          sourceId: importId,
          deckId: 1,
          cardIds: {1, 2},
        ),
        introducedCardIds: (_) => {1, 2},
        activePlacementCardIds: (_) => {1, 2},
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

      expect(
        AnkiReviewSessionPage.debugOfficialBatchBuilder,
        isNull,
        reason: 'must exercise productionLoader, not the debug seam',
      );

      await tester.pumpWidget(
        MultiProvider(
          providers: [
            ChangeNotifierProvider<SrsProvider>.value(value: srs),
            ChangeNotifierProvider(create: (_) => CourseProvider(appPrefs)),
          ],
          child: const MaterialApp(
            home: AnkiReviewSessionPage(
              sectionId: 'anki-src-official-page-s1',
            ),
          ),
        ),
      );

      // Avoid pumpAndSettle — StudyCardSurface / TTS may keep scheduling frames.
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 20));
      await tester.pump(const Duration(milliseconds: 200));
      await tester.pump(const Duration(milliseconds: 200));

      expect(find.byType(CircularProgressIndicator), findsNothing);
      expect(find.textContaining('front-1'), findsWidgets);
    },
  );

  test(
    'productionLoader default path renders non-empty faces without presentationsForCards',
    () async {
      final engine = FakeOfficialAnkiEngine();
      engine.seedPackage(packagePath: 'loader.apkg', notes: 2, cards: 2);
      // No presentationsForCards — must use engine.renderCard → Flip text.
      final loader = OfficialFormalReviewProductionLoader(
        flags: flags,
        engine: engine,
        resolveTarget: (_) async => const OfficialAnkiRoutedSource(
          importId: 'src-l',
          sourceId: 'src-l',
          deckId: 1,
          cardIds: {1, 2},
        ),
        introducedCardIds: (_) => {1, 2},
        activePlacementCardIds: (_) => {1, 2},
      );

      final batch = await loader.load(
        importId: 'src-l',
        courseId: 'anki-src-l',
      );
      expect(batch, isNotNull);
      expect(batch!.items, isNotEmpty);
      expect(
        batch.items.every((i) => i.ledgerOwner == StudyLedgerOwner.officialAnki),
        isTrue,
      );
      expect(batch.items.every((i) => i.presentation is FlipCardPresentation),
          isTrue);

      for (final item in batch.items) {
        final body = reviewContentFor(
          item,
          fidelityInteractions: batch.fidelityInteractions,
        );
        expect(body, isA<StandardCourseCardContent>());
        final content = body as StandardCourseCardContent;
        expect(content.frontText, isNotEmpty,
            reason: 'default production path must not yield blank fronts');
        expect(content.backText, isNotEmpty,
            reason: 'default production path must not yield blank backs');
        expect(content.frontText, startsWith('Q'));
        expect(content.backText, startsWith('A'));
      }
      expect(engine.renderCount, greaterThan(0));
    },
  );

  testWidgets(
    'Official owner page default loader shows renderCard text (no Flip inject)',
    (tester) async {
      const importId = 'src-default-render';
      OfficialAnkiHomeDue.officialImportIds = {importId};

      final engine = FakeOfficialAnkiEngine();
      engine.seedPackage(packagePath: 'page2.apkg', notes: 2, cards: 2);

      AnkiReviewSessionPage.productionLoader =
          OfficialFormalReviewProductionLoader(
        flags: flags,
        engine: engine,
        resolveTarget: (_) async => const OfficialAnkiRoutedSource(
          importId: importId,
          sourceId: importId,
          deckId: 1,
          cardIds: {1, 2},
        ),
        introducedCardIds: (_) => {1, 2},
        activePlacementCardIds: (_) => {1, 2},
        // presentationsForCards intentionally omitted.
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
      expect(AnkiReviewSessionPage.debugOfficialBatchBuilder, isNull);

      await tester.pumpWidget(
        MultiProvider(
          providers: [
            ChangeNotifierProvider<SrsProvider>.value(value: srs),
            ChangeNotifierProvider(create: (_) => CourseProvider(appPrefs)),
          ],
          child: const MaterialApp(
            home: AnkiReviewSessionPage(
              sectionId: 'anki-src-default-render-s1',
            ),
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 20));
      await tester.pump(const Duration(milliseconds: 200));
      await tester.pump(const Duration(milliseconds: 200));

      expect(find.byType(CircularProgressIndicator), findsNothing);
      // FakeOfficialAnkiEngine.renderCard returns Q$id / A$id.
      expect(find.textContaining('Q1'), findsWidgets);
    },
  );

  testWidgets(
    'Official shared host reveal then Good writes official scheduler',
    (tester) async {
      const importId = 'src-answer';
      OfficialAnkiHomeDue.officialImportIds = {importId};

      final engine = FakeOfficialAnkiEngine();
      engine.seedPackage(packagePath: 'answer.apkg', notes: 2, cards: 2);

      AnkiReviewSessionPage.productionLoader =
          OfficialFormalReviewProductionLoader(
        flags: flags,
        engine: engine,
        resolveTarget: (_) async => const OfficialAnkiRoutedSource(
          importId: importId,
          sourceId: importId,
          deckId: 1,
          cardIds: {1, 2},
        ),
        introducedCardIds: (_) => {1, 2},
        activePlacementCardIds: (_) => {1, 2},
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

      await tester.pumpWidget(
        MultiProvider(
          providers: [
            ChangeNotifierProvider<SrsProvider>.value(value: srs),
            ChangeNotifierProvider(create: (_) => CourseProvider(appPrefs)),
          ],
          child: const MaterialApp(
            home: AnkiReviewSessionPage(
              sectionId: 'anki-src-answer-s1',
            ),
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 20));
      await tester.pump(const Duration(milliseconds: 200));
      await tester.pump(const Duration(milliseconds: 200));

      expect(find.text(AppStrings.lessonShowAnswer), findsOneWidget);
      await tester.tap(find.text(AppStrings.lessonShowAnswer));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));

      expect(find.text(AppStrings.reviewBinaryRemembered), findsOneWidget);
      await tester.tap(find.text(AppStrings.reviewBinaryRemembered));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));

      expect(engine.officialAnswers, 1);
      expect(engine.answeredIds, contains(1));
    },
  );

  testWidgets(
    'all-decks entry (no sectionId) uses Official loader when any Official source exists',
    (tester) async {
      OfficialAnkiHomeDue.officialImportIds = {'src-all'};

      final engine = FakeOfficialAnkiEngine();
      engine.seedPackage(packagePath: 'all.apkg', notes: 2, cards: 2);

      AnkiReviewSessionPage.productionLoader =
          OfficialFormalReviewProductionLoader(
        flags: flags,
        engine: engine,
        resolveTarget: (_) async => const OfficialAnkiRoutedSource(
          importId: 'src-all',
          sourceId: 'src-all',
          deckId: 1,
          cardIds: {1, 2},
        ),
        introducedCardIds: (_) => {1, 2},
        activePlacementCardIds: (_) => {1, 2},
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

      await tester.pumpWidget(
        MultiProvider(
          providers: [
            ChangeNotifierProvider<SrsProvider>.value(value: srs),
            ChangeNotifierProvider(create: (_) => CourseProvider(appPrefs)),
          ],
          child: const MaterialApp(
            home: AnkiReviewSessionPage(),
          ),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 20));
      await tester.pump(const Duration(milliseconds: 200));
      await tester.pump(const Duration(milliseconds: 200));

      expect(find.byType(CircularProgressIndicator), findsNothing);
      expect(find.textContaining('Q1'), findsWidgets);
    },
  );
}
