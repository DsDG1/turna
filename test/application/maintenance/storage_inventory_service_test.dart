import 'dart:io';

import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:turna/application/maintenance/storage_inventory_service.dart';
import 'package:turna/data/anki_import_dao.dart';
import 'package:turna/data/anki_note_dao.dart';
import 'package:turna/data/course_database.dart';

import '../../helpers/in_memory_course_db.dart';
import '../../helpers/anki_import_seed.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  ensureSqliteLibForTestHost();
  ensurePathProviderMockForTest();

  late CourseDatabase db;
  // Path-provider mock resolves to the system temp dir, which other test
  // suites share: every directory this suite creates carries a unique stamp
  // so scans only ever see their own artifacts.
  late String stamp;

  setUp(() async {
    final getIt = GetIt.instance;
    await getIt.reset();
    db = CourseDatabase(NativeDatabase.memory());
    getIt.registerSingleton<CourseDatabase>(db);
    getIt.registerSingleton<AnkiNoteDao>(AnkiNoteDao(db));
    stamp = 'inv${DateTime.now().microsecondsSinceEpoch}';
  });

  tearDown(() async {
    final mediaNames = Directory('${Directory.systemTemp.path}/anki_media')
        .listSync(followLinks: false)
        .whereType<Directory>()
        .where((d) => d.path.contains(stamp))
        .toList();
    for (final dir in mediaNames) {
      try {
        dir.deleteSync(recursive: true);
      } catch (_) {}
    }
    await db.close();
    await GetIt.instance.reset();
  });

  String dirName(String id) => '$stamp-$id';

  Future<void> writeMediaFile(String id, String name, int bytes) async {
    final dir =
        Directory('${Directory.systemTemp.path}/anki_media/${dirName(id)}');
    await dir.create(recursive: true);
    await File('${dir.path}/$name').writeAsBytes(List.filled(bytes, 1));
  }

  /// Seed the course-tree section row that makes a legacy import "visible"
  /// — ownership now requires both the import row and a live section.
  Future<void> seedDeckSection(String id) async {
    await db.into(db.sections).insert(
          SectionsCompanion(
            id: Value('anki-${dirName(id)}-s1'),
            name: Value('Deck $id'),
            sortOrder: const Value(1),
          ),
        );
  }

  test('attributes every media dir to its owner and flags orphans', () async {
    await seedAnkiImportRow(
      db,
      AnkiImportRecord(
        importId: dirName('owned'),
        sourcePath: '/tmp/a.apkg',
        sourceHash: 'hash-owned',
        importedAt: 1,
      ),
    );
    await seedDeckSection('owned');
    await writeMediaFile('owned', 'a.mp3', 100);
    await writeMediaFile('ghost', 'b.mp3', 50);

    final report = await const StorageInventoryService().scan();

    final mediaDirs = report.mediaDirsByOwner;
    final owned = mediaDirs.singleWhere((a) => a.ownerId == dirName('owned'));
    expect(owned.orphaned, isFalse);
    expect(owned.physicalBytes, 100);
    expect(owned.fileCount, 1);
    expect(owned.cleanupPolicy, StorageCleanupPolicy.deleteSaga,
        reason: 'owned media is user data; only the delete saga removes it');

    final ghost = mediaDirs.singleWhere((a) => a.ownerId == dirName('ghost'));
    expect(ghost.orphaned, isTrue,
        reason: 'a media dir without an import row is an orphan');
    expect(ghost.physicalBytes, 50);
    expect(ghost.cleanupPolicy, StorageCleanupPolicy.confirmOnly,
        reason: 'orphans need explicit confirmation, never auto-delete');
  });

  test('a staging import row owns media before course visibility commit',
      () async {
    // Commit-last imports intentionally have a durable import row before
    // their course tree is visible. Inventory must use exact ownership,
    // otherwise a valid staging directory is offered as an orphan cleanup.
    await seedAnkiImportRow(
      db,
      AnkiImportRecord(
        importId: dirName('stuck'),
        sourcePath: '/tmp/s.apkg',
        sourceHash: 'hash-stuck',
        importedAt: 1,
      ),
    );
    await writeMediaFile('stuck', 's.mp3', 20);

    final report = await const StorageInventoryService().scan();

    final stuck = report.mediaDirsByOwner
        .singleWhere((a) => a.ownerId == dirName('stuck'));
    expect(stuck.orphaned, isFalse);
    expect(stuck.cleanupPolicy, StorageCleanupPolicy.deleteSaga);
  });

  test('reports database file/wal/freelist and cache categories', () async {
    await writeMediaFile('solo', 'a.mp3', 10);
    final report = await const StorageInventoryService().scan();

    final mainDb = report.artifact(StorageArtifactCategory.mainDatabase);
    expect(mainDb, isNotNull);
    expect(mainDb!.cleanupPolicy, StorageCleanupPolicy.optimize);
    // In-memory connection: no file bytes, but page stats still answer.
    expect(report.freelistBytes, greaterThanOrEqualTo(0));

    // The anki prerender cache artifact was removed with its table (schema
    // v22); logs remain the only safeClear artifact in this environment.

    final legacy = report.artifact(StorageArtifactCategory.legacyAnki);
    expect(legacy!.cleanupPolicy, StorageCleanupPolicy.deleteSaga);

    expect(report.scannedAt, isNotNull);
    expect(report.aiCacheEntries, 0);
  });

  test('scans the official profile directory without opening engines',
      () async {
    final profileId = '$stamp-profile';
    final officialRoot =
        Directory('${Directory.systemTemp.path}/official_anki/$profileId');
    await officialRoot.create(recursive: true);
    await File('${officialRoot.path}/collection.anki2')
        .writeAsBytes(List.filled(4096, 0));
    addTearDown(() => officialRoot.delete(recursive: true));

    final report = await const StorageInventoryService().scan();

    final official =
        report.artifacts.singleWhere((a) => a.ownerId == profileId);
    expect(official.category, StorageArtifactCategory.officialAnki);
    expect(official.physicalBytes, 4096);
    expect(official.fileCount, 1);
    expect(official.cleanupPolicy, StorageCleanupPolicy.deleteSaga,
        reason: 'collection/catalog files are reclaimed via the owner saga');
  });

  test('lists leftover official_anki/staging dirs as diagnostics', () async {
    final leftover = Directory(
      '${Directory.systemTemp.path}/official_anki/staging/$stamp-orphan',
    );
    await leftover.create(recursive: true);
    await File('${leftover.path}/collection.anki2')
        .writeAsBytes(List.filled(2048, 0));
    addTearDown(() => leftover.delete(recursive: true));

    final report = await const StorageInventoryService().scan();
    final staging = report.artifacts.singleWhere(
      (a) => a.ownerId == '$stamp-orphan',
    );
    expect(staging.category, StorageArtifactCategory.officialAnki);
    expect(staging.label, contains('no ledger'));
    expect(staging.orphaned, isTrue);
    expect(staging.cleanupPolicy, StorageCleanupPolicy.confirmOnly);
    expect(staging.physicalBytes, 2048);
  });
}
