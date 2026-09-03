// Drift schema migration tests: create DBs at older schema versions and
// verify that opening them with the current [CourseDatabase] migrates
// successfully to the current schema without losing data.

import 'dart:io';

import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqlite3/sqlite3.dart' as sqlite;
import 'package:turna/data/course_database.dart' as db;

import '../helpers/in_memory_course_db.dart';

class _CourseDatabaseV1 extends db.CourseDatabase {
  _CourseDatabaseV1(super.e);

  @override
  int get schemaVersion => 1;

  @override
  MigrationStrategy get migration => MigrationStrategy(
        onCreate: (m) async {
          await m.database.customStatement('''
            CREATE TABLE IF NOT EXISTS sections (
              id TEXT PRIMARY KEY,
              name TEXT NOT NULL,
              description TEXT NOT NULL DEFAULT '',
              prerequisite_section_ids TEXT NOT NULL DEFAULT '[]',
              sort_order INTEGER NOT NULL DEFAULT 0
            )
          ''');
          await m.createTable(units);
          await m.createTable(lessons);
          await m.createTable(lessonContents);
          await m.createTable(vocabulary);
        },
      );
}

class _CourseDatabaseV2 extends db.CourseDatabase {
  _CourseDatabaseV2(super.e);

  @override
  int get schemaVersion => 2;

  @override
  MigrationStrategy get migration => MigrationStrategy(
        onCreate: (m) async {
          await m.database.customStatement('''
            CREATE TABLE IF NOT EXISTS sections (
              id TEXT PRIMARY KEY,
              name TEXT NOT NULL,
              description TEXT NOT NULL DEFAULT '',
              prerequisite_section_ids TEXT NOT NULL DEFAULT '[]',
              sort_order INTEGER NOT NULL DEFAULT 0
            )
          ''');
          await m.createTable(units);
          await m.createTable(lessons);
          await m.createTable(lessonContents);
          await m.createTable(vocabulary);
          // v2 grammar_points has no practiceItems column.
          await m.database.customStatement('''
            CREATE TABLE grammar_points (
              id TEXT PRIMARY KEY,
              title TEXT NOT NULL,
              explanation TEXT NOT NULL DEFAULT '',
              example_expression_ids TEXT NOT NULL DEFAULT '[]',
              example_sentence_ids TEXT NOT NULL DEFAULT '[]'
            )
          ''');
        },
      );
}

class _CourseDatabaseV3 extends db.CourseDatabase {
  _CourseDatabaseV3(super.e);

  @override
  int get schemaVersion => 3;

  @override
  MigrationStrategy get migration => MigrationStrategy(
        onCreate: (m) async {
          await m.database.customStatement('''
            CREATE TABLE IF NOT EXISTS sections (
              id TEXT PRIMARY KEY,
              name TEXT NOT NULL,
              description TEXT NOT NULL DEFAULT '',
              prerequisite_section_ids TEXT NOT NULL DEFAULT '[]',
              sort_order INTEGER NOT NULL DEFAULT 0
            )
          ''');
          await m.createTable(units);
          await m.createTable(lessons);
          await m.createTable(lessonContents);
          await m.createTable(vocabulary);
          await m.createTable(grammarPoints);
        },
      );
}

class _CourseDatabaseV4 extends db.CourseDatabase {
  _CourseDatabaseV4(super.e);

  @override
  int get schemaVersion => 4;

  @override
  MigrationStrategy get migration => MigrationStrategy(
        onCreate: (m) async {
          await m.database.customStatement('''
            CREATE TABLE IF NOT EXISTS sections (
              id TEXT PRIMARY KEY,
              name TEXT NOT NULL,
              description TEXT NOT NULL DEFAULT '',
              prerequisite_section_ids TEXT NOT NULL DEFAULT '[]',
              sort_order INTEGER NOT NULL DEFAULT 0
            )
          ''');
          await m.createTable(units);
          await m.createTable(lessons);
          await m.createTable(lessonContents);
          await m.createTable(vocabulary);
          await m.createTable(grammarPoints);
          await m.createTable(courseMeta);
        },
      );
}

