import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqlite3/sqlite3.dart' as sqlite;
import 'package:streaming_shared_preferences/streaming_shared_preferences.dart';
import 'package:turna/application/mistake_provider.dart';
import 'package:turna/data/course_database.dart';
import 'package:turna/data/course_db_backup.dart';
import 'package:turna/data/mistake_repository.dart';
import 'package:turna/data/srs_state_dao.dart';
import 'package:turna/domain/course/language_codes.dart';
import 'package:turna/service/locator.dart';

import '../helpers/in_memory_course_db.dart';

Future<String> _tempDbPath() async {
  final dir = await Directory.systemTemp.createTemp('turna_lang_mig_');
  return p.join(dir.path, 'course.db');
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  ensureSqliteLibForTestHost();

  test('v24 database migrates SRS, history and mistakes onto turkish', () async {
    final path = await _tempDbPath();
    addTearDown(() async {
      final parent = File(path).parent;
      if (await parent.exists()) await parent.delete(recursive: true);
    });

    final dueAt = DateTime(2026, 9, 1, 8).millisecondsSinceEpoch;
    final lastReviewed = DateTime(2026, 8, 20, 9).millisecondsSinceEpoch;
    final reviewedAt = DateTime(2026, 8, 20, 9, 5).millisecondsSinceEpoch;

    final raw = sqlite.sqlite3.open(path);
    raw.execute('''
      CREATE TABLE sections (
        id TEXT PRIMARY KEY, name TEXT NOT NULL, description TEXT NOT NULL DEFAULT '',
        level TEXT NOT NULL DEFAULT '', prerequisite_section_ids TEXT NOT NULL DEFAULT '[]',
        sort_order INTEGER NOT NULL DEFAULT 0
      );
      CREATE TABLE vocabulary (
        id TEXT PRIMARY KEY, term TEXT NOT NULL, translation TEXT NOT NULL,
        pronunciation TEXT, audio_asset TEXT, tags TEXT NOT NULL DEFAULT '[]'
      );
      CREATE TABLE grammar_points (
        id TEXT PRIMARY KEY, title TEXT NOT NULL, explanation TEXT NOT NULL DEFAULT '',
        example_expression_ids TEXT NOT NULL DEFAULT '[]',
        example_sentence_ids TEXT NOT NULL DEFAULT '[]',
        practice_items TEXT NOT NULL DEFAULT '[]'
      );
      CREATE TABLE expressions (
        id TEXT PRIMARY KEY, term TEXT NOT NULL, translation TEXT NOT NULL,
        pronunciation TEXT, audio_asset TEXT, tags TEXT NOT NULL DEFAULT '[]'
      );
      CREATE TABLE units (
        id TEXT PRIMARY KEY, section_id TEXT NOT NULL, name TEXT NOT NULL,
        description TEXT NOT NULL DEFAULT '', prerequisite_unit_ids TEXT NOT NULL DEFAULT '[]',
        sort_order INTEGER NOT NULL DEFAULT 0
      );
      CREATE TABLE lessons (
        id TEXT PRIMARY KEY, unit_id TEXT NOT NULL, name TEXT NOT NULL,
        description TEXT NOT NULL DEFAULT '', type TEXT NOT NULL DEFAULT 'normal',
        template TEXT NOT NULL DEFAULT 'legacy',
        prerequisite_lesson_ids TEXT NOT NULL DEFAULT '[]', sort_order INTEGER NOT NULL DEFAULT 0
      );
      CREATE TABLE lesson_contents (
        lesson_id TEXT PRIMARY KEY, content_json TEXT NOT NULL
      );
      CREATE TABLE course_meta (key TEXT PRIMARY KEY, value TEXT NOT NULL);
      CREATE TABLE srs_states (
        word_id TEXT PRIMARY KEY, queue TEXT NOT NULL, due_at INTEGER NOT NULL,
        interval_days INTEGER NOT NULL, ease REAL NOT NULL, reps INTEGER NOT NULL,
        lapses INTEGER NOT NULL, is_leech INTEGER NOT NULL,
        is_suspended INTEGER NOT NULL DEFAULT 0, is_buried INTEGER NOT NULL DEFAULT 0,
        type TEXT NOT NULL, last_reviewed_at INTEGER, stability REAL,
        difficulty REAL, fsrs_state INTEGER NOT NULL, learning_step INTEGER,
        source_kind TEXT, source_id TEXT, owner_id TEXT
      );
      CREATE TABLE review_events (
        id INTEGER PRIMARY KEY AUTOINCREMENT, card_id TEXT NOT NULL,
        queue TEXT NOT NULL, reviewed_at INTEGER NOT NULL, quality INTEGER NOT NULL,
        prev_interval_days INTEGER NOT NULL, next_interval_days INTEGER NOT NULL,
        prev_ease REAL NOT NULL, next_ease REAL NOT NULL, reps INTEGER NOT NULL,
        lapses INTEGER NOT NULL, type TEXT NOT NULL, source_key TEXT,
        source_kind TEXT, source_id TEXT, owner_id TEXT
      );
      INSERT INTO srs_states (
        word_id, queue, due_at, interval_days, ease, reps, lapses, is_leech,
        is_suspended, is_buried, type, last_reviewed_at, stability, difficulty,
        fsrs_state, learning_step, source_kind, source_id, owner_id
      ) VALUES (
        'w-merhaba', 'srs', $dueAt, 11, 2.6, 5, 1, 0,
        0, 0, 'word', $lastReviewed, 18.5, 4.2,
        2, NULL, 'course', 'course', NULL
      );
      INSERT INTO review_events (
        card_id, queue, reviewed_at, quality, prev_interval_days, next_interval_days,
        prev_ease, next_ease, reps, lapses, type, source_kind, source_id
      ) VALUES (
        'w-merhaba', 'srs', $reviewedAt, 4, 4, 11, 2.5, 2.6, 5, 1, 'word',
        'course', 'course'
      );
      INSERT INTO course_meta VALUES ('contentVersion', '12+4');
      PRAGMA user_version = 24;
    ''');
    raw.dispose();

    final migrated = CourseDatabase(NativeDatabase(File(path)));
    await migrated.customSelect('SELECT 1').get();
    expect(migrated.schemaVersion, 25);

    final dao = SrsStateDao(migrated);
    final loaded = await dao.loadQueue('srs', languageCode: LanguageCodes.turkish);
    expect(loaded.keys, ['w-merhaba']);
    final word = loaded['w-merhaba']!;
    expect(word.dueAt.millisecondsSinceEpoch, dueAt);
    expect(word.intervalDays, 11);
    expect(word.reps, 5);
    expect(word.lapses, 1);
    expect(word.ease, closeTo(2.6, 1e-9));
    expect(word.stability, closeTo(18.5, 1e-9));
    expect(word.difficulty, closeTo(4.2, 1e-9));
    expect(word.fsrsState, 2);
    expect(word.lastReviewedAt!.millisecondsSinceEpoch, lastReviewed);

    final row = await migrated.customSelect(
      "SELECT language_code, source_kind, source_id FROM srs_states WHERE word_id = 'w-merhaba'",
    ).getSingle();
    expect(row.read<String>('language_code'), LanguageCodes.turkish);
    expect(row.read<String>('source_kind'), 'builtin');
    expect(row.read<String>('source_id'), LanguageCodes.turkish);

    final event = await migrated.customSelect(
      "SELECT language_code, quality, next_interval_days FROM review_events WHERE card_id = 'w-merhaba'",
    ).getSingle();
    expect(event.read<String>('language_code'), LanguageCodes.turkish);
    expect(event.read<int>('quality'), 4);
    expect(event.read<int>('next_interval_days'), 11);

    // CourseMeta bucketing: the legacy unsuffixed key is copied (not
    // renamed) to contentVersion:tr; both stay readable.
    final bucket = await migrated.customSelect(
      "SELECT value FROM course_meta WHERE key = 'contentVersion:tr'",
    ).getSingleOrNull();
    expect(bucket?.read<String>('value'), '12+4');
    final legacyMeta = await migrated.customSelect(
      "SELECT value FROM course_meta WHERE key = 'contentVersion'",
    ).getSingleOrNull();
    expect(legacyMeta?.read<String>('value'), '12+4');

    SharedPreferences.setMockInitialValues({
      LocalStateKeys.mistakeLog:
          '[{"id":"m-old","lessonId":"s1-l1","stageId":"st","interactionId":"i1","timestamp":"2026-08-20T09:00:00.000","rewriteCount":0,"userAnswer":"x","correctAnswer":"y"}]',
      LocalStateKeys.mistakeDailyCounts: '{"2026-08-20":1}',
      LocalStateKeys.mistakeMasteredTotal: 3,
    });
    final sp = await StreamingSharedPreferences.instance;
    final prefs = AppPrefs(sp);
    final mistakes = MistakeProvider(prefs)
      ..useRepository(MistakeRepository(migrated));
    await mistakes.ensureLoaded();
    expect(mistakes.entries.map((e) => e.id), ['m-old']);
    expect(mistakes.masteredTotal, 3);
    expect(mistakes.dailyCounts['2026-08-20'], 1);

    await migrated.close();
  });

  test('backupCourseDbBeforeMigration snapshots only stale-version files',
      () async {
    final path = await _tempDbPath();
    addTearDown(() async {
      final parent = File(path).parent;
      if (await parent.exists()) await parent.delete(recursive: true);
    });

    final raw = sqlite.sqlite3.open(path);
    raw.execute('''
      CREATE TABLE sections (id TEXT PRIMARY KEY);
      INSERT INTO sections VALUES ('s1');
      PRAGMA user_version = 24;
    ''');
    raw.dispose();

    final backup = await backupCourseDbBeforeMigration(File(path));
    expect(backup, isNotNull);
    expect(await backup!.exists(), isTrue);

    final check = sqlite.sqlite3.open(backup.path);
    expect(
      check.select('PRAGMA user_version').first['user_version'] as int,
      24,
    );
    expect(check.select('SELECT id FROM sections').length, 1);
    check.dispose();

    // A file already on the current schema (or missing entirely) produces
    // no backup.
    const currentVersion = CourseDatabase.kSchemaVersion;
    final fresh = sqlite.sqlite3.open(path);
    fresh.execute('PRAGMA user_version = $currentVersion');
    fresh.dispose();
    expect(await backupCourseDbBeforeMigration(File(path)), isNull);
    expect(
      await backupCourseDbBeforeMigration(File('$path.missing')),
      isNull,
    );
  });
}
