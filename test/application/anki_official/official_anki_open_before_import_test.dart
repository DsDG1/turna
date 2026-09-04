import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:turna/application/anki_official/contract/official_anki_dto.dart';
import 'package:turna/application/anki_official/contract/official_anki_errors.dart';
import 'package:turna/application/anki_official/engine/official_anki_engine_fake.dart';
import 'package:turna/application/anki_official/import/official_anki_import_saga.dart';
import 'package:turna/application/anki_official/official_anki_composition.dart';
import 'package:turna/application/anki_official/official_anki_paths.dart';
import 'package:turna/application/anki_official/storage/official_anki_database.dart';
import 'package:turna/application/anki_official/storage/official_anki_import_attempt_dao.dart';
import 'package:turna/application/anki_official/storage/official_anki_source_dao.dart';
import 'package:turna/application/anki_official/v2/official_anki_v2_import_service.dart';
import 'package:turna/data/course_database.dart';

import '../../helpers/in_memory_course_db.dart';

/// Strict-order fake (step1 task B): mirrors the Rust engine state machine
/// contract — `importPackage` on a Created (never opened) engine must fail
/// with invalid_state. Records the call sequence for order assertions.
class StrictOrderEngine extends FakeOfficialAnkiEngine {
  final calls = <String>[];

  @override
  Future<void> openProfile(OfficialAnkiPaths paths) async {
    calls.add('openProfile');
    await super.openProfile(paths);
  }

  @override
  Future<void> closeCollection() async {
    calls.add('closeCollection');
    await super.closeCollection();
  }

  @override
  Future<OfficialAnkiImportLog> importPackage({
    required String packagePath,
    bool withScheduling = true,
    bool withDeckConfigs = true,
  }) async {
    calls.add('importPackage');
    if (openProfileId == null) {
      throw const OfficialAnkiException(
        code: OfficialAnkiErrorCode.invalidState,
        messageKey: 'official_anki.invalid_state',
        debugDetails: 'import_before_open',
      );
    }
    return super.importPackage(
      packagePath: packagePath,
      withScheduling: withScheduling,
      withDeckConfigs: withDeckConfigs,
    );
  }
}

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

  ({
    OfficialAnkiDatabase catalog,
    OfficialAnkiSourceDao sources,
    OfficialAnkiImportAttemptDao attempts,
    OfficialAnkiPaths paths,
    StrictOrderEngine live,
    StrictOrderEngine staging,
    OfficialAnkiImportSaga saga,
    void Function() dispose,
  }) harness() {
    final root = Directory.systemTemp.createTempSync('turna-step1-order-');
    final liveRoot = Directory(p.join(root.path, 'official_anki', 'default'))
      ..createSync(recursive: true);
    File(p.join(liveRoot.path, 'collection.anki2')).writeAsBytesSync([1, 2, 3]);
    final catalog = OfficialAnkiDatabase.file(
      p.join(liveRoot.path, 'official_catalog.sqlite'),
    );
    final paths = OfficialAnkiPaths(
      profileId: 'profile-step1-order',
      profileRoot: liveRoot,
    );
    final live = StrictOrderEngine();
    final staging = StrictOrderEngine();
    live.seedPackage(packagePath: pkg.path, notes: 1, cards: 1);
    staging.seedPackage(packagePath: pkg.path, notes: 1, cards: 1);
    OfficialAnkiCompositionRoot.debugEngineOverride = live;
    OfficialAnkiCompositionRoot.debugStagingEngineOverride = staging;
    OfficialAnkiCompositionRoot.stagingDiscardRequested = false;
    final sources = OfficialAnkiSourceDao(catalog);
    final attempts = OfficialAnkiImportAttemptDao(catalog);
    final saga = OfficialAnkiImportSaga(
      sources: sources,
      attempts: attempts,
      paths: paths,
      liveEngine: live,
    );
    return (
      catalog: catalog,
      sources: sources,
      attempts: attempts,
      paths: paths,
      live: live,
      staging: staging,
      saga: saga,
      dispose: () {
        OfficialAnkiCompositionRoot.debugEngineOverride = null;
        OfficialAnkiCompositionRoot.debugStagingEngineOverride = null;
        OfficialAnkiCompositionRoot.stagingEngine = null;
        OfficialAnkiCompositionRoot.stagingSession = null;
        OfficialAnkiCompositionRoot.stagingDiscardRequested = false;
        catalog.close();
        try {
          root.deleteSync(recursive: true);
        } catch (_) {}
      },
    );
  }

  test('startStaging opens the staging engine before importing', () async {
    final h = harness();
    addTearDown(h.dispose);

    final imported = await h.saga.startStaging(
      packagePath: pkg.path,
      displayName: 'unicode',
    );
    expect(imported.state.name, 'previewReady');
    expect(h.staging.importCount, 1);
    // acquire() must have opened the engine before the saga imported into it.
    expect(h.staging.calls.first, 'openProfile');
    expect(h.staging.calls, contains('importPackage'));
    expect(
      h.staging.calls.indexOf('openProfile') <
          h.staging.calls.indexOf('importPackage'),
      isTrue,
    );
    // The staging engine is a separate collection; live stays untouched.
    expect(h.live.importCount, 0);
    expect(h.live.calls, isEmpty);
  });

  test('v2 commit opens the live engine before importing', () async {
    final h = harness();
    addTearDown(h.dispose);
    final course = CourseDatabase(NativeDatabase.memory());
    addTearDown(course.close);

    await h.saga.startStaging(packagePath: pkg.path, displayName: 'unicode');
    // Live engine fresh: no home due-sync, no review gate ran. The v2
    // commit chain must open it itself before importPackage, or the strict
    // engine fails with import_before_open (Step 1 task B contract).
    final committed = await OfficialAnkiV2ImportService(
      catalog: h.catalog,
      paths: h.paths,
      course: course,
      engine: h.live,
    ).commit(
      sourceId: h.sources.listSources(h.paths.profileId).single.sourceId,
      packagePath: pkg.path,
      displayName: 'unicode',
    );
    expect(committed.sourceId, isNotEmpty);
    expect(h.live.importCount, 1);
    expect(
      h.live.calls.indexOf('openProfile') <
          h.live.calls.indexOf('importPackage'),
      isTrue,
    );
  });
}
