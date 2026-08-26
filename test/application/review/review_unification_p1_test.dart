import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:streaming_shared_preferences/streaming_shared_preferences.dart';
import 'package:turna/application/anki_official/engine/official_anki_course_grades_bridge.dart';
import 'package:turna/application/anki_official/engine/official_formal_due_repository.dart';
import 'package:turna/application/anki_official/contract/official_anki_dto.dart';
import 'package:turna/application/anki_official/migration/official_anki_migration_dao.dart';
import 'package:turna/application/anki_official/migration/official_anki_migration_state.dart';
import 'package:turna/application/anki_official/migration/official_anki_production_router.dart';
import 'package:turna/application/anki_official/official_anki_feature_flags.dart';
import 'package:turna/application/anki_official/storage/official_anki_database.dart';
import 'package:turna/application/anki_official/storage/official_anki_source_dao.dart';
import 'package:turna/application/lesson_link_store.dart';
import 'package:turna/application/srs_provider.dart';
import 'package:turna/service/locator.dart';

import '../../helpers/in_memory_course_db.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('P1-A: SRS Queue & Due counts', () {
    late SrsProvider srsProvider;
    late AppPrefs appPrefs;

    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      final sp = await StreamingSharedPreferences.instance;
      appPrefs = AppPrefs(sp);
      await appPrefs.preferences.setString(LocalStateKeys.srsState, '{}');
      final linkStore = LessonLinkStore(appPrefs);
      final srsDao = emptySrsStateDao();
      srsProvider = SrsProvider(appPrefs, linkStore, srsDao);
    });

    test('getDueWords excludes legacy and official Anki cards', () {
      // Register standard course words
      srsProvider.registerWord('vocab-1');
      srsProvider.registerWord('vocab-2');
      // Register legacy anki cards
      srsProvider.registerWord('anki-import1-c100');
      srsProvider.registerWord('anki-import2-c200');
      // Register official anki projection cards
      srsProvider.registerWord('official-anki-src1-c300');

      final checkTime = DateTime.now().add(const Duration(seconds: 10));

      // Due words for General SRS must ONLY return the 2 course vocab words
      final dueWords = srsProvider.getDueWords(checkTime);
      expect(
          dueWords.map((w) => w.wordId), containsAll(['vocab-1', 'vocab-2']));
      expect(dueWords.any((w) => w.wordId.startsWith('anki-')), isFalse);
      expect(
          dueWords.any((w) => w.wordId.startsWith('official-anki-')), isFalse);
      expect(dueWords.length, 2);

      // dueCount & dueWordIdSet must also exclude Anki
      expect(srsProvider.dueCount, 2);
      expect(srsProvider.dueWordIdSet, {'vocab-1', 'vocab-2'});

      // getDueAnkiWords must return Anki items
      final ankiDue = srsProvider.getDueAnkiWords(checkTime);
      expect(ankiDue.length, 3);
      expect(
        ankiDue.map((w) => w.wordId),
        containsAll([
          'anki-import1-c100',
          'anki-import2-c200',
          'official-anki-src1-c300',
        ]),
      );
    });
  });

  group('P1-A: Official Due Count without fake splitting', () {
    test('Multiple targets do not divide total due into fake fractions',
        () async {
      final db = OfficialAnkiDatabase.memory();
      addTearDown(db.close);

      final sources = OfficialAnkiSourceDao(db);
      sources.upsertSource(
        sourceId: 'src-1',
        profileId: 'profile-default-01',
        sourceHash: 'hash1',
        sourceSize: 1,
        displayName: 'Deck 1',
        state: 'active',
        backendCommit: 'x',
        nowMillis: 1,
      );
      sources.upsertSource(
        sourceId: 'src-2',
        profileId: 'profile-default-01',
        sourceHash: 'hash2',
        sourceSize: 1,
        displayName: 'Deck 2',
        state: 'active',
        backendCommit: 'x',
        nowMillis: 1,
      );

      db.handle.execute(
        'INSERT INTO anki_source_cards (source_id, card_id, note_id, deck_id, note_guid, template_ord) '
        "VALUES ('src-1', 101, 1, 1, 'g1', 0), ('src-2', 102, 2, 2, 'g2', 0)",
      );

      final dao = OfficialAnkiMigrationDao(db);
      dao.insertDetected(
        migrationId: 'mig-1',
        profileId: 'profile-default-01',
        legacyImportId: 'import-1',
        policy: LegacyAnkiSchedulingPolicy.preservePackageScheduling,
        nowMillis: 1,
      );
      dao.transition(
        migrationId: 'mig-1',
        expected: LegacyAnkiMigrationState.detected,
        next: LegacyAnkiMigrationState.awaitingPackage,
        nowMillis: 2,
        officialSourceId: 'src-1',
      );
      dao.setRecordedKind(
        migrationId: 'mig-1',
        recordedKind: 'official',
        nowMillis: 3,
      );

      dao.insertDetected(
        migrationId: 'mig-2',
        profileId: 'profile-default-01',
        legacyImportId: 'import-2',
        policy: LegacyAnkiSchedulingPolicy.preservePackageScheduling,
        nowMillis: 1,
      );
      dao.transition(
        migrationId: 'mig-2',
        expected: LegacyAnkiMigrationState.detected,
        next: LegacyAnkiMigrationState.awaitingPackage,
        nowMillis: 2,
        officialSourceId: 'src-2',
      );
      dao.setRecordedKind(
        migrationId: 'mig-2',
        recordedKind: 'official',
        nowMillis: 3,
      );

      final repo = OfficialFormalDueRepository.instance;
      repo.resetForTest();
      const router = OfficialAnkiProductionRouter();
      final collected = await router.collectFormalDueCardIds(
        dao: dao,
        sources: sources,
        cutoverEnabled: true,
        setCurrentDeck: (_) async {},
        getReviewQueue: ({int fetchLimit = 500}) async => OfficialReviewQueue(
          sessionId: 's1',
          queueEpoch: 1,
          newCount: 5,
          learningCount: 2,
          reviewCount: 3,
          cards: const [],
        ),
      );

      // No queue cards → no per-import scheduler due; formal due is
      // derived (introduced-only, plan 34 D6) so neither import gets a
      // fake share of the queue meta total.
      expect(collected.rawDueByImport['import-1'], 0);
      expect(collected.rawDueByImport['import-2'], 0);
      expect(
        collected.inputs
            .where((i) => !i.schedulerDueSynced)
            .isEmpty,
        isTrue,
      );
    });

    test('deck tree assigns exact per-import counts including learning',
        () async {
      final db = OfficialAnkiDatabase.memory();
      addTearDown(db.close);
      final sources = OfficialAnkiSourceDao(db);
      final dao = OfficialAnkiMigrationDao(db);
      _addOfficialImport(
        db: db,
        sources: sources,
        dao: dao,
        importId: 'import-a',
        sourceId: 'source-a',
        deckId: 101,
        cardId: 1001,
      );
      _addOfficialImport(
        db: db,
        sources: sources,
        dao: dao,
        importId: 'import-b',
        sourceId: 'source-b',
        deckId: 202,
        cardId: 2002,
      );

      final counts =
          await const OfficialAnkiProductionRouter().collectHomeDueFromDeckTree(
        dao: dao,
        sources: sources,
        cutoverEnabled: true,
        getDeckTree: () async => const [
          OfficialAnkiDeckNode(
            deckId: 101,
            name: 'A',
            newCount: 2,
            learnCount: 3,
            reviewCount: 4,
          ),
          OfficialAnkiDeckNode(
            deckId: 202,
            name: 'B',
            newCount: 1,
            learnCount: 2,
            reviewCount: 3,
          ),
        ],
      );

      expect(counts.total, 15);
      expect(counts.dueByImport['import-a'], 9);
      expect(counts.dueByImport['import-b'], 6);
    });

    test('selected parent owns descendant due count exactly once', () async {
      final db = OfficialAnkiDatabase.memory();
      addTearDown(db.close);
      final sources = OfficialAnkiSourceDao(db);
      final dao = OfficialAnkiMigrationDao(db);
      _addOfficialImport(
        db: db,
        sources: sources,
        dao: dao,
        importId: 'parent-import',
        sourceId: 'parent-source',
        deckId: 10,
        cardId: 100,
      );
      _addOfficialImport(
        db: db,
        sources: sources,
        dao: dao,
        importId: 'child-import',
        sourceId: 'child-source',
        deckId: 11,
        cardId: 110,
      );

      final counts =
          await const OfficialAnkiProductionRouter().collectHomeDueFromDeckTree(
        dao: dao,
        sources: sources,
        cutoverEnabled: true,
        getDeckTree: () async => const [
          OfficialAnkiDeckNode(
            deckId: 10,
            name: 'Parent',
            level: 0,
            newCount: 2,
            learnCount: 1,
            reviewCount: 2,
          ),
          OfficialAnkiDeckNode(
            deckId: 11,
            name: 'Parent::Child',
            level: 1,
            newCount: 1,
            reviewCount: 2,
          ),
        ],
      );

      expect(counts.total, 5);
      expect(counts.dueByImport['parent-import'], 5);
      expect(counts.dueByImport['child-import'], 0);
    });
  });

  group('P1-B: Official Bridge Callback Safety', () {
    const fullFlags = OfficialAnkiFeatureFlags(
      engine: true,
      import: true,
      catalogReady: true,
      runtimeCapable: true,
      platformReady: true,
      renderer: true,
      scheduler: true,
      courseGradesScheduler: true,
    );

    test(
        'answerOfficialCard returns false when no onAnswer callback is injected',
        () async {
      const bridge = OfficialAnkiCourseGradesBridgeImpl(
        flags: fullFlags,
        onAnswer: null,
      );

      final result = await bridge.answerOfficialCard(
        wordId: 'official-anki-src1-c123',
        rating: 'good',
      );

      expect(result, isFalse,
          reason: 'Must not return fake success when unhandled');
    });

    test('answerOfficialCard forwards to callback when injected', () async {
      var calledCardId = 0;
      var calledRating = '';
      final bridge = OfficialAnkiCourseGradesBridgeImpl(
        flags: fullFlags,
        onAnswer: (cardId, rating, ms) async {
          calledCardId = cardId;
          calledRating = rating;
          return true;
        },
      );

      final result = await bridge.answerOfficialCard(
        wordId: 'official-anki-src1-c999',
        rating: 'again',
      );

      expect(result, isTrue);
      expect(calledCardId, 999);
      expect(calledRating, 'again');
    });
  });
}

