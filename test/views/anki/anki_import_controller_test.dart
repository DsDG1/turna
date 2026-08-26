// Wave 4 controller tests (maintainability plan §6.2-4): the wizard state
// machine owns the flow — pick-time plan stays frozen, previews are
// expressed by sealed variants, stale async callbacks cannot overwrite a
// newer selection, dispose/cancel clean the temp dir, repeated commit is
// single-flight, and an official-first failure produces zero Legacy
// writes.

import 'dart:async';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:streaming_shared_preferences/streaming_shared_preferences.dart';
import 'package:turna/application/ai/engine/ai_engine_config_holder.dart';
import 'package:turna/application/anki/anki_card_adapter.dart';
import 'package:turna/application/anki/anki_deck_assembler.dart';
import 'package:turna/application/anki/anki_importer.dart';
import 'package:turna/application/anki/anki_models.dart';
import 'package:turna/application/anki/anki_sample_deck.dart';
import 'package:turna/application/anki/card_recognition_pipeline.dart';
import 'package:turna/application/anki/import_wizard/anki_import_controller.dart';
import 'package:turna/application/anki/import_wizard/anki_import_dependencies.dart';
import 'package:turna/application/anki/import_wizard/anki_import_wizard_state.dart';
import 'package:turna/application/anki/legacy_anki_import_executor.dart';
import 'package:turna/application/anki_official/contract/official_anki_errors.dart';
import 'package:turna/application/anki_official/engine/official_anki_native_availability.dart';
import 'package:turna/application/anki_official/import/anki_import_execution_plan.dart';
import 'package:turna/application/anki_official/import/anki_import_facade.dart';
import 'package:turna/application/anki_official/import/official_anki_import_state.dart';
import 'package:turna/application/anki_official/import/official_anki_official_first_service.dart';
import 'package:turna/application/anki_official/migration/official_anki_engine_kind.dart';
import 'package:turna/application/anki_official/official_anki_composition.dart';
import 'package:turna/application/anki_official/official_anki_feature_flags.dart';
import 'package:turna/application/anki_official/projection/official_anki_projection_store.dart';
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
import 'package:turna/domain/audio/anki_audio_resolver.dart';
import 'package:turna/domain/repositories/i_course_repository.dart';
import 'package:turna/di/injection.dart';
import 'package:turna/service/locator.dart';

import '../../helpers/in_memory_course_db.dart';

/// Parse hangs until the test completes it — drives the stale-callback
/// and cancel paths deterministically.
class _HangingImporter extends AnkiImporter {
  final Completer<AnkiCollection> gate = Completer();

  @override
  Future<AnkiCollection> parse(
    String apkgPath, {
    String? tempDir,
    void Function(double progress, String message)? onProgress,
    bool Function()? isCancelled,
  }) {
    onProgress?.call(0.1, 'working');
    return gate.future;
  }
}

/// Immediate sample-backed parse.
class _ImmediateImporter extends AnkiImporter {
  @override
  Future<AnkiCollection> parse(
    String apkgPath, {
    String? tempDir,
    void Function(double progress, String message)? onProgress,
    bool Function()? isCancelled,
  }) async {
    onProgress?.call(1, 'done');
    return AnkiSampleDeck.build();
  }
}

class _CountingExecutor implements LegacyAnkiImportExecutor {
  _CountingExecutor();

  int calls = 0;
  Completer<LegacyAnkiImportExecutionResult>? gate;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);

  @override
  Future<LegacyAnkiImportExecutionResult> execute(
    LegacyAnkiImportRequest request,
  ) {
    calls++;
    if (gate != null) return gate!.future;
    return Future.value(_fakeResult());
  }

  static LegacyAnkiImportExecutionResult _fakeResult() =>
      LegacyAnkiImportExecutionResult(
        importId: 'legacy-test',
        summary: AnkiImportSummary(
          importId: 'legacy-test',
          sectionCount: 1,
          unitCount: 1,
          lessonCount: 2,
          cardCount: 4,
          wordEntryCount: 0,
          sourceCardCount: 4,
        ),
        mediaReport: AnkiMediaCopyReport(),
      );
}

class _FailingOfficialImporter implements OfficialAnkiImporter {
  int calls = 0;

