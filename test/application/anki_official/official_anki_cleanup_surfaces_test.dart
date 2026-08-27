// P5F-3 cleanup-surface tests: catalog deleteSource, seeder reseed guard
// for projection tables, uninstall routing (+ legacy substring regression),
// the projection vocabulary channel, and the hard-uninstall surface
// (official collection deleteNotes + app-side records + mistake log).

// Dart imports:
import 'dart:convert';

// Package imports:
import 'package:drift/drift.dart' show Variable;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:streaming_shared_preferences/streaming_shared_preferences.dart';
import 'package:turna/application/anki_official/anki_deck_manager.dart';
import 'package:turna/application/anki_official/contract/official_anki_dto.dart';
import 'package:turna/application/anki_official/engine/official_anki_engine_fake.dart';
import 'package:turna/application/anki_official/official_anki_composition.dart';
import 'package:turna/application/lesson_link_store.dart';
import 'package:turna/application/mistake_provider.dart';
import 'package:turna/application/srs_provider.dart';
import 'package:turna/application/anki_official/projection/official_anki_projection_projector.dart';
import 'package:turna/application/anki_official/projection/official_anki_projection_store.dart';
import 'package:turna/application/anki_official/storage/official_anki_database.dart';
import 'package:turna/application/anki_official/storage/official_anki_source_dao.dart';
import 'package:turna/application/course_catalog.dart';
import 'package:turna/data/anki_import_dao.dart';
import 'package:turna/data/anki_note_dao.dart';
import 'package:turna/data/anki_owner_authority_dao.dart';
import 'package:turna/data/anki_unification_dao.dart';
import 'package:turna/data/course_database.dart';
import 'package:turna/data/course_database_seeder.dart';
import 'package:turna/data/course_repository.dart';
import 'package:turna/data/review_history_dao.dart';
import 'package:turna/data/srs_state_dao.dart';
import 'package:turna/domain/anki/canonical_card_key.dart';
import 'package:turna/domain/anki/card_introduction_state.dart';
import 'package:turna/domain/course/interaction.dart';
import 'package:turna/domain/course/mistake_entry.dart';
import 'package:turna/domain/repositories/i_course_repository.dart';
import 'package:turna/service/locator.dart';

import '../../helpers/in_memory_course_db.dart';

Future<int> _count(CourseDatabase db, String sql) async {
  final rows = await db.customSelect(sql).get();
  return rows.isEmpty ? 0 : rows.first.read<int>('n');
}

