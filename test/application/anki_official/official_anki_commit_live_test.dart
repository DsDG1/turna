import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:turna/application/anki_import/recognition/recognize/recognizer.dart';
import 'package:turna/application/anki_official/contract/official_anki_dto.dart';
import 'package:turna/application/anki_official/engine/official_anki_engine_fake.dart';
import 'package:turna/application/anki_official/import/official_anki_import_saga.dart';
import 'package:turna/application/anki_official/lifecycle/official_anki_lifecycle_models.dart';
import 'package:turna/application/anki_official/official_anki_composition.dart';
import 'package:turna/application/anki_official/official_anki_feature_flags.dart';
import 'package:turna/application/anki_official/official_anki_paths.dart';
import 'package:turna/application/anki_official/projection/official_anki_mapping_suggestion.dart';
import 'package:turna/application/anki_official/projection/official_anki_projection_service.dart';
import 'package:turna/application/anki_official/storage/official_anki_database.dart';
import 'package:turna/application/anki_official/storage/official_anki_import_attempt_dao.dart';
import 'package:turna/application/anki_official/storage/official_anki_source_dao.dart';
import 'package:turna/data/course_database.dart';

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

  test('commitLive writes live collection once and promotes mappings', () async {
    final root = Directory.systemTemp.createTempSync('turna-p3-commit-');
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
    final course = CourseDatabase(NativeDatabase.memory());
    addTearDown(course.close);
    final paths = OfficialAnkiPaths(
      profileId: 'profile-p3-01',
      profileRoot: liveRoot,
    );
    final live = FakeOfficialAnkiEngine();
    final staging = FakeOfficialAnkiEngine();
    live.seedPackage(packagePath: pkg.path, notes: 2, cards: 2);
    live.collectionGeneration = 1;
    live.importCount = 0;
    staging.seedPackage(packagePath: pkg.path, notes: 2, cards: 2);
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
      liveEngine: live,
    );
    final started = await saga.startStaging(
      packagePath: pkg.path,
      displayName: 'unicode',
    );
    expect(live.collectionGeneration, 1);
    expect(live.importCount, 0);

    const schema = OfficialAnkiProjectionSchema(
      notetypeId: 1,
      name: 'Basic',
      kind: 'normal',
      fieldNames: ['Front', 'Back'],
      templateNames: ['Card 1'],
      schemaFingerprint: 'fake-basic',
    );
    final service = OfficialAnkiCourseProjectionService(
      engine: live,
      catalog: catalog,
      course: course,
      sourceId: started.sourceId,
      profileId: paths.profileId,
      flags: const OfficialAnkiFeatureFlags(
        engine: true,
        import: true,
        catalogReady: true,
        runtimeCapable: true,
        projection: true,
      ),
    );
    final committed = await saga.commitLive(
      sourceId: started.sourceId,
      packagePath: pkg.path,
      projection: service,
      suggestions: {
        1: officialAnkiSuggestMapping(schema, const CardRecognizer()),
      },
      confirmedNotetypes: {1},
    );
    expect(committed.alreadyImported, isFalse);
    expect(live.importCount, 1);
    expect(live.collectionGeneration, 2);

    await saga.finishCommit(
      sourceId: started.sourceId,
      attemptId: started.attemptId,
      published: true,
    );
    final attempt = attempts.find(started.attemptId)!;
    expect(attempt.phase, OfficialAnkiAttemptPhase.completed);
    expect(
      !Directory(attempt.stagingPath ?? '').existsSync(),
      isTrue,
    );
    final mapping = catalog.handle.select(
      'SELECT user_confirmed FROM anki_projection_mappings '
      'WHERE profile_id = ? AND notetype_id = 1',
      [paths.profileId],
    );
    expect(mapping, isNotEmpty);
    expect(mapping.first['user_confirmed'], 1);
    expect(sources.findById(started.sourceId)?.state, 'active');
  });
}
