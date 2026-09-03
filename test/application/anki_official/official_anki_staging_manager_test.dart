import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:turna/application/anki_official/engine/official_anki_engine_fake.dart';
import 'package:turna/application/anki_official/import/official_anki_import_saga.dart';
import 'package:turna/application/anki_official/import/official_anki_staging_manager.dart';
import 'package:turna/application/anki_official/lifecycle/official_anki_lifecycle_models.dart';
import 'package:turna/application/anki_official/official_anki_composition.dart';
import 'package:turna/application/anki_official/official_anki_paths.dart';
import 'package:turna/application/anki_official/storage/official_anki_database.dart';
import 'package:turna/application/anki_official/storage/official_anki_import_attempt_dao.dart';
import 'package:turna/application/anki_official/storage/official_anki_source_dao.dart';

import '../../helpers/in_memory_course_db.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  ensureSqliteLibForTestHost();

  final pkg = File(
    p.join(
      'test',
      'fixtures',
      'anki_official',
      'packages',
      '01-basic-unicode.apkg',
    ),
  );

  test('catalog v12 has attempt phase and staging_path columns', () {
    final db = OfficialAnkiDatabase.memory();
    addTearDown(db.close);
    final version =
        db.handle.select('PRAGMA user_version').first['user_version'] as int;
    expect(version, kOfficialAnkiCatalogSchemaVersion);
    expect(version, 14);
    final columns = db.handle
        .select("SELECT name FROM pragma_table_info('anki_import_attempts')")
        .map((row) => row['name'] as String)
        .toSet();
    expect(columns, containsAll(['phase', 'staging_path']));
  });

  test('startStaging writes staging collection only; cancel deletes it', () async {
    final root = Directory.systemTemp.createTempSync('turna-p1-stage-');
    addTearDown(() {
      try {
        root.deleteSync(recursive: true);
      } catch (_) {}
    });
    final liveRoot = Directory(p.join(root.path, 'official_anki', 'default'))
      ..createSync(recursive: true);
    File(p.join(liveRoot.path, 'collection.anki2')).writeAsBytesSync([1, 2, 3]);
    final catalog = OfficialAnkiDatabase.file(
      p.join(liveRoot.path, 'official_catalog.sqlite'),
    );
    addTearDown(catalog.close);
    final paths = OfficialAnkiPaths(
      profileId: 'profile-p1-01',
      profileRoot: liveRoot,
    );
    final live = FakeOfficialAnkiEngine();
    final staging = FakeOfficialAnkiEngine();
    staging.seedPackage(packagePath: pkg.path, notes: 1, cards: 1);
    OfficialAnkiCompositionRoot.debugEngineOverride = live;
    OfficialAnkiCompositionRoot.debugStagingEngineOverride = staging;
    OfficialAnkiCompositionRoot.stagingDiscardRequested = false;
    addTearDown(() {
      OfficialAnkiCompositionRoot.debugEngineOverride = null;
      OfficialAnkiCompositionRoot.debugStagingEngineOverride = null;
      OfficialAnkiCompositionRoot.stagingEngine = null;
      OfficialAnkiCompositionRoot.stagingSession = null;
      OfficialAnkiCompositionRoot.stagingDiscardRequested = false;
    });

    final sources = OfficialAnkiSourceDao(catalog);
    final attempts = OfficialAnkiImportAttemptDao(catalog);
    final saga = OfficialAnkiImportSaga(
      sources: sources,
      attempts: attempts,
      paths: paths,
    );
    final generationBefore = live.collectionGeneration;
    final imported = await saga.startStaging(
      packagePath: pkg.path,
      displayName: 'unicode',
    );
    expect(imported.state.name, 'previewReady');
    expect(live.collectionGeneration, generationBefore);
    expect(staging.collectionGeneration, greaterThan(generationBefore));
    expect(live.importCount, 0);
    expect(staging.importCount, 1);
    final attempt = attempts.find(imported.attemptId)!;
    expect(attempt.phase, OfficialAnkiAttemptPhase.previewReady);
    expect(attempt.stagingPath, isNotNull);
    expect(Directory(attempt.stagingPath!).existsSync(), isTrue);

    await saga.cancelActive();
    expect(live.collectionGeneration, generationBefore);
    expect(sources.listSources(paths.profileId), isEmpty);
    final leftover = Directory(p.join(liveRoot.parent.path, 'staging'));
    expect(
      !leftover.existsSync() || leftover.listSync(followLinks: false).isEmpty,
      isTrue,
    );
  });

  test('deleteDirectory retries until the folder is gone', () async {
    final dir = Directory.systemTemp.createTempSync('turna-p1-del-');
    File(p.join(dir.path, 'x.txt')).writeAsStringSync('x');
    await OfficialAnkiStagingManager.deleteDirectory(dir);
    expect(dir.existsSync(), isFalse);
  });
}
