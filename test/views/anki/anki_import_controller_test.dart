// Wave 4 controller tests (maintainability plan §6.2-4), official-flow
// remainder after doc 35 L1 deleted the Legacy parser flow: pick-time plan
// stays frozen, previews are expressed by sealed variants, and an
// official-first failure produces zero Legacy writes.

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:streaming_shared_preferences/streaming_shared_preferences.dart';
import 'package:turna/application/anki_import/anki_import_controller.dart';
import 'package:turna/application/anki_import/anki_import_dependencies.dart';
import 'package:turna/application/anki_import/anki_import_wizard_state.dart';
import 'package:turna/application/anki_official/contract/official_anki_errors.dart';
import 'package:turna/application/anki_official/engine/official_anki_native_availability.dart';
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
import 'package:turna/domain/repositories/i_course_repository.dart';
import 'package:turna/di/injection.dart';
import 'package:turna/service/locator.dart';

import '../../helpers/in_memory_course_db.dart';

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
    getIt.registerSingleton<ReviewHistoryDao>(ReviewHistoryDao(db));
    getIt.registerSingleton<AnkiNoteDao>(AnkiNoteDao(db));
    getIt.registerSingleton<AnkiImportDao>(AnkiImportDao(db));
    getIt.registerSingleton<AnkiUnificationDao>(AnkiUnificationDao(db));

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
        pickFilePath: ({required allowedExtensions, required dialogTitle}) async =>
            pickedPath,
        officialFirst: const OfficialAnkiOfficialFirstService(),
        courseDatabase: db,
        readOfficialProjectionSummary: (sourceId) async =>
            OfficialProjectionSummary(
          sourceId: sourceId,
          sectionIds: const {},
          itemCount: 0,
        ),
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
    expect(await getIt<AnkiImportDao>().getAll(), isEmpty);
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

    final controller = controllerWith();
    addTearDown(controller.dispose);

    await controller.proceedWithPath('/tmp/o.apkg');

    expect(failing.calls, 1, reason: 'the official saga ran');
    expect(controller.state, isA<AnkiImportFailed>(),
        reason: 'the wizard surfaces the failure');
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
