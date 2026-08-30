// Doc 42 §10.1 P0 failing gates (S-a, S-b). Expected red until P1+ staging-first
// import. At least this file uses a real on-disk catalog SQLite.

import 'dart:async';
import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:streaming_shared_preferences/streaming_shared_preferences.dart';
import 'package:turna/application/anki_import/anki_import_controller.dart';
import 'package:turna/application/anki_import/anki_import_dependencies.dart';
import 'package:turna/application/anki_import/anki_import_wizard_state.dart';
import 'package:turna/application/anki_official/contract/official_anki_dto.dart';
import 'package:turna/application/anki_official/engine/official_anki_engine.dart';
import 'package:turna/application/anki_official/engine/official_anki_engine_fake.dart';
import 'package:turna/application/anki_official/engine/official_anki_native_availability.dart';
import 'package:turna/application/anki_official/import/anki_import_facade.dart';
import 'package:turna/application/anki_official/import/official_anki_import_state.dart';
import 'package:turna/application/anki_official/import/official_anki_official_first_service.dart';
import 'package:turna/application/anki_official/migration/official_anki_engine_kind.dart';
import 'package:turna/application/anki_official/official_anki_composition.dart';
import 'package:turna/application/anki_official/official_anki_feature_flags.dart';
import 'package:turna/application/anki_official/official_anki_paths.dart';
import 'package:turna/application/anki_official/projection/official_anki_projection_store.dart';
import 'package:turna/application/anki_official/storage/official_anki_database.dart';
import 'package:turna/application/anki_official/storage/official_anki_source_dao.dart';
import 'package:turna/application/course_provider.dart';
import 'package:turna/application/lesson_link_store.dart';
import 'package:turna/application/srs_provider.dart';
import 'package:turna/courses/course_loader.dart';
import 'package:turna/data/anki_import_dao.dart';
import 'package:turna/data/anki_note_dao.dart';
import 'package:turna/data/anki_unification_dao.dart';
import 'package:turna/data/course_database.dart';
import 'package:turna/data/course_repository.dart';
import 'package:turna/data/review_history_dao.dart';
import 'package:turna/data/srs_state_dao.dart';
import 'package:turna/di/injection.dart';
import 'package:turna/domain/repositories/i_course_repository.dart';
import 'package:turna/service/locator.dart';

import '../../helpers/in_memory_course_db.dart';

const _flags = OfficialAnkiFeatureFlags(
  engine: true,
  import: true,
  catalogReady: true,
  runtimeCapable: true,
  platformReady: true,
  projection: true,
  courseEntry: true,
  officialFirstImport: true,
);

class _DelayedImportEngine extends FakeOfficialAnkiEngine {
  final enteredImport = Completer<void>();
  final releaseImport = Completer<void>();

  @override
  Future<OfficialAnkiImportLog> importPackage({
    required String packagePath,
    bool withScheduling = true,
    bool withDeckConfigs = true,
  }) async {
    if (!enteredImport.isCompleted) enteredImport.complete();
    await releaseImport.future;
    return super.importPackage(
      packagePath: packagePath,
      withScheduling: withScheduling,
      withDeckConfigs: withDeckConfigs,
    );
  }
}