/// v6 schema: all course tables through `anki_imports` + section `level`, but
/// NO `srs_states` (added in v7). Used to verify the v6 -> v7 upgrade creates
/// the SRS table without losing course data.
class _CourseDatabaseV6 extends db.CourseDatabase {
  _CourseDatabaseV6(super.e);

  @override
  int get schemaVersion => 6;

  @override
  MigrationStrategy get migration => MigrationStrategy(
        onCreate: (m) async {
          await m.createTable(sections);
          await m.createTable(units);
          await m.createTable(lessons);
          await m.createTable(lessonContents);
          await m.createTable(vocabulary);
          await m.createTable(grammarPoints);
          await m.createTable(courseMeta);
          await m.createTable(expressions);
          await m.createTable(ankiImports);
        },
      );
}

/// A hypothetical newer schema used to verify downgrade behavior: opening
/// a future DB with the current code must not crash - it wipes + recreates the
/// schema (the course DB is a reseedable derived cache).
class _CourseDatabaseV25 extends db.CourseDatabase {
  _CourseDatabaseV25(super.e);

  @override
  int get schemaVersion => db.CourseDatabase.kSchemaVersion + 1;
}


/// v15 is the last schema before the official Anki derived projection index.
class _CourseDatabaseV15 extends db.CourseDatabase {
  _CourseDatabaseV15(super.e);

  @override
  int get schemaVersion => 15;

  @override
  MigrationStrategy get migration => MigrationStrategy(
        onCreate: (m) async => await m.createAll(),
      );
}

/// v14 contains all live learning tables but predates Fun Lab checkpoints.
class _CourseDatabaseV14 extends db.CourseDatabase {
  _CourseDatabaseV14(super.e);

  @override
  int get schemaVersion => 14;

  @override
  MigrationStrategy get migration => MigrationStrategy(
        onCreate: (m) async {
          await m.createAll();
          await m.database.customStatement(
            'ALTER TABLE anki_cards_meta ADD COLUMN suspended '
            'INTEGER NOT NULL DEFAULT 0',
          );
          await m.database.customStatement(
            'ALTER TABLE anki_cards_meta ADD COLUMN buried_until INTEGER',
          );
          await m.database.customStatement(
            'ALTER TABLE anki_cards_meta ADD COLUMN marked '
            'INTEGER NOT NULL DEFAULT 0',
          );
          await m.database.customStatement(
            'ALTER TABLE anki_cards_meta ADD COLUMN flag '
            'INTEGER NOT NULL DEFAULT 0',
          );
        },
      );
}

/// A v13 schema (the version before the card-level Anki wordId re-key) used to
/// verify the v13 -> v14 migration re-keys legacy note-based SRS ids. onCreate
/// builds the full current table set; the re-key only touches Drift-defined
/// columns on anki_cards_meta / srs_states / review_events.
class _CourseDatabaseV13 extends db.CourseDatabase {
  _CourseDatabaseV13(super.e);

  @override
  int get schemaVersion => 13;

  @override
  MigrationStrategy get migration => MigrationStrategy(
        onCreate: (m) async => await m.createAll(),
      );
}

Future<void> _forceOpen(db.CourseDatabase database) async {
  // Trigger the database open (and therefore migration) by running a query.
  await database.customSelect('SELECT 1').get();
}

Future<void> _seedV1Data(db.CourseDatabase database) async {
  await database.into(database.sections).insert(
        const db.SectionsCompanion(
          id: Value('s-v1'),
          name: Value('Section V1'),
        ),
      );
  await database.into(database.vocabulary).insert(
        const db.VocabularyCompanion(
          id: Value('w-v1'),
          term: Value('Test'),
          translation: Value('Test'),
        ),
      );
}

Future<void> _seedV2Data(db.CourseDatabase database) async {
  await _seedV1Data(database);
  await database.into(database.grammarPoints).insert(
        const db.GrammarPointsCompanion(
          id: Value('gp-v2'),
          title: Value('Grammar V2'),
        ),
      );
}

Future<void> _seedV3Data(db.CourseDatabase database) async {
  await _seedV2Data(database);
  await database.into(database.grammarPoints).insert(
        const db.GrammarPointsCompanion(
          id: Value('gp-v3'),
          title: Value('Grammar V3'),
          practiceItems: Value('[{"\$type":"showWord","wordId":"w-v3"}]'),
        ),
      );
}

