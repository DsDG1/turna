// Official-first production import: saga before any Turna-side write
// (failure → zero Turna rows). Flag-off / legacyMirror must fail-closed
// rather than reopen a Legacy writer (doc 34 W0).
//
// The wizard is driven through the real file-pick flow with an injected
// parser ([AnkiImportPage.importerForTest]) so everything stays synchronous —
// fake-async cannot receive worker-isolate port messages.

// Dart imports:
import 'dart:io';

// Package imports:
import 'package:drift/native.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:streaming_shared_preferences/streaming_shared_preferences.dart';
import 'package:turna/application/ai/engine/ai_engine_config_holder.dart';
import 'package:turna/application/anki/anki_deck_manager.dart';
import 'package:turna/application/anki/anki_importer.dart';
import 'package:turna/application/anki/anki_models.dart';
import 'package:turna/application/anki/anki_sample_deck.dart';
import 'package:turna/application/anki/unified_anki_import_orchestrator.dart';
import 'package:turna/application/anki_official/contract/official_anki_errors.dart';
import 'package:turna/application/anki_official/import/official_anki_import_state.dart';
import 'package:turna/application/anki_official/migration/official_anki_engine_kind.dart';
import 'package:turna/application/anki_official/contract/official_anki_dto.dart';
import 'package:turna/application/anki_official/engine/official_anki_engine_fake.dart';
import 'package:turna/application/anki_official/engine/official_anki_native_availability.dart';
import 'package:turna/application/anki_official/official_anki_composition.dart';
import 'package:turna/application/anki_official/official_anki_feature_flags.dart';
import 'package:turna/application/anki_official/storage/official_anki_database.dart';
import 'package:turna/application/anki_official/storage/official_anki_source_dao.dart';
import 'package:turna/application/course_provider.dart';
import 'package:turna/application/lesson_link_store.dart';
import 'package:turna/application/mistake_provider.dart';
import 'package:turna/application/settings_provider.dart';
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
import 'package:turna/l10n/app_strings.dart';
import 'package:turna/service/locator.dart';
import 'package:turna/views/anki/anki_import_screen.dart';
import 'package:path/path.dart' as p;

import '../../helpers/in_memory_course_db.dart';

/// Returns the built-in sample collection synchronously so the whole wizard
/// (preview + import) runs inside fake-async.
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

class _FakePicker extends FilePicker {
  _FakePicker(this.path);

  final String path;

  @override
  Future<FilePickerResult?> pickFiles({
    String? dialogTitle,
    String? initialDirectory,
    FileType type = FileType.any,
    List<String>? allowedExtensions,
    Function(FilePickerStatus)? onFileLoading,
    bool allowCompression = true,
    int compressionQuality = 30,
    bool allowMultiple = false,
    bool withData = false,
    bool withReadStream = false,
    bool lockParentWindow = false,
    bool readSequential = false,
  }) async =>
      FilePickerResult([
        PlatformFile(path: path, name: p.basename(path), size: 1),
      ]);
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
      debugDetails: 'p5f test failure',
    );
  }
}

class _ActiveOfficialImporter implements OfficialAnkiImporter {
  _ActiveOfficialImporter(
    this.dao, {
    this.sourceId = 'src-p5f-test',
  });

  final AnkiImportDao dao;
  final String sourceId;
  int calls = 0;

  /// Import rows present at the moment the official saga ran — proves the
  /// saga ran BEFORE the Turna transaction.
  List<String> importIdsAtOfficialRun = const [];

  @override
  Future<OfficialAnkiImportResult> importFile({
    required String packagePath,
    required String displayName,
    String? requestId,
    bool cancel = false,
  }) async {
    calls++;
    importIdsAtOfficialRun =
        (await dao.getAll()).map((r) => r.importId).toList();
    return OfficialAnkiImportResult(
      sourceId: sourceId,
      attemptId: 'att-$sourceId',
      state: OfficialAnkiSourceState.active,
      cardCount: 2,
      noteCount: 2,
    );
  }
}

