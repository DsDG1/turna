import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:turna/application/maintenance/storage_inventory_service.dart';
import 'package:turna/data/course_database.dart';

import '../../helpers/in_memory_course_db.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  ensureSqliteLibForTestHost();
  ensurePathProviderMockForTest();

  late CourseDatabase db;
  // System temp is shared across test suites: every directory this suite
  // creates carries a unique stamp so scans only ever inspect their own dirs.
  late String stamp;

  setUp(() async {
    final getIt = GetIt.instance;
    await getIt.reset();
    db = CourseDatabase(NativeDatabase.memory());
    getIt.registerSingleton<CourseDatabase>(db);
    stamp = 'inv${DateTime.now().microsecondsSinceEpoch}';
  });

  tearDown(() async {
    final mediaRoot = Directory('${Directory.systemTemp.path}/anki_media');
    if (mediaRoot.existsSync()) {
      final mediaNames = mediaRoot
          .listSync(followLinks: false)
          .whereType<Directory>()
          .where((d) => d.path.contains(stamp))
          .toList();
      for (final dir in mediaNames) {
        try {
          dir.deleteSync(recursive: true);
        } catch (_) {/* best-effort temp cleanup */}
      }
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

  StorageInventoryService scanner() =>
      StorageInventoryService(documentsDirectory: Directory.systemTemp);

  test('reports every anki_media dir as orphaned legacy media with confirmOnly',
      () async {
    await writeMediaFile('first', 'a.mp3', 100);
    await writeMediaFile('second', 'b.mp3', 50);

    final report = await scanner().scan();

    final mediaDirs = report.mediaDirsByOwner;
    final first = mediaDirs.singleWhere((a) => a.ownerId == dirName('first'));
    expect(first.category, StorageArtifactCategory.legacyAnkiMedia);
    expect(first.orphaned, isTrue);
    expect(first.physicalBytes, 100);
    expect(first.fileCount, 1);
    expect(first.cleanupPolicy, StorageCleanupPolicy.confirmOnly,
        reason: 'retired legacy media dirs need explicit confirmation');

    final second = mediaDirs.singleWhere((a) => a.ownerId == dirName('second'));
    expect(second.category, StorageArtifactCategory.legacyAnkiMedia);
    expect(second.orphaned, isTrue);
    expect(second.physicalBytes, 50);
    expect(second.fileCount, 1);
    expect(second.cleanupPolicy, StorageCleanupPolicy.confirmOnly);
  });

  test('reports database file/wal/freelist and cache categories', () async {
    await writeMediaFile('solo', 'a.mp3', 10);
    final report = await scanner().scan();

    final mainDb = report.artifact(StorageArtifactCategory.mainDatabase);
    expect(mainDb, isNotNull);
    expect(mainDb!.cleanupPolicy, StorageCleanupPolicy.optimize);
    // In-memory connection: no file bytes, but page stats still answer.
    expect(report.freelistBytes, greaterThanOrEqualTo(0));

    // Legacy `anki_imports` table retired at schema v35; any leftover
    // `anki_media/<dir>` directory surfaces solely as orphaned legacyAnkiMedia.
    expect(report.artifact(StorageArtifactCategory.legacyAnki), isNull);
    final solo = report.mediaDirsByOwner
        .singleWhere((a) => a.ownerId == dirName('solo'));
    expect(solo.orphaned, isTrue);
    expect(solo.cleanupPolicy, StorageCleanupPolicy.confirmOnly);

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

    final report = await scanner().scan();

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

    final report = await scanner().scan();
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