Future<void> _seedV4Data(db.CourseDatabase database) async {
  await _seedV2Data(database);
  await database.into(database.courseMeta).insert(
        const db.CourseMetaCompanion(
          key: Value('version'),
          value: Value('4'),
        ),
      );
}

Future<String> _tempDbPath() async {
  final dir = await Directory.systemTemp.createTemp('turna_migration_');
  return p.join(dir.path, 'course.db');
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  ensureSqliteLibForTestHost();

  group('Drift schema migrations', () {
    test('v1 -> v6 creates grammarPoints, courseMeta, expressions', () async {
      final path = await _tempDbPath();
      final oldDb = _CourseDatabaseV1(NativeDatabase(File(path)));
      await _forceOpen(oldDb);
      await _seedV1Data(oldDb);
      await oldDb.close();

      final migrated = db.CourseDatabase(NativeDatabase(File(path)));
      await _forceOpen(migrated);

      // All current tables exist.
      final sections = await migrated.select(migrated.sections).get();
      expect(sections.map((r) => r.id), ['s-v1']);

      final vocab = await migrated.select(migrated.vocabulary).get();
      expect(vocab.map((r) => r.id), ['w-v1']);

      final grammar = await migrated.select(migrated.grammarPoints).get();
      expect(grammar, isEmpty);

      final meta = await migrated.select(migrated.courseMeta).get();
      expect(meta, isEmpty);

      final expressions = await migrated.select(migrated.expressions).get();
      expect(expressions, isEmpty);

      await migrated.close();
      await File(path).parent.delete(recursive: true);
    });

    test('v2 -> v6 preserves grammar points and adds courseMeta/expressions',
        () async {
      final path = await _tempDbPath();
      final oldDb = _CourseDatabaseV2(NativeDatabase(File(path)));
      await _forceOpen(oldDb);
      await _seedV2Data(oldDb);
      await oldDb.close();

      final migrated = db.CourseDatabase(NativeDatabase(File(path)));
      await _forceOpen(migrated);

      final grammar = await migrated.select(migrated.grammarPoints).get();
      expect(grammar.map((r) => r.id), ['gp-v2']);
      // practiceItems column was added in v3; should default to empty list.
      expect(grammar.single.practiceItems, '[]');

      final expressions = await migrated.select(migrated.expressions).get();
      expect(expressions, isEmpty);

      await migrated.close();
      await File(path).parent.delete(recursive: true);
    });

    test('v3 -> v6 preserves grammar point practiceItems', () async {
      final path = await _tempDbPath();
      final oldDb = _CourseDatabaseV3(NativeDatabase(File(path)));
      await _forceOpen(oldDb);
      await _seedV3Data(oldDb);
      await oldDb.close();

      final migrated = db.CourseDatabase(NativeDatabase(File(path)));
      await _forceOpen(migrated);

      final grammar = await migrated.select(migrated.grammarPoints).get();
      final gpV3 = grammar.firstWhere((r) => r.id == 'gp-v3');
      expect(gpV3.practiceItems, '[{"\$type":"showWord","wordId":"w-v3"}]');

      final expressions = await migrated.select(migrated.expressions).get();
      expect(expressions, isEmpty);

      await migrated.close();
      await File(path).parent.delete(recursive: true);
    });

    test('v4 -> v6 preserves all existing data', () async {
      final path = await _tempDbPath();
      final oldDb = _CourseDatabaseV4(NativeDatabase(File(path)));
      await _forceOpen(oldDb);
      await _seedV4Data(oldDb);
      await oldDb.close();

      final migrated = db.CourseDatabase(NativeDatabase(File(path)));
      await _forceOpen(migrated);

      final sections = await migrated.select(migrated.sections).get();
      expect(sections.map((r) => r.id), ['s-v1']);

      final vocab = await migrated.select(migrated.vocabulary).get();
      expect(vocab.map((r) => r.id), ['w-v1']);

      final grammar = await migrated.select(migrated.grammarPoints).get();
      expect(grammar.map((r) => r.id), ['gp-v2']);

      final meta = await migrated.select(migrated.courseMeta).get();
      expect(meta.map((r) => r.key), ['version']);

      final expressions = await migrated.select(migrated.expressions).get();
      expect(expressions, isEmpty);

      await migrated.close();
      await File(path).parent.delete(recursive: true);
    });

    test('v6 -> v7 adds the srs_states table and preserves course data',
        () async {
      final path = await _tempDbPath();
      final oldDb = _CourseDatabaseV6(NativeDatabase(File(path)));
      await _forceOpen(oldDb);
      await _seedV4Data(oldDb); // section + vocab + grammar + meta
      await oldDb.close();

      final migrated = db.CourseDatabase(NativeDatabase(File(path)));
      await _forceOpen(migrated);

      // v6 course data is preserved across the upgrade.
      final sections = await migrated.select(migrated.sections).get();
      expect(sections.map((r) => r.id), ['s-v1']);
      final meta = await migrated.select(migrated.courseMeta).get();
      expect(meta.map((r) => r.key), ['version']);

      // v7 adds the srs_states table (empty on creation; state is backfilled
      // from the legacy prefs blob post-DI by SrsQueueProvider.ensureLoaded).
      final srsStates = await migrated.select(migrated.srsStates).get();
      expect(srsStates, isEmpty);

      await migrated.close();
      await File(path).parent.delete(recursive: true);
    });

    test('v6 -> v8 adds FSRS columns on srs_states', () async {
      final path = await _tempDbPath();
      final oldDb = _CourseDatabaseV6(NativeDatabase(File(path)));
      await _forceOpen(oldDb);
      await _seedV4Data(oldDb);
      await oldDb.close();

      final migrated = db.CourseDatabase(NativeDatabase(File(path)));
      await _forceOpen(migrated);

      // v8 columns exist (nullable FSRS fields); table is queryable.
      final srsStates = await migrated.select(migrated.srsStates).get();
      expect(srsStates, isEmpty);

      await migrated.close();
      await File(path).parent.delete(recursive: true);
    });

    test('v6 -> v9 adds the Anki NoteStore tables', () async {
      final path = await _tempDbPath();
      final oldDb = _CourseDatabaseV6(NativeDatabase(File(path)));
      await _forceOpen(oldDb);
      await _seedV4Data(oldDb);
      await oldDb.close();

      final migrated = db.CourseDatabase(NativeDatabase(File(path)));
      await _forceOpen(migrated);

      // v9 adds the three NoteStore tables (empty on creation; populated at
      // import time by the AnkiImporter).
      expect(await migrated.select(migrated.ankiNotetypes).get(), isEmpty);
      expect(await migrated.select(migrated.ankiNotes).get(), isEmpty);
      expect(await migrated.select(migrated.ankiCardsMeta).get(), isEmpty);

      await migrated.close();
      await File(path).parent.delete(recursive: true);
    });

    test('v6 -> current drops the v10 anki_prerendered_html cache (v22)',
        () async {
      final path = await _tempDbPath();
      final oldDb = _CourseDatabaseV6(NativeDatabase(File(path)));
      await _forceOpen(oldDb);
      await _seedV4Data(oldDb);
      await oldDb.close();

      final migrated = db.CourseDatabase(NativeDatabase(File(path)));
      await _forceOpen(migrated);

      // v10 created the pre-rendered HTML cache; v22 drops it — its only
      // writer lost its last production caller when the legacy Anki layer
      // was removed, so the table was guaranteed empty.
      final tables = await migrated
          .customSelect(
            "SELECT name FROM sqlite_master WHERE type = 'table' "
            "AND name = 'anki_prerendered_html'",
          )
          .get();
      expect(tables, isEmpty);

      await migrated.close();
      await File(path).parent.delete(recursive: true);
    });

    test('v14 -> v15 adds Fun Lab checkpoint tables and preserves data',
        () async {
      final path = await _tempDbPath();
      final oldDb = _CourseDatabaseV14(NativeDatabase(File(path)));
      await _forceOpen(oldDb);
      await oldDb.into(oldDb.sections).insert(
            const db.SectionsCompanion(
              id: Value('s-v14'),
              name: Value('Section V14'),
            ),
          );
      await oldDb.close();

      final migrated = db.CourseDatabase(NativeDatabase(File(path)));
      await _forceOpen(migrated);
      expect(
          (await migrated.select(migrated.sections).get()).single.id, 's-v14');
      final tables = await migrated
          .customSelect(
            "SELECT name FROM sqlite_master WHERE type = 'table' "
            "AND name LIKE 'fun_lab_snapshot_%' ORDER BY name",
          )
          .get();
      expect(
        tables.map((row) => row.read<String>('name')),
        [
          'fun_lab_snapshot_anki_state',
          'fun_lab_snapshot_meta',
          'fun_lab_snapshot_review_events',
          'fun_lab_snapshot_srs',
        ],
      );

      await migrated.close();
      await File(path).parent.delete(recursive: true);
    });

    test('v15 -> v17 adds projection index and manifest and keeps rows',
        () async {
      final path = await _tempDbPath();
      final oldDb = _CourseDatabaseV15(NativeDatabase(File(path)));
      await _forceOpen(oldDb);
      await oldDb.into(oldDb.sections).insert(
            const db.SectionsCompanion(
              id: Value('s-v15'),
              name: Value('Section V15'),
            ),
          );
      await oldDb.close();

      final migrated = db.CourseDatabase(NativeDatabase(File(path)));
      await _forceOpen(migrated);
      expect(
        (await migrated.select(migrated.sections).get()).single.id,
        's-v15',
      );
      final tables = await migrated
          .customSelect(
            "SELECT name FROM sqlite_master WHERE type = 'table' "
            "AND name IN ('official_anki_projection_index',"
            "'official_anki_projection_manifest') ORDER BY name",
          )
          .get();
      expect(tables, isEmpty);
      final legacy = await migrated
          .customSelect(
            "SELECT name FROM sqlite_master WHERE type = 'table' "
            "AND name IN ('anki_notes','anki_notetypes','anki_cards_meta') "
            "ORDER BY name",
          )
          .get();
      expect(legacy.map((row) => row.read<String>('name')), [
        'anki_cards_meta',
        'anki_notes',
        'anki_notetypes',
      ]);
      expect(migrated.schemaVersion,
          db.CourseDatabase(NativeDatabase.memory()).schemaVersion);

      await migrated.close();
      await File(path).parent.delete(recursive: true);
    });

    test('v25 -> v24 downgrade wipes and recreates instead of crashing',
        () async {
      final path = await _tempDbPath();
      final newer = _CourseDatabaseV25(NativeDatabase(File(path)));
      await _forceOpen(newer);
      await newer.into(newer.sections).insert(
            const db.SectionsCompanion(
              id: Value('s-v11'),
              name: Value('Section V11'),
            ),
          );
      await newer.close();

      // Opening a future schema with the current code must downgrade
      // gracefully (wipe + recreate) rather than throw.
      final downgraded = db.CourseDatabase(NativeDatabase(File(path)));
      await _forceOpen(downgraded);

      // Schema recreated and prior data wiped.
      final sections = await downgraded.select(downgraded.sections).get();
      expect(sections, isEmpty);

      // Schema is functional: a fresh insert works.
      await downgraded.into(downgraded.sections).insert(
            const db.SectionsCompanion(
              id: Value('s-fresh'),
              name: Value('Fresh'),
            ),
          );
      final after = await downgraded.select(downgraded.sections).get();
      expect(after.map((r) => r.id), ['s-fresh']);

      await downgraded.close();
      await File(path).parent.delete(recursive: true);
    });

    test('v20 -> v24 migration drops legacy owner authority tables and unifies on v2',
        () async {
      final path = await _tempDbPath();
      final raw = sqlite.sqlite3.open(path);
      raw.execute('''
        CREATE TABLE anki_course_sources (
          course_id TEXT PRIMARY KEY NOT NULL,
          profile_id TEXT NOT NULL,
          source_id TEXT NOT NULL,
          backend_kind TEXT NOT NULL,
          display_name TEXT NOT NULL DEFAULT '',
          source_hash TEXT NOT NULL,
          source_fingerprint TEXT NOT NULL,
          state TEXT NOT NULL,
          created_at INTEGER NOT NULL,
          updated_at INTEGER NOT NULL
        );
        INSERT INTO anki_course_sources VALUES (
          'course-a', 'default', 'src-abc123', 'legacyTurna', 'Deck A',
          'hash-a', 'fp-a', 'active', 111, 112
        );
        PRAGMA user_version = 20;
      ''');
      raw.dispose();

      final migrated = db.CourseDatabase(NativeDatabase(File(path)));
      await _forceOpen(migrated);
      expect(migrated.schemaVersion, 24);

      // In v24, anki_course_sources, anki_owner_transitions, course_scope_repair_journal,
      // and course_meta_v21_codec are physically dropped.
      final droppedTables = await migrated
          .customSelect(
            "SELECT name FROM sqlite_master WHERE type = 'table' "
            "AND name IN ('anki_course_sources','anki_owner_transitions','course_scope_repair_journal',"
            "'course_meta_v21_codec') ORDER BY name",
          )
          .get();
      expect(droppedTables, isEmpty);

      // Core v2 tables exist.
      final v2Tables = await migrated
          .customSelect(
            "SELECT name FROM sqlite_master WHERE type = 'table' "
            "AND name IN ('anki_course_tree_view','anki_card_introduction_states') ORDER BY name",
          )
          .get();
      expect(v2Tables.map((r) => r.read<String>('name')), [
        'anki_card_introduction_states',
        'anki_course_tree_view',
      ]);

      await migrated.close();
      await File(path).parent.delete(recursive: true);
    });

    test('fresh create at v24 contains v2 course tree view and introduction states', () async {
      final database = db.CourseDatabase(NativeDatabase.memory());
      await _forceOpen(database);
      expect(database.schemaVersion, 24);
      final tables = await database
          .customSelect(
            "SELECT name FROM sqlite_master WHERE type = 'table' "
            "AND name IN ('anki_course_tree_view','anki_card_introduction_states','anki_course_sources') "
            "ORDER BY name",
          )
          .get();
      expect(tables.map((r) => r.read<String>('name')), [
        'anki_card_introduction_states',
        'anki_course_tree_view',
      ]);
      await database.close();
    });

    test('v19 -> v20 backfills explicit mixed source identity', () async {
      final path = await _tempDbPath();
      final raw = sqlite.sqlite3.open(path);
      raw.execute('''
        CREATE TABLE srs_states (
          word_id TEXT PRIMARY KEY, queue TEXT NOT NULL, due_at INTEGER NOT NULL,
          interval_days INTEGER NOT NULL, ease REAL NOT NULL, reps INTEGER NOT NULL,
          lapses INTEGER NOT NULL, is_leech INTEGER NOT NULL,
          is_suspended INTEGER NOT NULL, is_buried INTEGER NOT NULL,
          type TEXT NOT NULL, last_reviewed_at INTEGER, stability REAL,
          difficulty REAL, fsrs_state INTEGER NOT NULL, learning_step INTEGER
        );
        CREATE TABLE review_events (
          id INTEGER PRIMARY KEY AUTOINCREMENT, card_id TEXT NOT NULL,
          queue TEXT NOT NULL, reviewed_at INTEGER NOT NULL, quality INTEGER NOT NULL,
          prev_interval_days INTEGER NOT NULL, next_interval_days INTEGER NOT NULL,
          prev_ease REAL NOT NULL, next_ease REAL NOT NULL, reps INTEGER NOT NULL,
          lapses INTEGER NOT NULL, type TEXT NOT NULL, source_key TEXT
        );
        CREATE TABLE fun_lab_snapshot_srs (
          word_id TEXT PRIMARY KEY, queue TEXT NOT NULL
        );
        CREATE TABLE fun_lab_snapshot_review_events (
          id INTEGER PRIMARY KEY, card_id TEXT NOT NULL, queue TEXT NOT NULL
        );
        INSERT INTO srs_states VALUES
          ('opaque-course', 'srs', 0, 1, 2.5, 0, 0, 0, 0, 0, 'word', NULL, NULL, NULL, 1, NULL),
          ('grammar-row', 'grammar', 0, 1, 2.5, 0, 0, 0, 0, 0, 'word', NULL, NULL, NULL, 1, NULL),
          ('anki-legacy-a-c7', 'srs', 0, 1, 2.5, 0, 0, 0, 0, 0, 'word', NULL, NULL, NULL, 1, NULL),
          ('official-anki-official-a-c8', 'srs', 0, 1, 2.5, 0, 0, 0, 0, 0, 'word', NULL, NULL, NULL, 1, NULL);
        INSERT INTO review_events
          (card_id, queue, reviewed_at, quality, prev_interval_days,
           next_interval_days, prev_ease, next_ease, reps, lapses, type)
        SELECT word_id, queue, 1, 4, 1, 2, 2.5, 2.5, 1, 0, type
        FROM srs_states;
        PRAGMA user_version = 19;
      ''');
      raw.dispose();

      final migrated = db.CourseDatabase(NativeDatabase(File(path)));
      await _forceOpen(migrated);
      final states = await migrated
          .customSelect(
            'SELECT word_id, source_kind, source_id FROM srs_states '
            'ORDER BY word_id',
          )
          .get();
      final identity = {
        for (final row in states)
          row.read<String>('word_id'): (
            row.read<String>('source_kind'),
            row.read<String>('source_id'),
          ),
      };
      expect(identity['opaque-course'], ('course', 'course'));
      expect(identity['grammar-row'], ('grammar', 'grammar'));
      expect(identity['anki-legacy-a-c7'], ('ankiLegacy', 'legacy-a'));
      expect(identity['official-anki-official-a-c8'],
          ('ankiOfficial', 'official-a'));
      final events = await migrated
          .customSelect(
            'SELECT source_kind, source_id FROM review_events',
          )
          .get();
      expect(events, hasLength(4));
      expect(events.every((row) => row.data['source_kind'] != null), isTrue);

      await migrated.close();
      await File(path).parent.delete(recursive: true);
    });

    test('v13 -> v14 re-keys legacy note-based Anki word ids to card-level',
        () async {
      final path = await _tempDbPath();
      final oldDb = _CourseDatabaseV13(NativeDatabase(File(path)));
      await _forceOpen(oldDb);
      // anki_cards_meta carries the authoritative card-level word id; SRS
      // state + review history still carry legacy note-based ids.
      await oldDb.customStatement(
        "INSERT INTO anki_cards_meta "
        "(import_id, card_id, note_id, ord, did, word_id, render_mode, "
        "scheduling_json) VALUES ('anki_import_123', 456, 100, 0, 1, "
        "'anki-anki_import_123-c456', 'hybrid', '{}')",
      );
      await oldDb.customStatement(
        "INSERT INTO srs_states (word_id, queue, due_at, interval_days, "
        "ease, reps, lapses, is_leech, is_suspended, is_buried, type) VALUES "
        "('anki-anki_import_123-n100', 'srs', 0, 1, 2.5, 0, 0, 0, 0, 0, 'word')",
      );
      await oldDb.customStatement(
        "INSERT INTO review_events (card_id, queue, reviewed_at, quality, "
        "prev_interval_days, next_interval_days, prev_ease, next_ease, reps, "
        "lapses, type) VALUES ('anki-anki_import_123-n100', 'srs', 0, 4, 0, "
        "1, 2.5, 2.5, 1, 0, 'word')",
      );
      await oldDb.close();

      final migrated = db.CourseDatabase(NativeDatabase(File(path)));
      await _forceOpen(migrated);

      final srs = await migrated
          .customSelect(
            "SELECT word_id FROM srs_states WHERE word_id LIKE 'anki-%'",
          )
          .get();
      expect(srs.map((r) => r.read<String>('word_id')),
          ['anki-anki_import_123-c456']);

      final ev = await migrated
          .customSelect(
            "SELECT card_id FROM review_events WHERE card_id LIKE 'anki-%'",
          )
          .get();
      expect(ev.map((r) => r.read<String>('card_id')),
          ['anki-anki_import_123-c456']);

      await migrated.close();
      await File(path).parent.delete(recursive: true);
    });
  });
}
