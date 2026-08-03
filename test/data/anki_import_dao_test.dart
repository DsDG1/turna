// Package imports:
import 'package:drift/drift.dart' hide isNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';

// Project imports:
import 'package:varnamala/data/anki_import_dao.dart';
import 'package:varnamala/data/course_database.dart' as db;

import '../helpers/in_memory_course_db.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  ensureSqliteLibForTestHost();

  group('AnkiImportDao', () {
    late db.CourseDatabase database;
    late AnkiImportDao dao;

    setUp(() {
      database = db.CourseDatabase(NativeDatabase.memory());
      dao = AnkiImportDao(database);
    });

    tearDown(() async {
      await database.close();
    });

    // The schema adds `status` / `last_error` columns via `addColumn` (not
    // declared on the [AnkiImports] drift table), so seed and read both go
    // through raw SQL — mirroring how [AnkiImportDao] itself writes.
    Future<void> seedRow(
      String importId, {
      String status = 'pending',
      String? lastError,
    }) async {
      await database.customStatement(
        '''
        INSERT INTO anki_imports
            (import_id, source_path, source_hash, imported_at,
             status, last_error)
        VALUES (?, ?, ?, ?, ?, ?)
        ''',
        [
          importId,
          '/tmp/$importId.apkg',
          'hash-$importId',
          1700000000,
          status,
          lastError,
        ],
      );
    }

    Future<Map<String, Object?>> readRow(String importId) async {
      final row = await database
          .customSelect(
            'SELECT status, last_error FROM anki_imports WHERE import_id = ?',
            variables: [Variable.withString(importId)],
          )
          .getSingleOrNull();
      return row?.data ?? const {};
    }

    test('markFailed flips status from pending to failed with reason', () async {
      await seedRow('imp-1');

      expect((await readRow('imp-1'))['status'], 'pending');

      await dao.markFailed('imp-1', reason: 'cancelled by user');

      final row = await readRow('imp-1');
      expect(row['status'], 'failed');
      expect(row['last_error'], 'cancelled by user');
    });

    test('markFailed without a reason stores NULL last_error', () async {
      await seedRow('imp-2');

      await dao.markFailed('imp-2');

      final row = await readRow('imp-2');
      expect(row['status'], 'failed');
      expect(row['last_error'], isNull);
    });

    test('markFailed is idempotent on re-mark', () async {
      await seedRow('imp-3', status: 'failed', lastError: 'first');

      await dao.markFailed('imp-3', reason: 'second');

      final row = await readRow('imp-3');
      expect(row['status'], 'failed');
      expect(row['last_error'], 'second');
    });

    test('markFailed on a non-existent importId is a no-op', () async {
      // The WHERE import_id = ? clause matches zero rows; no error.
      await dao.markFailed('does-not-exist', reason: 'orphan');
      final row = await database
          .customSelect(
            'SELECT 1 FROM anki_imports WHERE import_id = ?',
            variables: [Variable.withString('does-not-exist')],
          )
          .getSingleOrNull();
      expect(row, isNull);
    });
  });
}