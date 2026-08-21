// P5F-3 cleanup-surface tests: catalog deleteSource, seeder reseed guard
// for projection tables, uninstall routing (+ legacy substring regression),
// and the projection vocabulary channel.

// Dart imports:
import 'dart:convert';

// Package imports:
import 'package:drift/drift.dart' show Variable;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:streaming_shared_preferences/streaming_shared_preferences.dart';
import 'package:turna/application/anki/anki_deck_manager.dart';
import 'package:turna/application/lesson_link_store.dart';
import 'package:turna/application/srs_provider.dart';
import 'package:turna/application/anki_official/projection/official_anki_projection_projector.dart';
import 'package:turna/application/anki_official/projection/official_anki_projection_store.dart';
import 'package:turna/application/anki_official/storage/official_anki_database.dart';
import 'package:turna/application/anki_official/storage/official_anki_source_dao.dart';
import 'package:turna/data/anki_import_dao.dart';
import 'package:turna/data/anki_note_dao.dart';
import 'package:turna/data/anki_unification_dao.dart';
import 'package:turna/data/course_database.dart';
import 'package:turna/data/course_database_seeder.dart';
import 'package:turna/data/course_repository.dart';
import 'package:turna/data/srs_state_dao.dart';
import 'package:turna/domain/anki/canonical_card_key.dart';
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
  final suffix = '-s1';
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
        await _count(db, 'SELECT COUNT(*) AS n FROM official_anki_projection_index'),
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
        (jsonDecode(row.read<String>('tags')) as List).contains('official:src-v'),
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
      final after = await db.customSelect(
        'SELECT id FROM vocabulary ORDER BY id',
      ).get();
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
    });

    tearDown(() => GetIt.instance.reset());

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

    test('official source uninstall cleans tree, unification; keeps legacy '
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
}