OfficialAnkiProjectedItem _item(
  String sourceId,
  int cardId, {
  OfficialAnkiProjectedVocabulary? vocabulary,
}) {
  const suffix = '-s1';
  return OfficialAnkiProjectedItem(
    kind: OfficialAnkiProjectionKind.showWord,
    cardId: cardId,
    wordId: 'official-anki-profile-default-01-c$cardId',
    sectionId: 'official-anki-$sourceId$suffix',
    unitId: 'official-anki-$sourceId-u1',
    lessonId: 'official-anki-$sourceId-l1-p1',
    sectionName: 'Section $sourceId',
    unitName: 'Unit',
    lessonName: 'Lesson',
    payload: <String, Object?>{'runtimeType': 'ShowWord', 'id': 'i$cardId'},
    sourceFingerprint: 'fp-$sourceId',
    vocabulary: vocabulary,
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  ensureSqliteLibForTestHost();

  group('p5f deleteSource cleans every catalog row', () {
    test('removes source, cards, attempts, state, migration chain', () {
      final catalog = OfficialAnkiDatabase.memory();
      addTearDown(catalog.close);
      final sources = OfficialAnkiSourceDao(catalog);
      sources.upsertSource(
        sourceId: 'src-1',
        profileId: 'profile-default-01',
        sourceHash: 'hash-1',
        sourceSize: 10,
        displayName: 'deck',
        state: 'active',
        backendCommit: 'test',
        nowMillis: 1,
      );
      sources.replaceCards(sourceId: 'src-1', cards: const []);
      catalog.handle.execute(
        "INSERT INTO anki_import_attempts (attempt_id, source_id, request_id, "
        "state, started_at_millis, heartbeat_at_millis) VALUES ('att-1', "
        "'src-1', 'req-1', 'active', 1, 1)",
      );
      catalog.handle.execute(
        'INSERT INTO anki_import_attempt_notes (attempt_id, ordinal, note_id) '
        "VALUES ('att-1', 0, 100)",
      );
      catalog.handle.execute(
        "INSERT INTO anki_source_projection_state (source_id, state, "
        "active_projection_version, source_fingerprint, projected_card_count, "
        "last_projected_at_millis) VALUES ('src-1', 'active', 1, 'fp', 1, 1)",
      );
      final migrationDao = catalog.handle;
      migrationDao.execute(
        "INSERT INTO legacy_anki_migrations (migration_id, profile_id, "
        "legacy_import_id, official_source_id, state, scheduling_policy, "
        "source_hash, legacy_card_count, matched_card_count, recorded_kind, "
        "started_at_millis, updated_at_millis) VALUES ('mig-1', "
        "'profile-default-01', 'imp-1', 'src-1', 'observing', "
        "'preservePackageScheduling', 'hash-1', 1, 1, 'official', 1, 1)",
      );
      migrationDao.execute(
        "INSERT INTO legacy_anki_card_map (migration_id, legacy_card_id, "
        "legacy_word_id, template_ord, match_method, match_state) "
        "VALUES ('mig-1', 5, 'anki-imp-1-c5', 0, 'guid', 'matched')",
      );

      final deleted = sources.deleteSource(
        profileId: 'profile-default-01',
        sourceId: 'src-1',
      );
      expect(deleted, isTrue);
      for (final table in const [
        'anki_sources',
        'anki_source_cards',
        'anki_import_attempts',
        'anki_import_attempt_notes',
        'anki_source_projection_state',
        'legacy_anki_migrations',
        'legacy_anki_card_map',
      ]) {
        final n = catalog.handle
            .select('SELECT COUNT(*) AS n FROM $table')
            .first['n'] as int;
        expect(n, 0, reason: '$table must be empty');
      }
      expect(
        sources.deleteSource(
          profileId: 'profile-default-01',
          sourceId: 'missing',
        ),
        isFalse,
      );
    });
  });

  group('p5f seeder reseed guard', () {
    test('reseed drops projection index/manifest so publish is not a no-op',
        () async {
      final db = CourseDatabase(NativeDatabase.memory());
      addTearDown(db.close);
      await DatabaseSeeder(db).seedIfNeeded();
      final store = OfficialAnkiCourseProjectionStore(db);
      await store.replaceOfficialProjection(
        sourceId: 'src-r',
        plan: OfficialAnkiProjectionPlan(
          items: [_item('src-r', 1), _item('src-r', 2)],
          issues: const [],
        ),
        sourceFingerprint: 'fp-r',
      );
      expect(
        await _count(
            db, 'SELECT COUNT(*) AS n FROM official_anki_projection_index'),
        2,
      );
      expect(
        await _count(
            db, 'SELECT COUNT(*) AS n FROM official_anki_projection_manifest'),
        1,
      );

      // Force a reseed by storing a stale content version.
      await db.customStatement(
        "INSERT OR REPLACE INTO course_meta (key, value) VALUES "
        "('contentVersion', 'stale-version')",
      );
      await DatabaseSeeder(db).seedIfNeeded();

      expect(
        await _count(
            db, 'SELECT COUNT(*) AS n FROM official_anki_projection_index'),
        0,
        reason: 'reseed must invalidate the projection index',
      );
      expect(
        await _count(
            db, 'SELECT COUNT(*) AS n FROM official_anki_projection_manifest'),
        0,
        reason: 'reseed must drop the manifest so the fingerprint no-op '
            'cannot skip republishing',
      );
    });
  });

  group('p5f projection vocabulary channel', () {
    late CourseDatabase db;
    late OfficialAnkiCourseProjectionStore store;

    setUp(() {
      db = CourseDatabase(NativeDatabase.memory());
      store = OfficialAnkiCourseProjectionStore(db);
    });

    tearDown(() => db.close());

    test('writes one tagged row per card and replaces on republish', () async {
      // A built-in vocabulary row must survive every projection write.
      await db.customStatement(
        "INSERT INTO vocabulary (id, term, translation, tags) VALUES "
        "('builtin-1', 'ev', 'house', '[\"builtin\"]')",
      );
      await store.replaceOfficialProjection(
        sourceId: 'src-v',
        plan: OfficialAnkiProjectionPlan(
          items: [
            _item(
              'src-v',
              11,
              vocabulary: const OfficialAnkiProjectedVocabulary(
                term: 'merhaba',
                translation: 'hello',
                pronunciation: 'meɾhaba',
                audioAsset: 'hello.mp3',
              ),
            ),
            _item('src-v', 12), // no usable term pair -> no row
          ],
          issues: const [],
        ),
      );
      final rows = await db.customSelect(
        "SELECT id, term, translation, pronunciation, audio_asset, tags "
        'FROM vocabulary WHERE tags LIKE ?',
        variables: [Variable('%official:src-v%')],
      ).get();
      expect(rows.length, 1);
      final row = rows.single;
      expect(row.read<String>('id'), 'official-anki-profile-default-01-c11');
      expect(row.read<String>('term'), 'merhaba');
      expect(row.read<String>('translation'), 'hello');
      expect(row.read<String>('pronunciation'), 'meɾhaba');
      expect(row.read<String>('audio_asset'), 'hello.mp3');
      expect(
        (jsonDecode(row.read<String>('tags')) as List)
            .contains('official:src-v'),
        isTrue,
      );

      // Republish with a changed card set: old row replaced by index-driven
      // delete, new row written, built-in row untouched.
      await store.replaceOfficialProjection(
        sourceId: 'src-v',
        plan: OfficialAnkiProjectionPlan(
          items: [
            _item(
              'src-v',
              13,
              vocabulary: const OfficialAnkiProjectedVocabulary(
                term: 'günaydın',
                translation: 'good morning',
              ),
            ),
          ],
          issues: const [],
        ),
      );
      final after = await db
          .customSelect(
            'SELECT id FROM vocabulary ORDER BY id',
          )
          .get();
      expect(after.map((r) => r.read<String>('id')), [
        'builtin-1',
        'official-anki-profile-default-01-c13',
      ]);
    });

    test('deleteOfficialProjection removes vocabulary rows', () async {
      await store.replaceOfficialProjection(
        sourceId: 'src-v',
        plan: OfficialAnkiProjectionPlan(
          items: [
            _item(
              'src-v',
              21,
              vocabulary: const OfficialAnkiProjectedVocabulary(
                term: 'a',
                translation: 'b',
              ),
            ),
          ],
          issues: const [],
        ),
      );
      await store.deleteOfficialProjection('src-v');
      expect(
        await _count(db, 'SELECT COUNT(*) AS n FROM vocabulary'),
        0,
      );
    });
  });

  group('p5f uninstall routing', () {
    late CourseDatabase db;
    late AnkiDeckManager manager;
    late AnkiUnificationDao unification;
    late OfficialAnkiDatabase catalog;

    setUp(() async {
      ensurePathProviderMockForTest();
      SharedPreferences.setMockInitialValues({});
      final preferences = await StreamingSharedPreferences.instance;
      final appPrefs = AppPrefs(preferences);
      db = CourseDatabase(NativeDatabase.memory());
      final getIt = GetIt.instance;
      await getIt.reset();
      final repo = CourseRepository(db);
      getIt.registerSingleton<ICourseRepository>(repo);
      getIt.registerSingleton<AnkiImportDao>(AnkiImportDao(db));
      getIt.registerSingleton<AnkiNoteDao>(AnkiNoteDao(db));
      unification = AnkiUnificationDao(db);
      getIt.registerSingleton<AnkiUnificationDao>(unification);
      manager = AnkiDeckManager(
        repo: repo,
        srsProvider: SrsProvider(
          appPrefs,
          LessonLinkStore(appPrefs),
          SrsStateDao(db),
        ),
        importDao: getIt<AnkiImportDao>(),
        noteDao: getIt<AnkiNoteDao>(),
        appPrefs: appPrefs,
        unificationDao: unification,
      );
      // The uninstall saga now consults the migration link table before
      // touching anything; give it an isolated in-memory catalog so the
      // lookup never falls through to a locator on the host filesystem.
      catalog = OfficialAnkiDatabase.memory();
      OfficialAnkiCompositionRoot.readOnlyCatalog = catalog;
    });

    tearDown(() async {
      OfficialAnkiCompositionRoot.readOnlyCatalog = null;
      OfficialAnkiCompositionRoot.locatorPaths = null;
      catalog.close();
      await GetIt.instance.reset();
    });

    test('legacy uninstall no longer matches prefix-sibling sections',
        () async {
      await db.customStatement(
        "INSERT INTO sections (id, name, level, sort_order) VALUES "
        "('anki-user-s1', 'User', 'Anki', 0), "
        "('anki-user2-s1', 'User2', 'Anki', 1)",
      );
      await manager.uninstallDeck('user');
      final left = await db.customSelect('SELECT id FROM sections').get();
      expect(left.map((r) => r.read<String>('id')), ['anki-user2-s1'],
          reason: 'uninstalling "user" must not delete "user2"');
    });

    test(
        'official source uninstall cleans tree, unification; keeps legacy '
        'tables', () async {
      final store = OfficialAnkiCourseProjectionStore(db);
      await store.replaceOfficialProjection(
        sourceId: 'src-o',
        plan: OfficialAnkiProjectionPlan(
          items: [
            _item(
              'src-o',
              31,
              vocabulary: const OfficialAnkiProjectedVocabulary(
                term: 't',
                translation: 'tr',
              ),
            ),
          ],
          issues: const [],
        ),
      );
      await unification.insertActivePlacement(
        placementId: 'official-anki-src-o-31',
        courseId: 'official-anki-src-o',
        profileId: 'profile-default-01',
        key: const CanonicalCardKey(
          backend: AnkiBackendKind.official,
          profileId: 'profile-default-01',
          sourceId: 'src-o',
          cardId: 31,
        ),
        sectionId: 'official-anki-src-o-s1',
        unitId: 'official-anki-src-o-u1',
        lessonId: 'official-anki-src-o-l1-p1',
        order: 0,
        sourceFingerprint: 'fp',
      );

      await manager.uninstall('src-o');

      expect(await _count(db, 'SELECT COUNT(*) AS n FROM sections'), 0);
      expect(await _count(db, 'SELECT COUNT(*) AS n FROM vocabulary'), 0);
      expect(
        await _count(
            db, 'SELECT COUNT(*) AS n FROM anki_course_card_placements'),
        0,
      );
      expect(
        await _count(
            db, 'SELECT COUNT(*) AS n FROM official_anki_projection_index'),
        0,
      );
    });
  });

  group('hard uninstall', () {
    late CourseDatabase db;
    late AnkiDeckManager manager;
    late MistakeProvider mistakes;
    late ReviewHistoryDao reviewHistory;
    late AnkiUnificationDao unification;
    late AnkiOwnerAuthorityDao authority;
    late OfficialAnkiDatabase catalog;
    late FakeOfficialAnkiEngine engine;

    setUp(() async {
      ensurePathProviderMockForTest();
      SharedPreferences.setMockInitialValues({});
      final preferences = await StreamingSharedPreferences.instance;
      final appPrefs = AppPrefs(preferences);
      await appPrefs.preferences.setString(LocalStateKeys.mistakeLog, '[]');
      db = CourseDatabase(NativeDatabase.memory());
      mistakes = MistakeProvider(appPrefs);
      reviewHistory = ReviewHistoryDao(db);
      unification = AnkiUnificationDao(db);
      authority = AnkiOwnerAuthorityDao(db);
      final getIt = GetIt.instance;
      await getIt.reset();
      final repo = CourseRepository(db);
      getIt.registerSingleton<ICourseRepository>(repo);
      getIt.registerSingleton<AnkiImportDao>(AnkiImportDao(db));
      getIt.registerSingleton<AnkiNoteDao>(AnkiNoteDao(db));
      getIt.registerSingleton<AnkiUnificationDao>(unification);
      getIt.registerSingleton<AnkiOwnerAuthorityDao>(authority);
      manager = AnkiDeckManager(
        repo: repo,
        srsProvider: SrsProvider(
          appPrefs,
          LessonLinkStore(appPrefs),
          SrsStateDao(db),
        ),
        importDao: getIt<AnkiImportDao>(),
        noteDao: getIt<AnkiNoteDao>(),
        appPrefs: appPrefs,
        unificationDao: unification,
        mistakeProvider: mistakes,
        reviewHistoryDao: reviewHistory,
      );

      catalog = OfficialAnkiDatabase.memory();
      OfficialAnkiCompositionRoot.readOnlyCatalog = catalog;
      engine = FakeOfficialAnkiEngine();
      OfficialAnkiCompositionRoot.debugEngineOverride = engine;
    });

    tearDown(() async {
      OfficialAnkiCompositionRoot.debugEngineOverride = null;
      OfficialAnkiCompositionRoot.readOnlyCatalog = null;
      OfficialAnkiCompositionRoot.locatorPaths = null;
      catalog.close();
      await db.close();
      await GetIt.instance.reset();
    });

    MistakeEntry mistake(
      String id, {
      required String lessonId,
      String? wordId,
    }) =>
        MistakeEntry(
          id: id,
          lessonId: lessonId,
          stageId: 'stage-1',
          interactionId: 'item-$id',
          wordId: wordId,
          interactionSnapshot: Interaction.multipleChoice(
            id: 'item-$id',
            prompt: 'Pick one',
            options: const ['a', 'b'],
            correctIndex: 0,
          ),
          userAnswer: 'wrong',
          correctAnswer: 'a',
          timestamp: DateTime(2026, 8, 1),
        );

    Future<void> seedOfficialAuthority(String sourceId) {
      return authority.upsertSource(
        courseId: 'official-anki-$sourceId',
        profileId: 'profile-default-01',
        sourceId: sourceId,
        backendKind: 'official',
        displayName: 'Deck $sourceId',
        sourceHash: 'hash-$sourceId',
        sourceFingerprint: 'fp-$sourceId',
        state: AnkiSourceVisibility.active,
      );
    }

    test('official source uninstall deletes collection notes and mistakes',
        () async {
      await seedOfficialAuthority('src-h');
      final sources = OfficialAnkiSourceDao(catalog);
      sources.upsertSource(
        sourceId: 'src-h',
        profileId: 'profile-default-01',
        sourceHash: 'hash-h',
        sourceSize: 10,
        displayName: 'deck',
        state: 'active',
        backendCommit: 'test',
        nowMillis: 1,
      );
      sources.replaceCards(
        sourceId: 'src-h',
        cards: const [
          OfficialAnkiCardDescriptor(
            cardId: 51,
            noteId: 500,
            deckId: 1,
            templateOrd: 0,
          ),
          OfficialAnkiCardDescriptor(
            cardId: 52,
            noteId: 501,
            deckId: 1,
            templateOrd: 0,
          ),
        ],
      );
      engine.cards.addAll({
        51: const OfficialAnkiCardDescriptor(
          cardId: 51,
          noteId: 500,
          deckId: 1,
          templateOrd: 0,
        ),
        52: const OfficialAnkiCardDescriptor(
          cardId: 52,
          noteId: 501,
          deckId: 1,
          templateOrd: 0,
        ),
      });
      engine.cardsByNote.addAll({
        500: [51],
        501: [52],
      });
      await OfficialAnkiCourseProjectionStore(db).replaceOfficialProjection(
        sourceId: 'src-h',
        plan: OfficialAnkiProjectionPlan(
          items: [_item('src-h', 51)],
          issues: const [],
        ),
        sourceFingerprint: 'fp-h',
      );
      await mistakes.record(mistake(
        'm-practice',
        lessonId: 'official-review',
        wordId: 'official-anki-review-c51',
      ));
      await mistakes.record(mistake(
        'm-course',
        lessonId: 'official-anki-src-h-l1-p1', // course path, wordId null
      ));
      await mistakes.record(mistake(
        'm-kept',
        lessonId: 'official-review',
        wordId: 'official-anki-review-c77',
      ));

      expect(await manager.uninstall('src-h'), isTrue);

      expect(engine.deletedNoteIds, const {500, 501});
      expect(
        catalog.handle
            .select('SELECT COUNT(*) AS n FROM anki_sources')
            .first['n'],
        0,
      );
      expect(
        catalog.handle
            .select('SELECT COUNT(*) AS n FROM anki_source_cards')
            .first['n'],
        0,
      );
      expect(mistakes.entries.map((e) => e.id), {'m-kept'});
      expect(
        (await authority.findBySource(
          profileId: 'profile-default-01',
          sourceId: 'src-h',
        ))
            ?.state,
        AnkiSourceVisibility.retired,
      );
      final entries = await CourseCatalog.load(
        shells: await CourseRepository(db).sectionShells(),
        courseDb: db,
      );
      expect(
        entries.any((entry) => entry.officialSourceId == 'src-h'),
        isFalse,
        reason: 'a successful uninstall must not leave a course-management '
            'authority ghost',
      );

      // The retained retired authority still routes a repeated cleanup as
      // Official even though its projection and catalog rows are already gone.
      expect(await manager.uninstall('src-h'), isTrue);
    });

    test('official uninstall retains sibling cards and shared notes',
        () async {
      await seedOfficialAuthority('src-a');
      final sources = OfficialAnkiSourceDao(catalog);
      for (final sourceId in const ['src-a', 'src-b']) {
        sources.upsertSource(
          sourceId: sourceId,
          profileId: 'profile-default-01',
          sourceHash: 'hash-$sourceId',
          sourceSize: 10,
          displayName: sourceId,
          state: 'active',
          backendCommit: 'test',
          nowMillis: 1,
        );
      }
      sources.replaceCards(
        sourceId: 'src-a',
        cards: const [
          OfficialAnkiCardDescriptor(
            cardId: 51,
            noteId: 500,
            deckId: 1,
            templateOrd: 0,
          ),
          OfficialAnkiCardDescriptor(
            cardId: 52,
            noteId: 501,
            deckId: 1,
            templateOrd: 0,
          ),
        ],
      );
      sources.replaceCards(
        sourceId: 'src-b',
        cards: const [
          OfficialAnkiCardDescriptor(
            cardId: 51,
            noteId: 500,
            deckId: 1,
            templateOrd: 0,
          ),
          OfficialAnkiCardDescriptor(
            cardId: 53,
            noteId: 500,
            deckId: 1,
            templateOrd: 1,
          ),
        ],
      );
      engine.cards.addAll({
        51: const OfficialAnkiCardDescriptor(
          cardId: 51,
          noteId: 500,
          deckId: 1,
          templateOrd: 0,
        ),
        52: const OfficialAnkiCardDescriptor(
          cardId: 52,
          noteId: 501,
          deckId: 1,
          templateOrd: 0,
        ),
        53: const OfficialAnkiCardDescriptor(
          cardId: 53,
          noteId: 500,
          deckId: 1,
          templateOrd: 1,
        ),
      });
      engine.cardsByNote.addAll({
        500: [51, 53],
        501: [52],
      });

      expect(await manager.uninstall('src-a'), isTrue);

      expect(engine.cards.keys, {51, 53});
      expect(engine.deletedNoteIds, {501});
      expect(sources.findById('src-b'), isNotNull);
      expect(sources.listCards('src-b').map((card) => card.cardId), {51, 53});
    });

    test('active authority ghost without projection can still be retired',
        () async {
      await seedOfficialAuthority('src-ghost');

      expect(await manager.uninstall('src-ghost'), isTrue);
      expect(
        (await authority.findBySource(
          profileId: 'profile-default-01',
          sourceId: 'src-ghost',
        ))
            ?.state,
        AnkiSourceVisibility.retired,
      );
    });

    test('startup retry also discovers authority-only pending cleanup',
        () async {
      await seedOfficialAuthority('src-pending-ghost');
      await authority.commitVisibility(
        courseId: 'official-anki-src-pending-ghost',
        state: AnkiSourceVisibility.pendingCleanup,
      );

      expect(await manager.retryPendingOfficialCleanups(), 1);
      expect(
        (await authority.findBySource(
          profileId: 'profile-default-01',
          sourceId: 'src-pending-ghost',
        ))
            ?.state,
        AnkiSourceVisibility.retired,
      );
    });

    test('legacy deck uninstall deletes records, history, and mistakes',
        () async {
      await db.customStatement(
        "INSERT INTO sections (id, name, level, sort_order) VALUES "
        "('anki-user-s1', 'User', 'Anki', 0)",
      );
      await reviewHistory.insertEvent(ReviewEventRecord(
        cardId: 'anki-user-c5',
        queue: 'new',
        reviewedAt: DateTime(2026, 8, 1),
        quality: 2,
        prevIntervalDays: 0,
        nextIntervalDays: 1,
        prevEase: 2.5,
        nextEase: 2.5,
        reps: 1,
        lapses: 1,
      ));
      await reviewHistory.insertEvent(ReviewEventRecord(
        cardId: 'anki-user2-c5',
        queue: 'new',
        reviewedAt: DateTime(2026, 8, 1),
        quality: 2,
        prevIntervalDays: 0,
        nextIntervalDays: 1,
        prevEase: 2.5,
        nextEase: 2.5,
        reps: 1,
        lapses: 1,
      ));
      await unification.upsertIntroduction(
        courseId: 'anki-user',
        key: const CanonicalCardKey(
          backend: AnkiBackendKind.legacyTurna,
          profileId: 'profile-default-01',
          sourceId: 'user',
          cardId: 5,
        ),
        status: CardIntroductionStatus.introduced,
      );
      await mistakes.record(mistake(
        'm-course',
        lessonId: 'anki-user-u1-l0-s0',
      ));
      await mistakes.record(mistake(
        'm-review',
        lessonId: 'srs-review',
        wordId: 'anki-user-c5',
      ));
      await mistakes.record(mistake(
        'm-sibling',
        lessonId: 'anki-user2-u1-l0-s0',
      ));

      await manager.uninstallDeck('user');

      expect(
        await _count(db,
            "SELECT COUNT(*) AS n FROM review_events WHERE card_id = 'anki-user-c5'"),
        0,
      );
      expect(
        await _count(db,
            "SELECT COUNT(*) AS n FROM review_events WHERE card_id = 'anki-user2-c5'"),
        1,
        reason: 'prefix sibling history must survive',
      );
      expect(
        await _count(db,
            "SELECT COUNT(*) AS n FROM anki_card_introduction_states WHERE course_id = 'anki-user'"),
        0,
      );
      expect(mistakes.entries.map((e) => e.id), {'m-sibling'});
      expect(engine.deletedNoteIds, isEmpty,
          reason: 'legacy uninstall never touches the official collection');
    });

    test(
        'mirrored import uninstall resolves via migration link and clears '
        'both owners', () async {
      await seedOfficialAuthority('src-m');
      final sources = OfficialAnkiSourceDao(catalog);
      sources.upsertSource(
        sourceId: 'src-m',
        profileId: 'profile-default-01',
        sourceHash: 'hash-m',
        sourceSize: 10,
        displayName: 'mirrored deck',
        state: 'active',
        backendCommit: 'test',
        nowMillis: 1,
      );
      sources.replaceCards(
        sourceId: 'src-m',
        cards: const [
          OfficialAnkiCardDescriptor(
            cardId: 61,
            noteId: 600,
            deckId: 1,
            templateOrd: 0,
          ),
        ],
      );
      engine.cards[61] = const OfficialAnkiCardDescriptor(
        cardId: 61,
        noteId: 600,
        deckId: 1,
        templateOrd: 0,
      );
      engine.cardsByNote[600] = [61];
      // The legacy↔official link is the authoritative ownership record.
      catalog.handle.execute(
        "INSERT INTO legacy_anki_migrations (migration_id, profile_id, "
        "legacy_import_id, official_source_id, state, scheduling_policy, "
        "source_hash, legacy_card_count, matched_card_count, recorded_kind, "
        "started_at_millis, updated_at_millis) VALUES ('mig-m', "
        "'profile-default-01', 'imp-m', 'src-m', 'observing', "
        "'preservePackageScheduling', 'hash-m', 1, 1, 'official', 1, 1)",
      );
      // Legacy side: import row and course tree. The official-side tree is
      // created by the projection write below.
      await db.customStatement(
        "INSERT INTO anki_imports (import_id, source_path, source_hash, "
        "imported_at) VALUES ('imp-m', '/tmp/m.apkg', 'hash-m', 1)",
      );
      await db.customStatement(
        "INSERT INTO sections (id, name, level, sort_order) VALUES "
        "('anki-imp-m-s1', 'Mirrored', 'Anki', 0)",
      );
      await OfficialAnkiCourseProjectionStore(db).replaceOfficialProjection(
        sourceId: 'src-m',
        plan: OfficialAnkiProjectionPlan(
          items: [_item('src-m', 61)],
          issues: const [],
        ),
        sourceFingerprint: 'fp-m',
      );

      expect(await manager.uninstall('imp-m'), isTrue);

      expect(engine.deletedNoteIds, const {600},
          reason: 'the official mirror loses its collection notes');
      expect(
        catalog.handle
            .select('SELECT COUNT(*) AS n FROM anki_sources')
            .first['n'],
        0,
        reason: 'catalog source row is gone',
      );
      expect(
        catalog.handle
            .select('SELECT COUNT(*) AS n FROM legacy_anki_migrations')
            .first['n'],
        0,
        reason: 'the migration link is retired with the source',
      );
      final sections = await db.customSelect('SELECT id FROM sections').get();
      expect(sections, isEmpty,
          reason: 'both legacy and official tree sections are removed');
      expect(
        await _count(db,
            "SELECT COUNT(*) AS n FROM anki_imports WHERE import_id = 'imp-m'"),
        0,
        reason: 'the legacy import record is removed',
      );
      expect(
        await _count(
            db, 'SELECT COUNT(*) AS n FROM official_anki_projection_index'),
        0,
      );
    });

    test(
        'collection delete failure marks pending_cleanup and keeps owner '
        'rows; retry completes', () async {
      await seedOfficialAuthority('src-p');
      final sources = OfficialAnkiSourceDao(catalog);
      sources.upsertSource(
        sourceId: 'src-p',
        profileId: 'profile-default-01',
        sourceHash: 'hash-p',
        sourceSize: 10,
        displayName: 'deck',
        state: 'active',
        backendCommit: 'test',
        nowMillis: 1,
      );
      sources.replaceCards(
        sourceId: 'src-p',
        cards: const [
          OfficialAnkiCardDescriptor(
            cardId: 71,
            noteId: 700,
            deckId: 1,
            templateOrd: 0,
          ),
        ],
      );
      engine.cards[71] = const OfficialAnkiCardDescriptor(
        cardId: 71,
        noteId: 700,
        deckId: 1,
        templateOrd: 0,
      );
      engine.cardsByNote[700] = [71];
      await OfficialAnkiCourseProjectionStore(db).replaceOfficialProjection(
        sourceId: 'src-p',
        plan: OfficialAnkiProjectionPlan(
          items: [_item('src-p', 71)],
          issues: const [],
        ),
        sourceFingerprint: 'fp-p',
      );

      engine.failDeleteNotes = true;
      expect(await manager.uninstall('src-p'), isFalse);

      final row = catalog.handle
          .select("SELECT state FROM anki_sources WHERE source_id = 'src-p'")
          .first;
      expect(row['state'], 'pending_cleanup',
          reason: 'failed collection delete defers the saga');
      expect(
        (await authority.findBySource(
          profileId: 'profile-default-01',
          sourceId: 'src-p',
        ))
            ?.state,
        AnkiSourceVisibility.pendingCleanup,
        reason: 'course authority must hide a deferred uninstall',
      );
      final pendingEntries = await CourseCatalog.load(
        shells: await CourseRepository(db).sectionShells(),
        courseDb: db,
      );
      expect(
        pendingEntries.any((entry) => entry.officialSourceId == 'src-p'),
        isFalse,
        reason: 'a pending source must stay out of course management even '
            'while its projection manifest remains for retry',
      );
      expect(
        catalog.handle
            .select('SELECT COUNT(*) AS n FROM anki_source_cards')
            .first['n'],
        1,
        reason: 'ownership rows stay so the notes can still be found',
      );
      expect(
        await _count(
            db, 'SELECT COUNT(*) AS n FROM official_anki_projection_index'),
        1,
        reason: 'the projection is not dropped before the collection',
      );

      // The engine recovers; the startup retry finishes the saga.
      engine.failDeleteNotes = false;
      final resumed = await manager.retryPendingOfficialCleanups();
      expect(resumed, 1);
      expect(engine.deletedNoteIds, const {700});
      expect(
        catalog.handle
            .select('SELECT COUNT(*) AS n FROM anki_sources')
            .first['n'],
        0,
      );
      expect(
        await _count(
            db, 'SELECT COUNT(*) AS n FROM official_anki_projection_index'),
        0,
      );
      expect(
        (await authority.findBySource(
          profileId: 'profile-default-01',
          sourceId: 'src-p',
        ))
            ?.state,
        AnkiSourceVisibility.retired,
      );
    });
  });
}
