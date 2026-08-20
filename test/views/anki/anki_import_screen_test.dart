import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:streaming_shared_preferences/streaming_shared_preferences.dart';
import 'package:turna/application/ai/engine/ai_engine_config_holder.dart';
import 'package:turna/application/anki/anki_deck_manager.dart';
import 'package:turna/application/course_provider.dart';
import 'package:turna/application/lesson_link_store.dart';
import 'package:turna/application/settings_provider.dart';
import 'package:turna/application/srs_provider.dart';
import 'package:turna/courses/course_loader.dart';
import 'package:turna/data/anki_import_dao.dart';
import 'package:turna/data/anki_note_dao.dart';
import 'package:turna/data/course_database.dart';
import 'package:turna/data/course_repository.dart';
import 'package:turna/data/review_history_dao.dart';
import 'package:turna/data/srs_state_dao.dart';
import 'package:turna/domain/repositories/i_course_repository.dart';
import 'package:turna/l10n/app_strings.dart';
import 'package:turna/service/locator.dart';
import 'package:turna/views/anki/anki_import_screen.dart';

import '../../helpers/in_memory_course_db.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  ensurePathProviderMockForTest();
  ensureSqliteLibForTestHost();

  late CourseDatabase db;
  late AppPrefs appPrefs;
  late SettingsProvider settingsProvider;
  late CourseProvider courseProvider;
  late SrsProvider srsProvider;
  late AiEngineConfigHolder aiConfigHolder;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    final preferences = await StreamingSharedPreferences.instance;
    appPrefs = AppPrefs(preferences);

    db = CourseDatabase(NativeDatabase.memory());
    final getIt = GetIt.instance;
    getIt.reset();

    getIt.registerSingleton<CourseDatabase>(db);
    getIt.registerSingleton<ICourseRepository>(CourseRepository(db));
    getIt.registerSingleton<ReviewHistoryDao>(ReviewHistoryDao(db));
    getIt.registerSingleton<AnkiNoteDao>(AnkiNoteDao(db));
    getIt.registerSingleton<AnkiImportDao>(AnkiImportDao(db));

    settingsProvider = SettingsProvider(appPrefs);
    courseProvider = CourseProvider(appPrefs);
    final linkStore = LessonLinkStore(appPrefs);
    final srsDao = SrsStateDao(db);
    srsProvider = SrsProvider(appPrefs, linkStore, srsDao);
    aiConfigHolder = AiEngineConfigHolder();

    getIt.registerSingleton<CourseProvider>(courseProvider);
    getIt.registerSingleton<SrsProvider>(srsProvider);
    getIt.registerSingleton<AnkiDeckManager>(
      AnkiDeckManager(
        repo: getIt<ICourseRepository>(),
        srsProvider: srsProvider,
        importDao: getIt<AnkiImportDao>(),
        noteDao: getIt<AnkiNoteDao>(),
        appPrefs: appPrefs,
      ),
    );

    CourseLoader.overrideDatabase(() => db);
  });

  tearDown(() async {
    CourseLoader.clearDatabaseOverride();
    await db.close();
    GetIt.instance.reset();
  });

  testWidgets('AnkiImportPage: sample deck loads preview, user can inspect settings, then imports successfully', (tester) async {
    tester.view.physicalSize = const Size(1080, 1920);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<SettingsProvider>.value(value: settingsProvider),
          ChangeNotifierProvider<CourseProvider>.value(value: courseProvider),
          ChangeNotifierProvider<SrsProvider>.value(value: srsProvider),
          ChangeNotifierProvider<AiEngineConfigHolder>.value(value: aiConfigHolder),
        ],
        child: const MaterialApp(
          home: AnkiImportPage(startWithSample: true),
        ),
      ),
    );

    // Initial frame + post-frame callback loading sample deck
    await tester.pump();
    await tester.pumpAndSettle();

    // 1. Verify we are in Step 2: Preview (NOT skipped to done!)
    expect(find.text(AppStrings.ankiPreviewSectionContent), findsOneWidget);
    expect(find.text(AppStrings.ankiPreviewStartImport), findsOneWidget);

    // 2. User taps "开始导入"
    await tester.tap(find.text(AppStrings.ankiPreviewStartImport));
    await tester.pumpAndSettle();

    // 3. Verify we are in Step 4: Done
    expect(find.text(AppStrings.ankiImportComplete), findsOneWidget);
    expect(find.text(AppStrings.ankiStartLearning), findsOneWidget);

    // 4. Verify the deck is created in CourseProvider
    expect(courseProvider.ankiDeckEntries.isNotEmpty, isTrue);
    expect(courseProvider.courseEntries.any((e) => !e.isBuiltin), isTrue);
  });
}