void _addOfficialImport({
  required OfficialAnkiDatabase db,
  required OfficialAnkiSourceDao sources,
  required OfficialAnkiMigrationDao dao,
  required String importId,
  required String sourceId,
  required int deckId,
  required int cardId,
}) {
  sources.upsertSource(
    sourceId: sourceId,
    profileId: OfficialAnkiProductionRouter.defaultProfileId,
    sourceHash: 'hash-$sourceId',
    sourceSize: 1,
    displayName: sourceId,
    state: 'active',
    backendCommit: 'test',
    nowMillis: 1,
  );
  db.handle.execute(
    'INSERT INTO anki_source_cards '
    '(source_id, card_id, note_id, deck_id, note_guid, template_ord) '
    'VALUES (?, ?, ?, ?, ?, 0)',
    [sourceId, cardId, cardId, deckId, 'guid-$cardId'],
  );
  dao.insertDetected(
    migrationId: 'migration-$importId',
    profileId: OfficialAnkiProductionRouter.defaultProfileId,
    legacyImportId: importId,
    policy: LegacyAnkiSchedulingPolicy.preservePackageScheduling,
    nowMillis: 1,
  );
  dao.transition(
    migrationId: 'migration-$importId',
    expected: LegacyAnkiMigrationState.detected,
    next: LegacyAnkiMigrationState.awaitingPackage,
    nowMillis: 2,
    officialSourceId: sourceId,
  );
  dao.setRecordedKind(
    migrationId: 'migration-$importId',
    recordedKind: 'official',
    nowMillis: 3,
  );
}