const _capableFlags = OfficialAnkiFeatureFlags(
  engine: true,
  import: true,
  catalogReady: true,
  runtimeCapable: true,
  platformReady: true,
  projection: true,
  courseEntry: true,
);

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
  late OfficialAnkiDatabase? savedCatalog;
  late Directory tmpDir;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    final preferences = await StreamingSharedPreferences.instance;
    appPrefs = AppPrefs(preferences);

    tmpDir = await Directory.systemTemp.createTemp('p5f-import');
    // The official mirror opens a catalog sqlite file under the (mocked)
    // support directory; sqlite cannot create parent dirs itself.
    await Directory(p.join(
      Directory.systemTemp.path,
      'official_anki',
      'default',
    )).create(recursive: true);

    db = CourseDatabase(NativeDatabase.memory());
    final getIt = GetIt.instance;
    await getIt.reset();
    getIt.registerSingleton<CourseDatabase>(db);
    getIt.registerSingleton<ICourseRepository>(CourseRepository(db));
    getIt.registerSingleton<ReviewHistoryDao>(ReviewHistoryDao(db));
    getIt.registerSingleton<AnkiNoteDao>(AnkiNoteDao(db));
    final importDao = AnkiImportDao(db);
    getIt.registerSingleton<AnkiImportDao>(importDao);
    getIt.registerSingleton<AnkiUnificationDao>(AnkiUnificationDao(db));

    courseProvider = CourseProvider(appPrefs);
    final linkStore = LessonLinkStore(appPrefs);
    srsProvider = SrsProvider(appPrefs, linkStore, SrsStateDao(db));
    getIt.registerSingleton<CourseProvider>(courseProvider);
    getIt.registerSingleton<SrsProvider>(srsProvider);
    getIt.registerSingleton<MistakeProvider>(MistakeProvider(appPrefs));
    getIt.registerSingleton<AnkiDeckManager>(
      AnkiDeckManager(
        repo: getIt<ICourseRepository>(),
        srsProvider: srsProvider,
        importDao: importDao,
        noteDao: getIt<AnkiNoteDao>(),
        appPrefs: appPrefs,
      ),
    );
    CourseLoader.overrideDatabase(() => db);

    savedFlags = OfficialAnkiFeatureFlags.current;
    savedSession = OfficialAnkiCompositionRoot.session;
    savedCatalog = OfficialAnkiCompositionRoot.readOnlyCatalog;
    FilePicker.platform = _FakePicker(p.join(tmpDir.path, 'p5f.apkg'));
    // The unified orchestrator is a process singleton; without this its
    // in-memory hash set leaks across tests and short-circuits the next
    // import as a no-op.
    UnifiedAnkiImportOrchestrator.instance.reset();
    // Host tests run on linux; production official routing is android-only.
    OfficialAnkiCapabilityMatrix.overrideHostPlatformForTests = 'android';
    // And the routing additionally requires the native library probe to pass
    // (on this host no .so exists, which would degrade routing to legacy).
    OfficialAnkiNativeAvailability.debugOverride = true;
    OfficialAnkiFeatureFlags.current =
        _capableFlags.copyWith(officialFirstImport: true);
  });

  tearDown(() async {
    OfficialAnkiCapabilityMatrix.overrideHostPlatformForTests = null;
    OfficialAnkiNativeAvailability.debugOverride = null;
    OfficialAnkiFeatureFlags.current = savedFlags;
    OfficialAnkiCompositionRoot.session = savedSession;
    OfficialAnkiCompositionRoot.debugEngineOverride = null;
    final openedCatalog = OfficialAnkiCompositionRoot.readOnlyCatalog;
    if (openedCatalog != null && !identical(openedCatalog, savedCatalog)) {
      openedCatalog.close();
    }
    OfficialAnkiCompositionRoot.readOnlyCatalog = savedCatalog;
    CourseLoader.clearDatabaseOverride();
    await db.close();
    await GetIt.instance.reset();
    await tmpDir.delete(recursive: true);
  });

  Future<void> pumpWizard(WidgetTester tester) async {
    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<SettingsProvider>.value(
            value: SettingsProvider(appPrefs),
          ),
          ChangeNotifierProvider<CourseProvider>.value(value: courseProvider),
          ChangeNotifierProvider<SrsProvider>.value(value: srsProvider),
          ChangeNotifierProvider<AiEngineConfigHolder>.value(
            value: AiEngineConfigHolder(),
          ),
        ],
        child: MaterialApp(
          home: AnkiImportPage(importerForTest: _ImmediateImporter()),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> pickAndWaitForPreview(WidgetTester tester) async {
    await tester.tap(
      find.widgetWithText(ElevatedButton, AppStrings.ankiChooseFile),
    );
    await tester.pumpAndSettle();
    expect(find.text(AppStrings.ankiPreviewStartImport), findsOneWidget,
        reason: 'preview step reached');
  }

  Future<void> startImport(WidgetTester tester) async {
    await tester.tap(find.text(AppStrings.ankiPreviewStartImport));
    await tester.pumpAndSettle();
  }

  testWidgets(
      'p5f_official_first_failure_leaves_zero_turna_writes', (tester) async {
    tester.view.physicalSize = const Size(1080, 1920);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);

    final failing = _FailingOfficialImporter();
    OfficialAnkiCompositionRoot.session = failing;
    await pumpWizard(tester);
    await tester.tap(
      find.widgetWithText(ElevatedButton, AppStrings.ankiChooseFile),
    );
    await tester.pumpAndSettle();

    expect(failing.calls, 1, reason: 'official saga ran');
    expect(
      find.widgetWithText(ElevatedButton, AppStrings.ankiChooseFile),
      findsOneWidget,
      reason: 'wizard returned to the select step with the mapped error',
    );
    final records = await getIt<AnkiImportDao>().getAll();
    expect(records, isEmpty,
        reason: 'official-first failure must write no anki_imports row');
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

  testWidgets('p5f_official_first_flow_projects_course_and_publishes',
      (tester) async {
    tester.view.physicalSize = const Size(1080, 1920);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);

    final catalog = OfficialAnkiDatabase.memory();
    OfficialAnkiCompositionRoot.readOnlyCatalog = catalog;
    OfficialAnkiSourceDao(catalog).upsertSource(
      sourceId: 'src-p5f2',
      profileId: 'profile-default-01',
      sourceHash: 'hash-p5f2',
      sourceSize: 1,
      displayName: 'p5f.apkg',
      state: 'active',
      backendCommit: 'test',
      nowMillis: 1,
    );
    OfficialAnkiSourceDao(catalog).replaceCards(
      sourceId: 'src-p5f2',
      cards: const [
        OfficialAnkiCardDescriptor(
            cardId: 1, noteId: 1, deckId: 1, templateOrd: 0, noteGuid: 'g1'),
        OfficialAnkiCardDescriptor(
            cardId: 2, noteId: 2, deckId: 1, templateOrd: 0, noteGuid: 'g2'),
      ],
    );
    final engine = FakeOfficialAnkiEngine();
    engine.seedPackage(packagePath: 'x.apkg', notes: 2, cards: 2);
    OfficialAnkiCompositionRoot.debugEngineOverride = engine;
    OfficialAnkiCompositionRoot.session = _ActiveOfficialImporter(
      getIt<AnkiImportDao>(),
      sourceId: 'src-p5f2',
    );

    await pumpWizard(tester);
    await pickAndWaitForPreview(tester);

    // Projection-based preview, not the legacy collection preview.
    expect(find.text(AppStrings.ankiOfficialPreviewBody), findsOneWidget);
    expect(find.textContaining('已识别'), findsOneWidget);
    expect(find.text(AppStrings.ankiOfficialMappingSuggested), findsNothing,
        reason: 'normal mappings stay collapsed behind the summary');

    await startImport(tester);

    expect(find.text(AppStrings.ankiImportComplete), findsOneWidget);
    final sections = await getIt<ICourseRepository>().sectionShells();
    expect(
      sections.where((s) => s.id.startsWith('official-anki-src-p5f2-')),
      isNotEmpty,
      reason: 'course tree projected from the official collection',
    );
    final placements = getIt<CourseDatabase>();
    final count = await placements.customSelect(
      'SELECT COUNT(*) AS n FROM anki_course_card_placements '
      "WHERE source_id = 'src-p5f2'",
    ).getSingle();
    expect(count.read<int>('n'), 2,
        reason: 'placements published from the projection index');
    final imports = await getIt<AnkiImportDao>().getAll();
    expect(imports, isEmpty,
        reason: 'official-first flow writes no legacy anki_imports rows');
    expect(
      srsProvider.state.keys.where((id) => id.startsWith('anki-')),
      isEmpty,
      reason: 'no Turna SRS rows',
    );
  });

  testWidgets('official_first_flag_off_fail_closes_with_zero_writes',
      (tester) async {
    tester.view.physicalSize = const Size(1080, 1920);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);

    OfficialAnkiFeatureFlags.current =
        _capableFlags.copyWith(officialFirstImport: false);
    final failing = _FailingOfficialImporter();
    OfficialAnkiCompositionRoot.session = failing;
    await pumpWizard(tester);
    await tester.tap(
      find.widgetWithText(ElevatedButton, AppStrings.ankiChooseFile),
    );
    await tester.pumpAndSettle();

    expect(failing.calls, 0, reason: 'fail-closed never starts the saga');
    expect(
      find.text(
        AppStrings.ankiImportUnavailable('official_first_required_but_flag_off'),
      ),
      findsOneWidget,
    );
    final records = await getIt<AnkiImportDao>().getAll();
    expect(records, isEmpty, reason: 'flag-off must not write Legacy rows');
    expect(
      srsProvider.state.keys.where((id) => id.startsWith('anki-')),
      isEmpty,
    );
  });

  testWidgets('legacyMirror_cannot_reopen_legacy_writer_when_official_first_off',
      (tester) async {
    tester.view.physicalSize = const Size(1080, 1920);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);

    OfficialAnkiFeatureFlags.current = _capableFlags.copyWith(
      officialFirstImport: false,
      legacyMirror: true,
    );
    final failing = _FailingOfficialImporter();
    OfficialAnkiCompositionRoot.session = failing;
    await pumpWizard(tester);
    await tester.tap(
      find.widgetWithText(ElevatedButton, AppStrings.ankiChooseFile),
    );
    await tester.pumpAndSettle();

    expect(failing.calls, 0);
    final records = await getIt<AnkiImportDao>().getAll();
    expect(records, isEmpty,
        reason: 'legacyMirror must not resurrect mixed-owner writes');
  });
}
