import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqlite3/sqlite3.dart' as sqlite;
import 'package:turna/data/course_database.dart';

void main() {
  test(
      'schema 29 course-tree view migrates to v35 with unit_key and without '
      'presentation_kind', () async {
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
    final columnNames = {for (final row in columns) row.read<String>('name')};
    expect(columnNames.contains('unit_key'), isTrue);
    expect(columnNames.contains('presentation_kind'), isFalse);
    final rows =
        await db.customSelect('SELECT * FROM anki_course_tree_view').get();
    expect(rows, isEmpty,
        reason: 'v35 drops and rebuilds the stateless view without '
            'presentation_kind');
    final version = await db.customSelect('PRAGMA user_version').getSingle();
    expect(version.read<int>('user_version'), CourseDatabase.kSchemaVersion);
  });
}
