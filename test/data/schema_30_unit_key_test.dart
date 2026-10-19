import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqlite3/sqlite3.dart' as sqlite;
import 'package:turna/data/course_database.dart';

void main() {
  test('schema 29 course-tree view gains unit_key and keeps its rows',
      () async {
    final dir = await Directory.systemTemp.createTemp('turna_schema30_');
    addTearDown(() async {
      if (dir.existsSync()) await dir.delete(recursive: true);
    });
    final path = p.join(dir.path, 'course.db');
    final raw = sqlite.sqlite3.open(path);
    raw
      ..execute('''
        CREATE TABLE anki_course_tree_view (
          source_id TEXT NOT NULL,
          card_id INTEGER NOT NULL,
          note_id INTEGER NOT NULL,
          deck_id INTEGER NOT NULL,
          word_id TEXT NOT NULL,
          section_key TEXT NOT NULL,
          section_id TEXT NOT NULL,
          unit_id TEXT NOT NULL,
          lesson_id TEXT NOT NULL,
          lesson_key TEXT NOT NULL,
          presentation_kind TEXT NOT NULL,
          source_hash TEXT NOT NULL,
          mapping_version INTEGER NOT NULL,
          rebuilt_at_millis INTEGER NOT NULL,
          PRIMARY KEY(source_id, card_id)
        )
      ''')
      ..execute(
        "INSERT INTO anki_course_tree_view ("
        "source_id, card_id, note_id, deck_id, word_id, section_key, "
        "section_id, unit_id, lesson_id, lesson_key, presentation_kind, "
        "source_hash, mapping_version, rebuilt_at_millis) VALUES ("
        "'src', 1, 2, 3, 'w', 'Deck', 'sec', 'unit', 'lesson', 'Noun', "
        "'flip', 'hash', 1, 4)",
      )
      ..execute('PRAGMA user_version = 29')
      ..dispose();

    final db = CourseDatabase(NativeDatabase(File(path)));
    addTearDown(db.close);
    await db.customSelect('SELECT 1').get();

    expect(db.schemaVersion, CourseDatabase.kSchemaVersion);
    final columns =
        await db.customSelect('PRAGMA table_info(anki_course_tree_view)').get();
    expect(
      columns.any((row) => row.read<String>('name') == 'unit_key'),
      isTrue,
    );
    final row = await db
        .customSelect(
          'SELECT lesson_key, unit_key FROM anki_course_tree_view',
        )
        .getSingle();
    expect(row.read<String>('lesson_key'), 'Noun');
    expect(row.read<String>('unit_key'), '');
    final version = await db.customSelect('PRAGMA user_version').getSingle();
    expect(version.read<int>('user_version'), CourseDatabase.kSchemaVersion);
  });
}
