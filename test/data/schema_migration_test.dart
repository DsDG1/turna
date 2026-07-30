// Drift schema migration tests: create DBs at older schema versions and
// verify that opening them with the current [CourseDatabase] migrates
// successfully to the current schema without losing data.

import 'dart:io';

import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:varnamala/data/course_database.dart' as db;

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

/// A hypothetical newer schema (v9) used to verify downgrade behavior: opening
/// a v9 DB with the current v8 code must not crash — it wipes + recreates the
/// schema (the course DB is a reseedable derived cache).
class _CourseDatabaseV9 extends db.CourseDatabase {
  _CourseDatabaseV9(super.e);

  @override
  int get schemaVersion => 9;

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
  final dir = await Directory.systemTemp.createTemp('varnamala_migration_');
  return p.join(dir.path, 'course.db');
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  ensureSqliteLibForTestHost();

  group('Drift schema migrations', () {
    test('v1 -> v6 creates grammarPoints, courseMeta, expressions',
        () async {
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

    test('v9 -> v8 downgrade wipes and recreates instead of crashing', () async {
      final path = await _tempDbPath();
      final newer = _CourseDatabaseV9(NativeDatabase(File(path)));
      await _forceOpen(newer);
      await newer.into(newer.sections).insert(
            const db.SectionsCompanion(
              id: Value('s-v9'),
              name: Value('Section V9'),
            ),
          );
      await newer.close();

      // Opening a v9 DB with the current v8 code must downgrade gracefully
      // (wipe + recreate) rather than throw.
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
  });
}
