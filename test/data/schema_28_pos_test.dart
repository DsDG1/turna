import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqlite3/sqlite3.dart' as sqlite;
import 'package:turna/data/course_database.dart';

void main() {
  test('schema 27 vocabulary opens at the current version with a null pos',
      () async {
    final dir = await Directory.systemTemp.createTemp('turna_schema28_');
    addTearDown(() async {
      if (dir.existsSync()) await dir.delete(recursive: true);
    });
    final path = p.join(dir.path, 'course.db');
    final raw = sqlite.sqlite3.open(path);
    raw
      ..execute('''
        CREATE TABLE vocabulary (
          language_code TEXT NOT NULL DEFAULT 'tr',
          id TEXT NOT NULL,
          term TEXT NOT NULL,
          translation TEXT NOT NULL,
          pronunciation TEXT,
          audio_asset TEXT,
          tags TEXT NOT NULL DEFAULT '[]',
          PRIMARY KEY (language_code, id)
        )
      ''')
      ..execute(
        "INSERT INTO vocabulary (language_code, id, term, translation, tags) "
        "VALUES ('tr', 'w1', 'ev', 'house', '[]')",
      )
      ..execute('PRAGMA user_version = 27')
      ..dispose();

    final db = CourseDatabase(NativeDatabase(File(path)));
    addTearDown(db.close);
    await db.customSelect('SELECT 1').get();

    expect(db.schemaVersion, CourseDatabase.kSchemaVersion);
    final row = await db.select(db.vocabulary).getSingle();
    expect(row.id, 'w1');
    expect(row.term, 'ev');
    expect(row.pos, isNull);
    // The v28 `pos` column is still the subject of this file, but the app has
    // moved on since; assert the upgrade lands on the current version rather
    // than pinning 28, which went stale the moment v29 was added.
    final version = await db.customSelect('PRAGMA user_version').getSingle();
    expect(version.read<int>('user_version'), CourseDatabase.kSchemaVersion);
  });
}
