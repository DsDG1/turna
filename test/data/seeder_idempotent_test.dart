// Regression: DatabaseSeeder must be safe across cold starts.
//
// Root cause of "first launch OK, second launch stuck": seedIfNeeded treated
// an empty expressions table as "DB empty" even when expressions.json is
// legitimately `[]`. Second open re-INSERTed without clearing and hit PK
// conflicts inside setupLocator before runApp.
//
// Invariant under test: skip iff contentVersion matches asset version AND
// sections exist; any write path clears course tables before INSERT.

import 'dart:io';

import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:varnamala/data/course_database.dart';
import 'package:varnamala/data/course_database_seeder.dart';

import '../helpers/in_memory_course_db.dart';

Future<String> _tempDbPath() async {
  final dir = await Directory.systemTemp.createTemp('varnamala_seeder_');
  return p.join(dir.path, 'course.swahili.db');
}

Set<String> _ids(Iterable<dynamic> rows) =>
    rows.map((r) => r.id as String).toSet();

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  ensureSqliteLibForTestHost();

  group('DatabaseSeeder.seedIfNeeded', () {
    test('second open with empty expressions asset does not reseed or throw',
        () async {
      final path = await _tempDbPath();
      addTearDown(() async {
        final parent = File(path).parent;
        if (await parent.exists()) {
          await parent.delete(recursive: true);
        }
      });

      final db1 = CourseDatabase(NativeDatabase(File(path)));
      final first = await DatabaseSeeder(db1).seedIfNeeded();
      expect(first, isTrue, reason: 'first open should seed');

      final sections1 = await db1.select(db1.sections).get();
      final vocab1 = await db1.select(db1.vocabulary).get();
      final grammar1 = await db1.select(db1.grammarPoints).get();
      final expressions1 = await db1.select(db1.expressions).get();
      final meta1 = await (db1.select(db1.courseMeta)
            ..where((t) => t.key.equals(DatabaseSeeder.metaContentVersion)))
          .getSingleOrNull();

      expect(sections1, isNotEmpty);
      expect(vocab1, isNotEmpty);
      expect(grammar1, isNotEmpty);
      // Current asset is legitimately empty — this is what triggered the bug.
      expect(expressions1, isEmpty);
      expect(meta1, isNotNull);

      await db1.close();

      final db2 = CourseDatabase(NativeDatabase(File(path)));
      final second = await DatabaseSeeder(db2).seedIfNeeded();
      expect(second, isFalse,
          reason: 'second open must skip reseed (no PK conflicts)');

      expect(_ids(await db2.select(db2.sections).get()), _ids(sections1));
      expect(_ids(await db2.select(db2.vocabulary).get()), _ids(vocab1));
      expect(_ids(await db2.select(db2.grammarPoints).get()), _ids(grammar1));

      await db2.close();
    });

    test('in-memory double seedIfNeeded is idempotent', () async {
      final db = CourseDatabase(NativeDatabase.memory());
      addTearDown(db.close);

      expect(await DatabaseSeeder(db).seedIfNeeded(), isTrue);
      expect(await DatabaseSeeder(db).seedIfNeeded(), isFalse);
      expect(await DatabaseSeeder(db).seedIfNeeded(), isFalse);
    });

    test('orphan vocabulary without sections clears and reseeds without PK crash',
        () async {
      final db = CourseDatabase(NativeDatabase.memory());
      addTearDown(db.close);

      // First full seed so meta + tables exist.
      expect(await DatabaseSeeder(db).seedIfNeeded(), isTrue);
      final meta = await (db.select(db.courseMeta)
            ..where((t) => t.key.equals(DatabaseSeeder.metaContentVersion)))
          .getSingle();
      final version = meta.value;

      // Simulate residue: wipe sections tree but leave vocabulary + matching meta.
      await db.transaction(() async {
        await db.delete(db.lessonContents).go();
        await db.delete(db.lessons).go();
        await db.delete(db.units).go();
        await db.delete(db.sections).go();
        // Keep vocabulary + grammar + courseMeta intentionally.
      });

      expect(await (db.select(db.sections)..limit(1)).get(), isEmpty);
      expect(await (db.select(db.vocabulary)..limit(1)).get(), isNotEmpty);
      expect(
        (await (db.select(db.courseMeta)
                  ..where(
                      (t) => t.key.equals(DatabaseSeeder.metaContentVersion)))
                .getSingle())
            .value,
        version,
      );

      // Must clear residue then reseed — must not throw on PK.
      final reseeds = await DatabaseSeeder(db).seedIfNeeded();
      expect(reseeds, isTrue);

      expect(await (db.select(db.sections)..limit(1)).get(), isNotEmpty);
      expect(await (db.select(db.vocabulary)..limit(1)).get(), isNotEmpty);
      expect(
        (await (db.select(db.courseMeta)
                  ..where(
                      (t) => t.key.equals(DatabaseSeeder.metaContentVersion)))
                .getSingle())
            .value,
        version,
      );
    });

    test('version bump clears and reseeds', () async {
      final db = CourseDatabase(NativeDatabase.memory());
      addTearDown(db.close);

      expect(await DatabaseSeeder(db).seedIfNeeded(), isTrue);
      final beforeSections = _ids(await db.select(db.sections).get());
      expect(beforeSections, isNotEmpty);

      // Force a stale content version while leaving rows in place.
      await db.into(db.courseMeta).insertOnConflictUpdate(
            const CourseMetaCompanion(
              key: Value(DatabaseSeeder.metaContentVersion),
              value: Value('__stale_for_test__'),
            ),
          );

      final reseeds = await DatabaseSeeder(db).seedIfNeeded();
      expect(reseeds, isTrue);

      final afterSections = _ids(await db.select(db.sections).get());
      expect(afterSections, beforeSections);

      final meta = await (db.select(db.courseMeta)
            ..where((t) => t.key.equals(DatabaseSeeder.metaContentVersion)))
          .getSingle();
      expect(meta.value, isNot(equals('__stale_for_test__')));
    });
  });
}
