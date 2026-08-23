// Plan 1 Phase 1 integration coverage: the dedup authority is the persisted
// inventory, exercised through the production lookups (anki_imports rows and
// the official catalog) instead of the function seams.

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:turna/application/anki/unified_anki_import_orchestrator.dart';
import 'package:turna/application/anki_official/official_anki_composition.dart';
import 'package:turna/application/anki_official/storage/official_anki_database.dart';
import 'package:turna/application/anki_official/storage/official_anki_source_dao.dart';
import 'package:turna/data/anki_import_dao.dart';
import 'package:turna/data/anki_unification_dao.dart';
import 'package:turna/data/course_database.dart';

import '../../helpers/in_memory_course_db.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  ensureSqliteLibForTestHost();
  ensurePathProviderMockForTest();

  late CourseDatabase db;
  late AnkiImportDao importDao;

  setUp(() async {
    final getIt = GetIt.instance;
    await getIt.reset();
    db = CourseDatabase(NativeDatabase.memory());
    importDao = AnkiImportDao(db);
    getIt.registerSingleton<CourseDatabase>(db);
    getIt.registerSingleton<AnkiImportDao>(importDao);
    getIt.registerSingleton<AnkiUnificationDao>(AnkiUnificationDao(db));
    UnifiedAnkiImportOrchestrator.instance.reset();
  });

  tearDown(() async {
    UnifiedAnkiImportOrchestrator.instance.reset();
    OfficialAnkiCompositionRoot.readOnlyCatalog = null;
    await db.close();
    await GetIt.instance.reset();
  });

  Future<AnkiImportRecord> insertImportRow(
    String importId,
    String hash, {
    String? status,
  }) async {
    final record = AnkiImportRecord(
      importId: importId,
      sourcePath: '/tmp/$importId.apkg',
      sourceHash: hash,
      importedAt: 1,
    );
    await importDao.upsert(record);
    if (status == 'complete') {
      await importDao.markComplete(
        importId,
        sourceCardCount: 0,
        indexedCardCount: 0,
        importedScheduling: false,
      );
    } else if (status != null) {
      await importDao.markFailed(importId, reason: 'test');
    }
    return record;
  }

  test('complete inventory row is a noOp; deleting it re-enables import',
      () async {
    await insertImportRow('imp-inv', 'hash-inv', status: 'complete');

    final dup = await UnifiedAnkiImportOrchestrator.instance.importPackage(
      const UnifiedAnkiImportRequest(
        importId: 'imp-inv2',
        sourceHash: 'hash-inv',
        canonicalCardIds: [1],
        officialCapable: false,
      ),
    );
    expect(dup.noOp, isTrue,
        reason: 'a complete import of this hash already exists');

    // Uninstall drops the row and invalidates process caches.
    await importDao.delete('imp-inv');
    UnifiedAnkiImportOrchestrator.instance.invalidate(importId: 'imp-inv');

    final reimport = await UnifiedAnkiImportOrchestrator.instance
        .importPackage(const UnifiedAnkiImportRequest(
      importId: 'imp-inv2',
      sourceHash: 'hash-inv',
      canonicalCardIds: [1],
      officialCapable: false,
    ));
    expect(reimport.noOp, isFalse,
        reason: 'same-process re-import after delete must run for real');
    expect(reimport.turnaSrsWordIds, {'anki-imp-inv2-c1'});
  });

  test('failed inventory row never produces a fake noOp', () async {
    await insertImportRow('imp-f', 'hash-f', status: 'failed');

    final result = await UnifiedAnkiImportOrchestrator.instance.importPackage(
      const UnifiedAnkiImportRequest(
        importId: 'imp-f',
        sourceHash: 'hash-f',
        canonicalCardIds: [5],
        officialCapable: false,
      ),
    );
    expect(result.noOp, isFalse,
        reason: 'a failed import is not a usable "already imported" state');
  });

  test('official catalog active source is a noOp; terminal failure is not',
      () async {
    final catalog = OfficialAnkiDatabase.memory();
    OfficialAnkiCompositionRoot.readOnlyCatalog = catalog;
    final sources = OfficialAnkiSourceDao(catalog);
    sources.upsertSource(
      sourceId: 'src-inv',
      profileId: 'profile-default-01',
      sourceHash: 'hash-official',
      sourceSize: 1,
      displayName: 'deck',
      state: 'active',
      backendCommit: 'test',
      nowMillis: 1,
    );

    final active = await UnifiedAnkiImportOrchestrator.instance.importPackage(
      const UnifiedAnkiImportRequest(
        importId: 'whatever',
        sourceHash: 'hash-official',
        canonicalCardIds: [1],
        officialCapable: true,
      ),
    );
    expect(active.noOp, isTrue,
        reason: 'an active official source owns this hash');

    sources.transitionSource(
      sourceId: 'src-inv',
      expectedState: 'active',
      nextState: 'failed_after_import',
      nowMillis: 2,
    );
    UnifiedAnkiImportOrchestrator.instance.invalidate(importId: 'whatever');

    final broken = await UnifiedAnkiImportOrchestrator.instance.importPackage(
      const UnifiedAnkiImportRequest(
        importId: 'whatever',
        sourceHash: 'hash-official',
        canonicalCardIds: [1],
        officialCapable: true,
      ),
    );
    expect(broken.noOp, isFalse,
        reason: 'a failed official source must not block re-import');
  });
}
