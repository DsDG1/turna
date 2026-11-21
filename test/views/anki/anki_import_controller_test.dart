// Wave 4 controller tests (maintainability plan §6.2-4), official-flow
// remainder after doc 35 L1 deleted the Legacy parser flow: pick-time plan
// stays frozen, previews are expressed by sealed variants, and an
// official-first failure produces zero Legacy writes.

import 'dart:async';
import 'dart:io';

import 'package:drift/native.dart';
import 'package:path/path.dart' as p;
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:streaming_shared_preferences/streaming_shared_preferences.dart';
import 'package:turna/application/anki_import/anki_import_controller.dart';
import 'package:turna/application/anki_import/anki_import_dependencies.dart';
import 'package:turna/application/anki_import/anki_import_wizard_state.dart';
import 'package:turna/application/anki_official/anki_deck_manager.dart';
import 'package:turna/application/anki_official/contract/official_anki_dto.dart';
import 'package:turna/application/anki_official/contract/official_anki_errors.dart';
import 'package:turna/application/anki_official/engine/official_anki_engine_fake.dart';
import 'package:turna/application/anki_official/engine/official_anki_native_availability.dart';
import 'package:turna/application/anki_official/import/official_anki_source_hasher.dart';
import 'package:turna/application/anki_official/lifecycle/official_anki_lifecycle_models.dart';
import 'package:turna/application/anki_official/lifecycle/official_anki_maintenance.dart';
import 'package:turna/application/anki_official/official_anki_paths.dart';
import 'package:turna/application/anki_official/import/anki_import_execution_plan.dart';
import 'package:turna/application/anki_official/import/anki_import_facade.dart';
import 'package:turna/application/anki_official/import/official_anki_import_state.dart';
import 'package:turna/application/anki_official/import/official_anki_official_first_service.dart';
import 'package:turna/application/anki_official/migration/official_anki_engine_kind.dart';
import 'package:turna/application/anki_official/official_anki_composition.dart';
import 'package:turna/application/anki_official/official_anki_feature_flags.dart';
import 'package:turna/application/anki_official/storage/official_anki_database.dart';
import 'package:turna/application/anki_official/storage/official_anki_import_attempt_dao.dart';
import 'package:turna/application/anki_official/storage/official_anki_source_dao.dart';
import 'package:turna/l10n/app_strings.dart';
import 'package:turna/application/course_provider.dart';
import 'package:turna/application/lesson_link_store.dart';
import 'package:turna/application/srs_provider.dart';
import 'package:turna/courses/course_loader.dart';
import 'package:turna/data/anki_unification_dao.dart';
import 'package:turna/data/course_database.dart';
import 'package:turna/data/course_repository.dart';
import 'package:turna/data/official_anki_v2_view_store.dart';
import 'package:turna/data/review_history_dao.dart';
import 'package:turna/data/srs_state_dao.dart';
import 'package:turna/domain/repositories/i_course_repository.dart';
import 'package:turna/di/injection.dart';
import 'package:turna/service/locator.dart';

