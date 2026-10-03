// Tests for the `PRAGMA table_info` shim's DDL parser.
//
// The bridge itself can only be exercised on a device, so this pins the half
// that can be checked anywhere: turning a stored CREATE statement into the
// column list drift's `Migrator.hasColumn` compares against. The statements
// used here are the ones this project actually generates, copied out of the
// device log of the ArkData-backed course database.

import 'package:flutter_test/flutter_test.dart';
import 'package:turna/data/rdb_schema_introspection.dart';

void main() {
  group('parseCreateTableColumns', () {
    test('reads a simple table', () {
      final columns = parseCreateTableColumns(
        'CREATE TABLE IF NOT EXISTS "course_meta" '
        '("key" TEXT NOT NULL, "value" TEXT NOT NULL, PRIMARY KEY ("key"))',
      );

      expect(columns.map((c) => c.name), ['key', 'value']);
      expect(columns.every((c) => c.type == 'TEXT'), isTrue);
    });

    test('skips a table-level primary key constraint', () {
      final columns = parseCreateTableColumns(
        'CREATE TABLE "sections" ('
        '"id" TEXT NOT NULL, '
        '"sort_order" INTEGER NOT NULL DEFAULT 0, '
        'PRIMARY KEY ("id"))',
      );

      expect(columns.map((c) => c.name), ['id', 'sort_order']);
      expect(columns[1].type, 'INTEGER');
    });

    test('does not split on a comma inside a CHECK constraint', () {
      // `CHECK ("ai_enhanced" IN (0, 1))` contains both a comma and nested
      // parentheses; splitting naively would invent a column named `1)`.
      final columns = parseCreateTableColumns(
        'CREATE TABLE IF NOT EXISTS "anki_imports" ('
        '"import_id" TEXT NOT NULL, '
        '"ai_enhanced" INTEGER NOT NULL DEFAULT 0 '
        'CHECK ("ai_enhanced" IN (0, 1)), '
        '"version" INTEGER NOT NULL DEFAULT 1, '
        'PRIMARY KEY ("import_id"))',
      );

      expect(columns.map((c) => c.name), ['import_id', 'ai_enhanced', 'version']);
    });

    test('does not split on a comma inside a quoted default', () {
      final columns = parseCreateTableColumns(
        'CREATE TABLE "sections" ('
        '"id" TEXT NOT NULL, '
        '"prerequisite_section_ids" TEXT NOT NULL DEFAULT \'[]\', '
        '"level" TEXT NOT NULL DEFAULT \'\', '
        'PRIMARY KEY ("id"))',
      );

      expect(
        columns.map((c) => c.name),
        ['id', 'prerequisite_section_ids', 'level'],
      );
    });

    test('handles a composite primary key across the course tree', () {
      final columns = parseCreateTableColumns(
        'CREATE TABLE IF NOT EXISTS "sections" ('
        '"id" TEXT NOT NULL, '
        '"language_code" TEXT NOT NULL DEFAULT \'tr\', '
        '"name" TEXT NOT NULL, '
        'PRIMARY KEY ("language_code", "id"))',
      );

      expect(columns.map((c) => c.name), ['id', 'language_code', 'name']);
    });

    test('keeps an autoincrement column', () {
      final columns = parseCreateTableColumns(
        'CREATE TABLE IF NOT EXISTS "review_events" ('
        '"id" INTEGER NOT NULL PRIMARY KEY AUTOINCREMENT, '
        '"card_id" TEXT NOT NULL, '
        '"reviewed_at" INTEGER NOT NULL, '
        '"ease" REAL NOT NULL DEFAULT 2.5)',
      );

      expect(columns.map((c) => c.name),
          ['id', 'card_id', 'reviewed_at', 'ease']);
      expect(columns[0].type, 'INTEGER');
      expect(columns[3].type, 'REAL');
    });

    test('reports a column with no declared type as empty', () {
      final columns = parseCreateTableColumns(
        'CREATE TABLE "t" ("a" PRIMARY KEY, "b" TEXT)',
      );

      expect(columns.map((c) => c.name), ['a', 'b']);
      expect(columns[0].type, isEmpty);
      expect(columns[1].type, 'TEXT');
    });

    test('skips a foreign key clause', () {
      final columns = parseCreateTableColumns(
        'CREATE TABLE "lessons" ('
        '"id" TEXT NOT NULL, '
        '"unit_id" TEXT NOT NULL, '
        'FOREIGN KEY ("unit_id") REFERENCES "units" ("id"))',
      );

      expect(columns.map((c) => c.name), ['id', 'unit_id']);
    });

    test('returns nothing for a statement that is not a table', () {
      expect(parseCreateTableColumns('CREATE INDEX ix ON t (a)'), isEmpty);
      expect(parseCreateTableColumns(''), isEmpty);
    });

    test('tolerates a multi-word declared type', () {
      final columns = parseCreateTableColumns(
        'CREATE TABLE "t" ("a" DOUBLE PRECISION NOT NULL, "b" TEXT)',
      );

      expect(columns[0].name, 'a');
      expect(columns[0].type, 'DOUBLE PRECISION');
      expect(columns[1].name, 'b');
    });
  });
}
