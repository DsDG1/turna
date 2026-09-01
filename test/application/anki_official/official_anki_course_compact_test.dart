import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:turna/application/anki_official/contract/official_anki_dto.dart';
import 'package:turna/application/anki_official/engine/official_anki_engine_fake.dart';
import 'package:turna/application/anki_official/lifecycle/official_anki_lifecycle_models.dart';
import 'package:turna/application/anki_official/lifecycle/official_anki_maintenance.dart';
import 'package:turna/application/anki_official/lifecycle/official_anki_uninstall_saga.dart';
import 'package:turna/application/anki_official/official_anki_paths.dart';
import 'package:turna/application/anki_official/storage/official_anki_database.dart';
import 'package:turna/application/anki_official/storage/official_anki_source_dao.dart';
import 'package:turna/data/course_database.dart';

import '../../helpers/in_memory_course_db.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  ensureSqliteLibForTestHost();

  test('compactCourseDatabase skips when course handle is missing', () async {
    final result = await OfficialAnkiMaintenanceRunner.compactCourseDatabase(
      null,
    );
    expect(result.skippedReason, 'course_db_unavailable');
  });

  test('compactCourseDatabase skips below threshold unless forced', () async {
    final db = CourseDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    final skipped = await OfficialAnkiMaintenanceRunner.compactCourseDatabase(
      db,
    );
    expect(skipped.skippedReason, 'below_threshold');
    final forced = await OfficialAnkiMaintenanceRunner.compactCourseDatabase(
      db,
      force: true,
    );
    expect(forced.skippedReason, isNull);
  });

  test('forced VACUUM on file-backed course.db keeps schema and stays open',
      () async {
    final root = Directory.systemTemp.createTempSync('turna-course-compact-');
    addTearDown(() {
      try {
        root.deleteSync(recursive: true);
      } catch (_) {}
    });
    final file = File(p.join(root.path, 'course.db'));
    final db = CourseDatabase(NativeDatabase(file));
    addTearDown(db.close);
    await db.customStatement(
      'CREATE TABLE IF NOT EXISTS compact_junk (id INTEGER PRIMARY KEY, blob TEXT)',
    );
    for (var i = 0; i < 200; i++) {
      await db.customStatement(
        'INSERT INTO compact_junk (blob) VALUES (?)',
        [List.filled(256, 'x').join()],
      );
    }
    await db.customStatement('DELETE FROM compact_junk');
    final before = file.lengthSync();
    final result = await OfficialAnkiMaintenanceRunner.compactCourseDatabase(
      db,
      force: true,
    );
    expect(result.skippedReason, isNull);
    expect(file.lengthSync(), lessThanOrEqualTo(before));
    final version = await db.customSelect('PRAGMA user_version').getSingle();
    expect(version.data.values.first, CourseDatabase.kSchemaVersion);
    final stillOpen = await db.customSelect('SELECT 1 AS n').getSingle();
    expect(stillOpen.data.values.first, 1);
  });

  test('compactCollection without engine keeps the job alive (retry_wait)',
      () async {
    // Regression (field report 2026-09-01): the runner used to fall back
    // to compactSqliteFile on collection.anki2, whose rslib schema carries
    // `COLLATE unicase` b-trees — that raw VACUUM fails with "no such
    // collation sequence" on any real collection. Engine-absent must fail
    // into retry_wait and stay pending for a later engine-backed run
    // (same keep-alive contract as v2_source_delete). The retired path
    // would have marked this job completed (skip 'missing' on the absent
    // file), which is exactly the degradation this test pins down.
    final catalog = OfficialAnkiDatabase.memory();
    addTearDown(catalog.close);
    final root = Directory.systemTemp.createTempSync('turna-compact-keep-');
    addTearDown(() {
      try {
        root.deleteSync(recursive: true);
      } catch (_) {}
    });
    const profileId = 'p-keep-01';
    final paths = OfficialAnkiPaths(profileId: profileId, profileRoot: root);

    OfficialAnkiMaintenanceJobDao(catalog).enqueue(
      profileId: profileId,
      kind: OfficialAnkiMaintenanceKind.compactCollection,
      nowMillis: 1,
    );

    final completed = await OfficialAnkiMaintenanceRunner(
      catalog: catalog,
      paths: paths,
      forceCompact: true,
    ).runPending(profileId: profileId);

    expect(completed, 0, reason: 'engine-absent job must not complete');
    final rows = catalog.handle.select(
      'SELECT state FROM anki_maintenance_jobs WHERE profile_id = ?',
      [profileId],
    );
    expect(rows, hasLength(1));
    expect(
      rows.first['state'],
      OfficialAnkiMaintenanceJobState.retryWait.wire,
    );
    expect(
      OfficialAnkiMaintenanceJobDao(catalog).pending(profileId: profileId),
      hasLength(1),
      reason: 'retry_wait stays discoverable for the next engine-backed run',
    );
  });

  test('uninstall enqueues compact_course with other maintenance kinds',
      () async {
    final catalog = OfficialAnkiDatabase.memory();
    addTearDown(catalog.close);
    final engine = FakeOfficialAnkiEngine();
    engine.cards[1] = const OfficialAnkiCardDescriptor(
      cardId: 1,
      noteId: 1,
      deckId: 1,
      templateOrd: 0,
      noteGuid: 'g',
      notetypeId: 1,
    );
    final sources = OfficialAnkiSourceDao(catalog);
    sources.upsertSource(
      sourceId: 'src-c',
      profileId: 'profile-c-01',
      sourceHash: 'h',
      sourceSize: 1,
      displayName: 'c',
      state: 'active',
      backendCommit: 'b',
      nowMillis: 1,
    );
    sources.upsertCardBatch(
      sourceId: 'src-c',
      cards: [engine.cards[1]!],
    );
    final root = Directory.systemTemp.createTempSync('turna-un-c-');
    addTearDown(() => root.deleteSync(recursive: true));
    await OfficialAnkiUninstallSaga(
      catalog: catalog,
      engine: engine,
      paths: OfficialAnkiPaths(
        profileId: 'profile-c-01',
        profileRoot: root,
      ),
    ).run('src-c');
    final kinds = catalog.handle
        .select(
          'SELECT kind FROM anki_maintenance_jobs WHERE profile_id = ?',
          ['profile-c-01'],
        )
        .map((row) => row['kind'] as String)
        .toSet();
    expect(kinds, contains(OfficialAnkiMaintenanceKind.compactCourse.wire));
    expect(kinds, contains(OfficialAnkiMaintenanceKind.compactCatalog.wire));
  });
}