import '../../helpers/in_memory_course_db.dart';
import 'package:turna/domain/repositories/i_anki_unification_store.dart';
import 'package:turna/domain/repositories/i_official_anki_v2_view_store.dart';
import 'package:turna/domain/repositories/i_review_history_store.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  ensurePathProviderMockForTest();
  ensureSqliteLibForTestHost();

  late CourseDatabase db;
  late AppPrefs appPrefs;
  late CourseProvider courseProvider;
  late SrsProvider srsProvider;
  late OfficialAnkiFeatureFlags savedFlags;
  late OfficialAnkiImporter? savedSession;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    final preferences = await StreamingSharedPreferences.instance;
    appPrefs = AppPrefs(preferences);

    db = CourseDatabase(NativeDatabase.memory());
    final getIt = GetIt.instance;
    await getIt.reset();
    getIt.registerSingleton<CourseDatabase>(db);
    getIt.registerSingleton<ICourseRepository>(CourseRepository(db));
    getIt.registerSingleton<IReviewHistoryStore>(ReviewHistoryDao(db));
    getIt.registerSingleton<IOfficialAnkiV2ViewStore>(
      OfficialAnkiV2ViewStore(db),
    );
    getIt.registerSingleton<IAnkiUnificationStore>(AnkiUnificationDao(db));

    courseProvider = CourseProvider(appPrefs);
    final linkStore = LessonLinkStore(appPrefs);
    srsProvider = SrsProvider(appPrefs, linkStore, SrsStateDao(db));
    getIt.registerSingleton<CourseProvider>(courseProvider);
    getIt.registerSingleton<SrsProvider>(srsProvider);
    CourseLoader.overrideDatabase(() => db);

    savedFlags = OfficialAnkiFeatureFlags.current;
    savedSession = OfficialAnkiCompositionRoot.session;
    OfficialAnkiCapabilityMatrix.overrideHostPlatformForTests = 'android';
    OfficialAnkiNativeAvailability.debugOverride = true;
  });

  tearDown(() async {
    OfficialAnkiCapabilityMatrix.overrideHostPlatformForTests = null;
    OfficialAnkiNativeAvailability.debugOverride = null;
    OfficialAnkiFeatureFlags.current = savedFlags;
    OfficialAnkiCompositionRoot.session = savedSession;
    CourseLoader.clearDatabaseOverride();
    await db.close();
    await GetIt.instance.reset();
  });

  AnkiImportController controllerWith({String? pickedPath}) {
    return AnkiImportController(
      deps: AnkiImportDependencies(
        planFor: ({required flags, required filePath}) =>
            AnkiImportFacade.planFor(
          flags,
          filePath: filePath,
        ),
        pickFilePath: (
                {required allowedExtensions, required dialogTitle}) async =>
            pickedPath,
        officialFirst: const OfficialAnkiOfficialFirstService(),
        v2ViewStore: OfficialAnkiV2ViewStore(db),
        unificationStore: AnkiUnificationDao(db),
        courseProvider: courseProvider,
      ),
    );
  }

  test('pick-time plan stays frozen for the whole flow', () async {
    OfficialAnkiFeatureFlags.current = const OfficialAnkiFeatureFlags(
      engine: false,
      import: false,
      catalogReady: false,
      runtimeCapable: false,
      platformReady: false,
    );
    final controller = controllerWith();
    addTearDown(controller.dispose);

    await controller.proceedWithPath('/tmp/a.apkg');

    // Everything off on the host → fail closed with zero writes.
    expect(controller.state, isA<AnkiImportFailed>());
    expect((controller.state as AnkiImportFailed).returnState,
        isA<AnkiImportSelecting>());
    expect(await OfficialAnkiV2ViewStore(db).isAvailable, isFalse);
  });

  test('official-first failure leaves zero Legacy writes', () async {
    OfficialAnkiFeatureFlags.current = const OfficialAnkiFeatureFlags(
      engine: true,
      import: true,
      catalogReady: true,
      runtimeCapable: true,
      platformReady: true,
      projection: true,
      courseEntry: true,
      officialFirstImport: true,
    );

    final controller = controllerWith();
    addTearDown(controller.dispose);

    await controller.proceedWithPath('/tmp/o.apkg');

    // Composition is not wired in this unit test, so the official-first
    // flow fails closed before any staging work; the invariant under test
    // is that the failure leaves zero Legacy writes.
    expect(controller.state, isA<AnkiImportFailed>(),
        reason: 'the wizard surfaces the failure');
    expect((controller.state as AnkiImportFailed).returnState,
        isA<AnkiImportSelecting>());
    expect(await OfficialAnkiV2ViewStore(db).isAvailable, isFalse,
        reason: 'no v2 view rows');
    expect(
      srsProvider.state.keys.where((id) => id.startsWith('anki-')),
      isEmpty,
      reason: 'no Turna SRS rows',
    );
    final sections = await getIt<ICourseRepository>().sectionShells();
    expect(
      sections.where((s) => s.id.startsWith('anki-')),
      isEmpty,
      reason: 'no course-tree sections',
    );
  });

  test('unfinished import blocks a new pick with system error', () async {
    final catalog = OfficialAnkiDatabase.memory();
    addTearDown(catalog.close);
    OfficialAnkiSourceDao(catalog).upsertSource(
      sourceId: 'src-pending',
      profileId: 'profile-default-01',
      sourceHash: 'hash-pending',
      sourceSize: 1,
      displayName: 'Pending',
      state: 'preview_ready',
      backendCommit: 'pending',
      nowMillis: 1,
      activeAttemptId: 'att-pending',
    );
    OfficialAnkiImportAttemptDao(catalog).insert(
      attemptId: 'att-pending',
      sourceId: 'src-pending',
      requestId: 'req',
      state: 'preview_ready',
      nowMillis: 1,
      phase: 'preview_ready',
    );
    final savedCatalog = OfficialAnkiCompositionRoot.readOnlyCatalog;
    OfficialAnkiCompositionRoot.readOnlyCatalog = catalog;
    addTearDown(() {
      OfficialAnkiCompositionRoot.readOnlyCatalog = savedCatalog;
    });

    final controller = controllerWith();
    addTearDown(controller.dispose);
    await controller.proceedWithPath('/tmp/new.apkg');

    expect(controller.state, isA<AnkiImportFailed>());
    final failed = controller.state as AnkiImportFailed;
    expect(failed.message, contains(AppStrings.ankiImportSystemError));
    expect(
      failed.message,
      contains(AppStrings.ankiPendingMustDiscardBeforeNew),
    );
    expect(failed.returnState, isA<AnkiImportSelecting>());
  });

  test('picking a colpkg file routes to ankiColpkgUnsupported guidance',
      () async {
    final controller = controllerWith(pickedPath: '/tmp/collection.colpkg');
    addTearDown(controller.dispose);

    await controller.pickFile();

    expect(controller.state, isA<AnkiImportFailed>());
    final failed = controller.state as AnkiImportFailed;
    expect(failed.message, equals(AppStrings.ankiColpkgUnsupported));
    expect(failed.returnState, isA<AnkiImportSelecting>());
  });

  test('same sha256 active source short-circuits before staging', () async {
    OfficialAnkiFeatureFlags.current = const OfficialAnkiFeatureFlags(
      engine: true,
      import: true,
      catalogReady: true,
      runtimeCapable: true,
      platformReady: true,
      projection: true,
      courseEntry: true,
      officialFirstImport: true,
    );
    final root = Directory.systemTemp.createTempSync('turna-dup-');
    addTearDown(() => root.deleteSync(recursive: true));
    final package = File(p.join(root.path, 'again.apkg'))
      ..writeAsBytesSync(const [9, 8, 7]);
    final digest =
        await const OfficialAnkiSourceHasher().hashFile(package.path);
    final catalog = OfficialAnkiDatabase.memory();
    addTearDown(catalog.close);
    OfficialAnkiSourceDao(catalog).upsertSource(
      sourceId: 'src-live',
      profileId: 'profile-default-01',
      sourceHash: digest.sha256,
      sourceSize: digest.bytes,
      displayName: 'Already',
      state: 'active',
      backendCommit: 'ok',
      nowMillis: 1,
    );
    final savedCatalog = OfficialAnkiCompositionRoot.readOnlyCatalog;
    final savedPaths = OfficialAnkiCompositionRoot.locatorPaths;
    OfficialAnkiCompositionRoot.readOnlyCatalog = catalog;
    OfficialAnkiCompositionRoot.locatorPaths = OfficialAnkiPaths(
      profileId: 'profile-default-01',
      profileRoot: Directory(p.join(root.path, 'live'))..createSync(),
    );
    addTearDown(() {
      OfficialAnkiCompositionRoot.readOnlyCatalog = savedCatalog;
      OfficialAnkiCompositionRoot.locatorPaths = savedPaths;
    });

    final controller = controllerWith();
    addTearDown(controller.dispose);
    await controller.proceedWithPath(package.path);

    expect(controller.state, isA<AnkiImportAlreadyImported>());
    final already = controller.state as AnkiImportAlreadyImported;
    expect(already.sourceId, 'src-live');
    expect(already.displayName, 'Already');
  });

  test('preview_ready staging resumes without a second import', () async {
    final root = Directory.systemTemp.createTempSync('turna-resume-');
    addTearDown(() => root.deleteSync(recursive: true));
    final staging = Directory(p.join(root.path, 'staging'))..createSync();
    File(p.join(staging.path, 'collection.anki2')).writeAsBytesSync([1, 2]);
    final catalog = OfficialAnkiDatabase.memory();
    addTearDown(catalog.close);
    OfficialAnkiSourceDao(catalog).upsertSource(
      sourceId: 'src-pending',
      profileId: 'profile-default-01',
      sourceHash: 'hash-pending',
      sourceSize: 1,
      displayName: 'Pending',
      state: 'preview_ready',
      backendCommit: 'pending',
      nowMillis: 1,
      activeAttemptId: 'att-pending',
    );
    OfficialAnkiImportAttemptDao(catalog).insert(
      attemptId: 'att-pending',
      sourceId: 'src-pending',
      requestId: 'req',
      state: 'preview_ready',
      nowMillis: 1,
      phase: 'preview_ready',
    );
    OfficialAnkiImportAttemptDao(catalog).setPhase(
      attemptId: 'att-pending',
      phase: OfficialAnkiAttemptPhase.previewReady,
      stagingPath: staging.path,
      nowMillis: 2,
    );
    final engine = FakeOfficialAnkiEngine()
      ..summary = const OfficialAnkiNoteDeckSummary(
        noteCount: 3,
        cardCount: 4,
        rows: [
          OfficialAnkiDeckNotetypeCount(deckId: 1, notetypeId: 1, cards: 4),
        ],
      );
    final savedCatalog = OfficialAnkiCompositionRoot.readOnlyCatalog;
    final savedPaths = OfficialAnkiCompositionRoot.locatorPaths;
    final savedStaging = OfficialAnkiCompositionRoot.debugStagingEngineOverride;
    OfficialAnkiCompositionRoot.readOnlyCatalog = catalog;
    OfficialAnkiCompositionRoot.locatorPaths = OfficialAnkiPaths(
      profileId: 'profile-default-01',
      profileRoot: Directory(p.join(root.path, 'live'))..createSync(),
    );
    OfficialAnkiCompositionRoot.debugStagingEngineOverride = engine;
    addTearDown(() {
      OfficialAnkiCompositionRoot.readOnlyCatalog = savedCatalog;
      OfficialAnkiCompositionRoot.locatorPaths = savedPaths;
      OfficialAnkiCompositionRoot.debugStagingEngineOverride = savedStaging;
      OfficialAnkiCompositionRoot.stagingEngine = null;
    });

    final controller = controllerWith();
    addTearDown(controller.dispose);
    await controller.continuePending(const OfficialAnkiPendingImport(
      sourceId: 'src-pending',
      attemptId: 'att-pending',
      displayName: 'Pending',
      phase: 'preview_ready',
      packagePath: '/tmp/pending.apkg',
      stagingIntact: true,
    ));

    expect(controller.state, isA<AnkiImportPreviewing>());
    final preview = (controller.state as AnkiImportPreviewing).preview
        as OfficialAnkiImportPreviewModel;
    expect(preview.cardCount, 4);
    expect(preview.notetypeByDeck[1], 1);
    expect(engine.importCount, 0);
  });

  test('notes progress with a total becomes determinate wizard state',
      () async {
    OfficialAnkiFeatureFlags.current = const OfficialAnkiFeatureFlags(
      engine: true,
      import: true,
      catalogReady: true,
      runtimeCapable: true,
      platformReady: true,
      projection: true,
      courseEntry: true,
      officialFirstImport: true,
    );
    final root = Directory.systemTemp.createTempSync('turna-prog-');
    addTearDown(() => root.deleteSync(recursive: true));
    final package = File(p.join(root.path, 'slow.apkg'))
      ..writeAsBytesSync(const [1]);
    final engine = FakeOfficialAnkiEngine()
      ..progress = const OfficialAnkiProgress(
        stage: 'notes',
        current: 12,
        total: 40,
      );
    final gate = Completer<void>();
    final savedStaging = OfficialAnkiCompositionRoot.debugStagingEngineOverride;
    OfficialAnkiCompositionRoot.debugStagingEngineOverride = engine;
    addTearDown(() {
      if (!gate.isCompleted) gate.complete();
      OfficialAnkiCompositionRoot.debugStagingEngineOverride = savedStaging;
    });

    final controller = AnkiImportController(
      deps: AnkiImportDependencies(
        planFor: ({required flags, required filePath}) =>
            AnkiImportFacade.planFor(flags, filePath: filePath),
        pickFilePath: ({
          required allowedExtensions,
          required dialogTitle,
        }) async =>
            null,
        officialFirst: _HoldPreview(gate),
        v2ViewStore: OfficialAnkiV2ViewStore(db),
        courseProvider: courseProvider,
      ),
    );
    addTearDown(controller.dispose);
    final pending = controller.proceedWithPath(package.path);
    await Future<void>.delayed(const Duration(milliseconds: 2000));

    expect(controller.state, isA<AnkiImportParsing>());
    final parsing = controller.state as AnkiImportParsing;
    expect(parsing.progressCurrent, 12);
    expect(parsing.progressTotal, 40);
    expect(parsing.stage, contains('12'));
    expect(parsing.stage, contains(AppStrings.ankiProgressReadingNotes));

    gate.complete();
    await pending;
  });

  test('arranging preview keeps its label after a later notes snapshot',
      () async {
    OfficialAnkiFeatureFlags.current = const OfficialAnkiFeatureFlags(
      engine: true,
      import: true,
      catalogReady: true,
      runtimeCapable: true,
      platformReady: true,
      projection: true,
      courseEntry: true,
      officialFirstImport: true,
    );
    final root = Directory.systemTemp.createTempSync('turna-arrange-');
    addTearDown(() => root.deleteSync(recursive: true));
    final package = File(p.join(root.path, 'slow.apkg'))
      ..writeAsBytesSync(const [1]);
    final engine = FakeOfficialAnkiEngine()
      ..progress = const OfficialAnkiProgress(
        stage: 'notes',
        current: 12,
        total: 40,
      );
    final arranged = Completer<void>();
    final gate = Completer<void>();
    final savedStaging = OfficialAnkiCompositionRoot.debugStagingEngineOverride;
    OfficialAnkiCompositionRoot.debugStagingEngineOverride = engine;
    addTearDown(() {
      if (!gate.isCompleted) gate.complete();
      OfficialAnkiCompositionRoot.debugStagingEngineOverride = savedStaging;
    });

    final controller = AnkiImportController(
      deps: AnkiImportDependencies(
        planFor: ({required flags, required filePath}) =>
            AnkiImportFacade.planFor(flags, filePath: filePath),
        pickFilePath: ({
          required allowedExtensions,
          required dialogTitle,
        }) async =>
            null,
        officialFirst: _ArrangeThenHold(gate, arranged, engine),
        v2ViewStore: OfficialAnkiV2ViewStore(db),
        courseProvider: courseProvider,
      ),
    );
    addTearDown(controller.dispose);
    final pending = controller.proceedWithPath(package.path);
    await arranged.future;
    await Future<void>.delayed(const Duration(milliseconds: 1600));

    expect(controller.state, isA<AnkiImportParsing>());
    final parsing = controller.state as AnkiImportParsing;
    expect(parsing.stage, AppStrings.ankiProgressRecognize);
    expect(parsing.progressCurrent, isNull);
    expect(parsing.progressTotal, isNull);

    gate.complete();
    await pending;
  });

  test(
      'replaceExisting passes awaitEnginePass: true before staging the '
      'replacement import', () async {
    OfficialAnkiFeatureFlags.current = const OfficialAnkiFeatureFlags(
      engine: true,
      import: true,
      catalogReady: true,
      runtimeCapable: true,
      platformReady: true,
      projection: true,
      courseEntry: true,
      officialFirstImport: true,
    );
    final root = Directory.systemTemp.createTempSync('turna-replace-');
    addTearDown(() => root.deleteSync(recursive: true));
    final package = File(p.join(root.path, 'deck.apkg'))
      ..writeAsBytesSync(const [4, 5, 6]);
    final digest =
        await const OfficialAnkiSourceHasher().hashFile(package.path);
    final catalog = OfficialAnkiDatabase.memory();
    addTearDown(catalog.close);
    OfficialAnkiSourceDao(catalog).upsertSource(
      sourceId: 'src-live',
      profileId: 'profile-default-01',
      sourceHash: digest.sha256,
      sourceSize: digest.bytes,
      displayName: 'Already',
      state: 'active',
      backendCommit: 'ok',
      nowMillis: 1,
    );
    final stagingEngine = FakeOfficialAnkiEngine()
      ..seedPackage(packagePath: package.path, notes: 1, cards: 1);
    final savedCatalog = OfficialAnkiCompositionRoot.readOnlyCatalog;
    final savedPaths = OfficialAnkiCompositionRoot.locatorPaths;
    final savedStaging = OfficialAnkiCompositionRoot.debugStagingEngineOverride;
    OfficialAnkiCompositionRoot.readOnlyCatalog = catalog;
    OfficialAnkiCompositionRoot.locatorPaths = OfficialAnkiPaths(
      profileId: 'profile-default-01',
      profileRoot: Directory(p.join(root.path, 'live'))..createSync(),
    );
    OfficialAnkiCompositionRoot.debugStagingEngineOverride = stagingEngine;
    addTearDown(() {
      OfficialAnkiCompositionRoot.readOnlyCatalog = savedCatalog;
      OfficialAnkiCompositionRoot.locatorPaths = savedPaths;
      OfficialAnkiCompositionRoot.debugStagingEngineOverride = savedStaging;
      OfficialAnkiCompositionRoot.stagingEngine = null;
      OfficialAnkiCompositionRoot.stagingSession = null;
    });

    final uninstallGate = Completer<void>();
    final uninstallStarted = Completer<void>();
    final recordingDeckManager = _RecordingAnkiDeckManager(
      repo: getIt<ICourseRepository>(),
      onUninstall: () async {
        if (!uninstallStarted.isCompleted) uninstallStarted.complete();
        await uninstallGate.future;
        OfficialAnkiSourceDao(catalog).deleteSourceV2(sourceId: 'src-live');
      },
    );
    getIt.registerSingleton<AnkiDeckManager>(recordingDeckManager);

    final controller = controllerWith();
    addTearDown(controller.dispose);
    await controller.proceedWithPath(package.path);
    expect(controller.state, isA<AnkiImportAlreadyImported>());

    final replacing = controller.replaceExisting();
    await uninstallStarted.future;
    await Future<void>.delayed(Duration.zero);

    expect(
      recordingDeckManager.uninstallCalls,
      [('src-live', true)],
      reason: 'replaceExisting must pass awaitEnginePass: true',
    );
    expect(
      stagingEngine.importCount,
      0,
      reason: 'replacement import must wait until awaited uninstall completes',
    );

    uninstallGate.complete();
    await replacing;
    expect(stagingEngine.importCount, 1);
    expect(controller.state, isA<AnkiImportPreviewing>());
  });

  test(
      'AnkiDeckManager.uninstall with awaitEnginePass: true awaits large-deck '
      'engine card deletion before returning', () async {
    final root = Directory.systemTemp.createTempSync('turna-large-retire-');
    addTearDown(() {
      try {
        root.deleteSync(recursive: true);
      } catch (_) {/* best-effort temp cleanup */}
    });
    final liveRoot = Directory(p.join(root.path, 'live'))..createSync();
    final catalog = OfficialAnkiDatabase.memory();
    final paths = OfficialAnkiPaths(
      profileId: 'profile-default-01',
      profileRoot: liveRoot,
    );
    const cardTotal = 5005;
    final sources = OfficialAnkiSourceDao(catalog);
    sources.upsertSource(
      sourceId: 'src-large',
      profileId: paths.profileId,
      sourceHash: 'hash-large',
      sourceSize: cardTotal,
      displayName: 'Large Deck',
      state: 'active',
      backendCommit: 'ok',
      nowMillis: 1,
    );
    sources.markChainV2(sourceId: 'src-large', nowMillis: 1);
    sources.upsertCardBatch(
      sourceId: 'src-large',
      cards: [
        for (var i = 1; i <= cardTotal; i++)
          OfficialAnkiCardDescriptor(
            cardId: i,
            noteId: i,
            deckId: 1,
            templateOrd: 0,
            notetypeId: 1,
          ),
      ],
    );

    final engine = _BlockingDeleteEngine();
    for (var i = 1; i <= cardTotal; i++) {
      engine.cards[i] = OfficialAnkiCardDescriptor(
        cardId: i,
        noteId: i,
        deckId: 1,
        templateOrd: 0,
        notetypeId: 1,
      );
      engine.cardsByNote[i] = [i];
    }

    final savedCatalog = OfficialAnkiCompositionRoot.readOnlyCatalog;
    final savedPaths = OfficialAnkiCompositionRoot.locatorPaths;
    final savedEngine = OfficialAnkiCompositionRoot.debugEngineOverride;
    OfficialAnkiCompositionRoot.readOnlyCatalog = catalog;
    OfficialAnkiCompositionRoot.locatorPaths = paths;
    OfficialAnkiCompositionRoot.debugEngineOverride = engine;
    addTearDown(() async {
      for (var i = 0; i < 40; i++) {
        if (OfficialAnkiMaintenanceJobDao(catalog)
            .pending(profileId: paths.profileId)
            .isEmpty) {
          break;
        }
        await Future<void>.delayed(const Duration(milliseconds: 10));
      }
      OfficialAnkiCompositionRoot.readOnlyCatalog = savedCatalog;
      OfficialAnkiCompositionRoot.locatorPaths = savedPaths;
      OfficialAnkiCompositionRoot.debugEngineOverride = savedEngine;
      catalog.close();
    });

    final manager = AnkiDeckManager(repo: getIt<ICourseRepository>());
    var finished = false;
    final uninstallFuture =
        manager.uninstall('src-large', awaitEnginePass: true).then((ok) {
      finished = true;
      return ok;
    });

    await engine.firstDeleteEntered.future;
    await Future<void>.delayed(const Duration(milliseconds: 20));
    expect(
      finished,
      isFalse,
      reason: 'awaitEnginePass: true must block even when cardCount > 5000',
    );

    engine.allowDeleteFinish.complete();
    expect(await uninstallFuture, isTrue);
    expect(engine.cards, isEmpty);
    expect(sources.findById('src-large'), isNull);
  });
}