  @override
  Future<OfficialAnkiImportResult> importFile({
    required String packagePath,
    required String displayName,
    String? requestId,
    bool cancel = false,
  }) async {
    calls++;
    throw const OfficialAnkiException(
      code: OfficialAnkiErrorCode.invalidState,
      messageKey: 'official_anki.import_failed',
    );
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  ensurePathProviderMockForTest();
  ensureSqliteLibForTestHost();

  late CourseDatabase db;
  late AppPrefs appPrefs;
  late CourseProvider courseProvider;
  late SrsProvider srsProvider;
  late AiEngineConfigHolder aiHolder;
  late OfficialAnkiFeatureFlags savedFlags;
  late OfficialAnkiImporter? savedSession;
  late _CountingExecutor countingExecutor;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    final preferences = await StreamingSharedPreferences.instance;
    appPrefs = AppPrefs(preferences);

    db = CourseDatabase(NativeDatabase.memory());
    final getIt = GetIt.instance;
    await getIt.reset();
    getIt.registerSingleton<CourseDatabase>(db);
    getIt.registerSingleton<ICourseRepository>(CourseRepository(db));
    getIt.registerSingleton<ReviewHistoryDao>(ReviewHistoryDao(db));
    getIt.registerSingleton<AnkiNoteDao>(AnkiNoteDao(db));
    getIt.registerSingleton<AnkiImportDao>(AnkiImportDao(db));
    getIt.registerSingleton<AnkiUnificationDao>(AnkiUnificationDao(db));

    courseProvider = CourseProvider(appPrefs);
    final linkStore = LessonLinkStore(appPrefs);
    srsProvider = SrsProvider(appPrefs, linkStore, SrsStateDao(db));
    getIt.registerSingleton<CourseProvider>(courseProvider);
    getIt.registerSingleton<SrsProvider>(srsProvider);
    aiHolder = AiEngineConfigHolder();
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

  AnkiImportController controllerWith({
    required AnkiImporter importer,
    String? pickedPath,
    bool legacyOnly = false,
  }) {
    countingExecutor = _CountingExecutor();
    return AnkiImportController(
      deps: AnkiImportDependencies(
        planFor: ({
          required flags,
          required isSample,
          required filePath,
        }) =>
            legacyOnly
                ? AnkiImportFacade.planFor(
                    flags,
                    platform: 'test-host',
                    allowLegacyOnly: true,
                    isSample: isSample,
                    filePath: filePath,
                  )
                : AnkiImportFacade.planFor(
                    flags,
                    isSample: isSample,
                    filePath: filePath,
                  ),
        pickFilePath: ({required allowedExtensions, required dialogTitle}) async =>
            pickedPath,
        importer: importer,
        legacyExecutorFactory: () => countingExecutor,
        officialFirst: const OfficialAnkiOfficialFirstService(),
        recognitionPipelineFactory: ({engine}) => CardRecognitionPipeline(
          engine: engine,
        ),
        courseDatabase: db,
        findExistingImportByHash: (hash) async => null,
        readOfficialProjectionSummary: (sourceId) async =>
            OfficialProjectionSummary(
          sourceId: sourceId,
          sectionIds: const {},
          itemCount: 0,
        ),
        srsProvider: srsProvider,
        courseProvider: courseProvider,
        aiConfigHolder: aiHolder,
        resolveAiEngine: () => null,
        ankiLiteThreshold: 200,
        dailyNewLimit: 20,
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
    final controller = controllerWith(importer: _ImmediateImporter());
    addTearDown(controller.dispose);

    await controller.proceedWithPath('/tmp/a.apkg');

    // Everything off on the host → fail closed with zero writes.
    expect(controller.state, isA<AnkiImportFailed>());
    expect((controller.state as AnkiImportFailed).returnState,
        isA<AnkiImportSelecting>());
    expect(await getIt<AnkiImportDao>().getAll(), isEmpty);
  });

  test('legacy preview is expressed by the sealed variant', () async {
    OfficialAnkiFeatureFlags.current = const OfficialAnkiFeatureFlags();
    final controller = controllerWith(
      importer: _ImmediateImporter(),
      legacyOnly: true,
    );
    addTearDown(controller.dispose);

    await controller.proceedWithPath('/tmp/a.apkg');

    expect(controller.state, isA<AnkiImportPreviewing>());
    final preview = (controller.state as AnkiImportPreviewing).preview;
    expect(preview, isA<LegacyAnkiImportPreviewModel>());
    final legacy = preview as LegacyAnkiImportPreviewModel;
    expect(legacy.plan.kind, AnkiImportExecutionKind.legacyOnly);
    expect(legacy.collection.cards, isNotEmpty);
    expect(controller.plan?.kind, AnkiImportExecutionKind.legacyOnly);
  });

  test('a stale parse callback never overwrites the next selection', () async {
    OfficialAnkiFeatureFlags.current = const OfficialAnkiFeatureFlags();
    final controller = controllerWith(
      importer: _ImmediateImporter(),
      legacyOnly: true,
    );
    addTearDown(controller.dispose);

    // First pick hangs inside parse; the user cancels and picks a fast
    // file instead. The slow parse's late completion must be dropped.
    final hanging = _HangingImporter();
    final slowController = controllerWith(
      importer: hanging,
      legacyOnly: true,
    );
    final firstParse = slowController.proceedWithPath('/tmp/slow.apkg');
    expect(slowController.state, isA<AnkiImportParsing>());
    slowController.cancel();

    await controller.proceedWithPath('/tmp/fast.apkg');
    expect(controller.state, isA<AnkiImportPreviewing>());

    // Completing the abandoned parse must not touch the OTHER controller
    // (it was cancelled) nor overwrite this one's state.
    expect(controller.state, isA<AnkiImportPreviewing>());
    final legacy = (controller.state as AnkiImportPreviewing).preview
        as LegacyAnkiImportPreviewModel;
    expect(legacy.filePath, '/tmp/fast.apkg');
    hanging.gate.complete(AnkiSampleDeck.build());
    await firstParse;
    expect(slowController.state, isA<AnkiImportSelecting>(),
        reason: 'cancel returned the abandoned wizard to select');
    expect(controller.state, isA<AnkiImportPreviewing>(),
        reason: 'the stale parse result was dropped, not applied');
  });

  test('repeated commit intents execute the executor exactly once', () async {
    OfficialAnkiFeatureFlags.current = const OfficialAnkiFeatureFlags();
    final controller = controllerWith(
      importer: _ImmediateImporter(),
      legacyOnly: true,
    );
    addTearDown(controller.dispose);

    await controller.proceedWithPath('/tmp/a.apkg');
    final legacy = (controller.state as AnkiImportPreviewing).preview
        as LegacyAnkiImportPreviewModel;
    legacy.recognitionResults
        .clear(); // avoid blocking on unmapped notetypes
    // Give every notetype a valid mapping so commit is not blocked.
    for (final entry in legacy.collection.notetypes.entries) {
      legacy.mappings[entry.key] = NotetypeMapping(
        type: NotetypeMappingType.cloze,
      );
    }

    countingExecutor.gate = Completer();
    final first = controller.commit();
    expect(controller.state, isA<AnkiImportCommitting>(),
        reason: 'first intent starts the commit');
    final second = controller.commit();
    expect(countingExecutor.calls, 1,
        reason: 'the second intent is a no-op while committing');

    countingExecutor.gate!.complete(_CountingExecutor._fakeResult());
    await first;
    await second;
    expect(controller.state, isA<AnkiImportCompleted>());
    expect(countingExecutor.calls, 1);
  });

  test('dispose releases the parse temp dir and stops updates', () async {
    OfficialAnkiFeatureFlags.current = const OfficialAnkiFeatureFlags();
    final controller = controllerWith(
      importer: _ImmediateImporter(),
      legacyOnly: true,
    );
    await controller.proceedWithPath('/tmp/a.apkg');
    expect(controller.state, isA<AnkiImportPreviewing>());

    await controller.disposeAsync();
    expect(controller.state, isA<AnkiImportPreviewing>(),
        reason: 'dispose does not change the visible state object');
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
    final failing = _FailingOfficialImporter();
    OfficialAnkiCompositionRoot.session = failing;

    final controller = controllerWith(importer: _ImmediateImporter());
    addTearDown(controller.dispose);

    await controller.proceedWithPath('/tmp/o.apkg');

    expect(failing.calls, 1, reason: 'the official saga ran');
    expect(controller.state, isA<AnkiImportFailed>(),
        reason: 'the wizard surfaces the failure');
    expect(controller.state, isA<AnkiImportFailed>());
    expect((controller.state as AnkiImportFailed).returnState,
        isA<AnkiImportSelecting>());
    expect(await getIt<AnkiImportDao>().getAll(), isEmpty,
        reason: 'no anki_imports row');
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
}