bool _stagingLeftover(OfficialAnkiPaths paths) {
  bool occupied(Directory dir) =>
      dir.existsSync() && dir.listSync(followLinks: false).isNotEmpty;
  final underProfile = Directory(p.join(paths.profileRoot.path, 'staging'));
  final sibling = Directory(p.join(paths.profileRoot.parent.path, 'staging'));
  return occupied(underProfile) || occupied(sibling);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  ensurePathProviderMockForTest();
  ensureSqliteLibForTestHost();

  late CourseDatabase course;
  late AppPrefs appPrefs;
  late CourseProvider courseProvider;
  late OfficialAnkiFeatureFlags savedFlags;
  late OfficialAnkiImporter? savedSession;
  late OfficialAnkiDatabase? savedCatalog;
  late OfficialAnkiPaths? savedPaths;
  late OfficialAnkiEngine? savedEngine;
  late OfficialAnkiEngine? savedStagingEngine;
  late Directory tmp;
  late File pkg;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    final preferences = await StreamingSharedPreferences.instance;
    appPrefs = AppPrefs(preferences);
    tmp = Directory.systemTemp.createTempSync('turna-p0-staging-');
    pkg = File(
      p.join(
        'test',
        'fixtures',
        'anki_official',
        'packages',
        '01-basic-unicode.apkg',
      ),
    );

    course = CourseDatabase(NativeDatabase.memory());
    final getIt = GetIt.instance;
    await getIt.reset();
    getIt.registerSingleton<CourseDatabase>(course);
    getIt.registerSingleton<ICourseRepository>(CourseRepository(course));
    getIt.registerSingleton<ReviewHistoryDao>(ReviewHistoryDao(course));
    getIt.registerSingleton<AnkiNoteDao>(AnkiNoteDao(course));
    getIt.registerSingleton<AnkiImportDao>(AnkiImportDao(course));
    getIt.registerSingleton<AnkiUnificationDao>(AnkiUnificationDao(course));
    courseProvider = CourseProvider(appPrefs);
    getIt.registerSingleton<CourseProvider>(courseProvider);
    getIt.registerSingleton<SrsProvider>(
      SrsProvider(appPrefs, LessonLinkStore(appPrefs), SrsStateDao(course)),
    );
    CourseLoader.overrideDatabase(() => course);

    savedFlags = OfficialAnkiFeatureFlags.current;
    savedSession = OfficialAnkiCompositionRoot.session;
    savedCatalog = OfficialAnkiCompositionRoot.readOnlyCatalog;
    savedPaths = OfficialAnkiCompositionRoot.locatorPaths;
    savedEngine = OfficialAnkiCompositionRoot.debugEngineOverride;
    savedStagingEngine = OfficialAnkiCompositionRoot.debugStagingEngineOverride;
    OfficialAnkiCapabilityMatrix.overrideHostPlatformForTests = 'android';
    OfficialAnkiNativeAvailability.debugOverride = true;
    OfficialAnkiFeatureFlags.current = _flags;
  });

  tearDown(() async {
    OfficialAnkiCapabilityMatrix.overrideHostPlatformForTests = null;
    OfficialAnkiNativeAvailability.debugOverride = null;
    OfficialAnkiFeatureFlags.current = savedFlags;
    OfficialAnkiCompositionRoot.session = savedSession;
    OfficialAnkiCompositionRoot.debugEngineOverride = savedEngine;
    OfficialAnkiCompositionRoot.debugStagingEngineOverride = savedStagingEngine;
    OfficialAnkiCompositionRoot.stagingDiscardRequested = false;
    OfficialAnkiCompositionRoot.stagingEngine = null;
    OfficialAnkiCompositionRoot.stagingSession = null;
    final opened = OfficialAnkiCompositionRoot.readOnlyCatalog;
    if (opened != null && !identical(opened, savedCatalog)) {
      opened.close();
    }
    OfficialAnkiCompositionRoot.readOnlyCatalog = savedCatalog;
    OfficialAnkiCompositionRoot.locatorPaths = savedPaths;
    CourseLoader.clearDatabaseOverride();
    await course.close();
    await GetIt.instance.reset();
    try {
      tmp.deleteSync(recursive: true);
    } catch (_) {}
  });

  ({
    OfficialAnkiDatabase catalog,
    OfficialAnkiSourceDao sources,
    OfficialAnkiPaths paths,
    AnkiImportController controller,
  }) wire({
    required FakeOfficialAnkiEngine live,
    required FakeOfficialAnkiEngine staging,
  }) {
    final profileRoot = Directory(p.join(tmp.path, 'official_anki', 'default'));
    profileRoot.createSync(recursive: true);
    File(p.join(profileRoot.path, 'collection.anki2')).writeAsBytesSync([1, 2, 3, 4]);
    final catalogPath = p.join(profileRoot.path, 'official_catalog.sqlite');
    final catalog = OfficialAnkiDatabase.file(catalogPath);
    addTearDown(catalog.close);
    final paths = OfficialAnkiPaths(
      profileId: 'profile-p0-01',
      profileRoot: profileRoot,
    );
    staging.seedPackage(packagePath: pkg.path, notes: 1, cards: 1);
    OfficialAnkiCompositionRoot.debugEngineOverride = live;
    OfficialAnkiCompositionRoot.debugStagingEngineOverride = staging;
    OfficialAnkiCompositionRoot.readOnlyCatalog = catalog;
    OfficialAnkiCompositionRoot.locatorPaths = paths;
    OfficialAnkiCompositionRoot.stagingDiscardRequested = false;
    final controller = AnkiImportController(
      deps: AnkiImportDependencies(
        planFor: ({required flags, required filePath}) =>
            AnkiImportFacade.planFor(flags, filePath: filePath),
        pickFilePath: ({required allowedExtensions, required dialogTitle}) async =>
            pkg.path,
        officialFirst: const OfficialAnkiOfficialFirstService(),
        courseDatabase: course,
        readOfficialProjectionSummary: (sourceId) async =>
            OfficialProjectionSummary(
          sourceId: sourceId,
          sectionIds: const {},
          itemCount: 0,
        ),
        courseProvider: courseProvider,
      ),
    );
    addTearDown(controller.dispose);
    return (
      catalog: catalog,
      sources: OfficialAnkiSourceDao(catalog),
      paths: paths,
      controller: controller,
    );
  }

  test(
    'P0 S-a: cancel during staging_importing leaves live collection and catalog clean',
    () async {
      final live = FakeOfficialAnkiEngine();
      final staging = _DelayedImportEngine();
      final h = wire(live: live, staging: staging);
      final generationBefore = live.collectionGeneration;

      final proceed = h.controller.proceedWithPath(pkg.path);
      await staging.enteredImport.future.timeout(const Duration(seconds: 5));
      expect(h.controller.state, isA<AnkiImportParsing>());

      h.controller.cancel();
      if (!staging.releaseImport.isCompleted) staging.releaseImport.complete();
      await proceed.timeout(const Duration(seconds: 5));
      await Future<void>.delayed(const Duration(milliseconds: 300));

      expect(
        live.collectionGeneration,
        generationBefore,
        reason: 'live Collection generation must not change before commit',
      );
      expect(
        h.sources.listSources(h.paths.profileId),
        isEmpty,
        reason: 'catalog must have no source row for a cancelled staging import',
      );
      expect(
        _stagingLeftover(h.paths),
        isFalse,
        reason: 'staging directory must be deleted on cancel',
      );
    },
  );

  test(
    'P0 S-b: discard from preview finishes in bound time with a staging receipt',
    () async {
      final live = FakeOfficialAnkiEngine();
      final staging = FakeOfficialAnkiEngine();
      final h = wire(live: live, staging: staging);
      final generationBefore = live.collectionGeneration;
      final silent = <Object>[];
      final previous = FlutterError.onError;
      FlutterError.onError = (details) {
        silent.add(details.exception);
        previous?.call(details);
      };
      addTearDown(() => FlutterError.onError = previous);

      await h.controller.proceedWithPath(pkg.path);
      expect(h.controller.state, isA<AnkiImportPreviewing>());

      await h.controller.reset().timeout(
            const Duration(seconds: 2),
            onTimeout: () => fail('preview discard exceeded 2s (S-b hang)'),
          );

      expect(silent, isEmpty, reason: 'discard must not swallow unawaited errors');
      expect(
        live.collectionGeneration,
        generationBefore,
        reason: 'preview discard must not have written the live Collection',
      );
      expect(h.sources.listSources(h.paths.profileId), isEmpty);
      expect(_stagingLeftover(h.paths), isFalse);
    },
  );
}