class _HoldPreview extends OfficialAnkiOfficialFirstService {
  _HoldPreview(this.gate);

  final Completer<void> gate;

  @override
  Future<OfficialAnkiOfficialFirstPreview> importThenPreview({
    required String filePath,
    required AnkiImportExecutionPlan plan,
    OfficialAnkiFeatureFlags? flags,
    OfficialAnkiSourceDigest? digest,
    bool withMedia = true,
    void Function()? onArrangingPreview,
  }) async {
    await gate.future;
    throw const OfficialAnkiException(
      code: OfficialAnkiErrorCode.importCancelled,
      messageKey: 'official_anki.import_cancelled',
      recoverable: true,
    );
  }
}

class _ArrangeThenHold extends OfficialAnkiOfficialFirstService {
  _ArrangeThenHold(this.gate, this.arranged, this.engine);

  final Completer<void> gate;
  final Completer<void> arranged;
  final FakeOfficialAnkiEngine engine;

  @override
  Future<OfficialAnkiOfficialFirstPreview> importThenPreview({
    required String filePath,
    required AnkiImportExecutionPlan plan,
    OfficialAnkiFeatureFlags? flags,
    OfficialAnkiSourceDigest? digest,
    bool withMedia = true,
    void Function()? onArrangingPreview,
  }) async {
    await Future<void>.delayed(const Duration(milliseconds: 1500));
    onArrangingPreview?.call();
    engine.progress = const OfficialAnkiProgress(
      stage: 'notes',
      current: 30,
      total: 80,
    );
    if (!arranged.isCompleted) arranged.complete();
    await gate.future;
    throw const OfficialAnkiException(
      code: OfficialAnkiErrorCode.importCancelled,
      messageKey: 'official_anki.import_cancelled',
      recoverable: true,
    );
  }
}

class _RecordingAnkiDeckManager extends AnkiDeckManager {
  _RecordingAnkiDeckManager({
    required super.repo,
    required this.onUninstall,
  });

  final Future<void> Function() onUninstall;
  final uninstallCalls = <(String, bool)>[];

  @override
  Future<bool> uninstall(
    String importId, {
    bool awaitEnginePass = false,
  }) async {
    uninstallCalls.add((importId, awaitEnginePass));
    await onUninstall();
    return true;
  }
}

class _BlockingDeleteEngine extends FakeOfficialAnkiEngine {
  final firstDeleteEntered = Completer<void>();
  final allowDeleteFinish = Completer<void>();

  @override
  Future<int> deleteCards(List<int> cardIds) async {
    if (!firstDeleteEntered.isCompleted) firstDeleteEntered.complete();
    await allowDeleteFinish.future;
    return super.deleteCards(cardIds);
  }
}
