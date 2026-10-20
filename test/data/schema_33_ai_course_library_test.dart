// v33 migration: the flat `ai_practice_sets` table becomes the course/version
// pair. Existing drafts must survive the upgrade — a learner's generated
// courses are the only copy of that content.

import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqlite3/sqlite3.dart' as sqlite;
import 'package:turna/data/ai_practice_repository.dart';
import 'package:turna/data/course_database.dart';
import 'package:turna/domain/ai/ai_course.dart';

void main() {
  test('schema 32 drafts become courses with one version each', () async {
    final dir = await Directory.systemTemp.createTemp('turna_schema33_');
    addTearDown(() async {
      if (dir.existsSync()) await dir.delete(recursive: true);
    });
    final path = p.join(dir.path, 'course.db');
    final createdAt = DateTime(2026, 1, 1).millisecondsSinceEpoch;
    final raw = sqlite.sqlite3.open(path);
    raw
      ..execute('''
        CREATE TABLE ai_practice_sets (
          id TEXT NOT NULL PRIMARY KEY,
          language_code TEXT NOT NULL DEFAULT 'tr',
          title TEXT NOT NULL,
          source_kind TEXT NOT NULL,
          status TEXT NOT NULL,
          section_json TEXT NULL,
          request_json TEXT NOT NULL DEFAULT '{}',
          progress_done INTEGER NOT NULL DEFAULT 0,
          progress_total INTEGER NOT NULL DEFAULT 0,
          error_message TEXT NULL,
          explanation TEXT NULL,
          pinned INTEGER NOT NULL DEFAULT 0,
          created_at_ms INTEGER NOT NULL,
          updated_at_ms INTEGER NOT NULL
        )
      ''')
      ..execute(
        'INSERT INTO ai_practice_sets (id, language_code, title, source_kind, '
        "status, section_json, request_json, progress_done, progress_total, "
        'pinned, created_at_ms, updated_at_ms) VALUES '
        "('draft', 'tr', 'Draft', 'custom', 'ready', '{\"id\":\"draft\"}', "
        "'{\"id\":\"draft\"}', 1, 1, 0, $createdAt, $createdAt)",
      )
      ..execute(
        'INSERT INTO ai_practice_sets (id, language_code, title, source_kind, '
        "status, section_json, request_json, progress_done, progress_total, "
        'pinned, created_at_ms, updated_at_ms) VALUES '
        "('kept', 'tr', 'Kept', 'mistakes', 'ready', '{\"id\":\"kept\"}', "
        "'{\"id\":\"kept\"}', 1, 1, 1, $createdAt, $createdAt)",
      )
      ..execute('PRAGMA user_version = 32')
      ..dispose();

    final db = CourseDatabase(NativeDatabase(File(path)));
    addTearDown(db.close);
    await db.customSelect('SELECT 1').get();

    expect(db.schemaVersion, CourseDatabase.kSchemaVersion);

    final repository = AiPracticeRepository(db);
    final courses = await repository.list();
    final byId = {for (final course in courses) course.id: course};
    expect(byId.keys, containsAll(<String>['draft', 'kept']));

    // Content survived and is playable again.
    expect(byId['draft']!.isPlayable, isTrue);
    expect(byId['draft']!.sectionJson, '{"id":"draft"}');
    expect(byId['draft']!.versions, hasLength(1));

    // Expiry: plain drafts get createdAt + 7d, favourites become permanent.
    expect(
      byId['draft']!.expiresAt,
      DateTime.fromMillisecondsSinceEpoch(createdAt).add(kAiCourseDraftTtl),
    );
    expect(byId['kept']!.pinned, isTrue);
    expect(byId['kept']!.expiresAt, isNull);

    // The legacy table is gone; nothing reads it again.
    final tables = await db
        .customSelect("SELECT name FROM sqlite_master WHERE type = 'table'")
        .get();
    expect(
      tables.any((row) => row.read<String>('name') == 'ai_practice_sets'),
      isFalse,
    );
  });
}
