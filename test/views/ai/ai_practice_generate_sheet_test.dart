// Dart imports:
import 'dart:convert';

// Flutter imports:
import 'package:flutter/material.dart';

// Package imports:
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:streaming_shared_preferences/streaming_shared_preferences.dart';

// Project imports:
import 'package:turna/application/ai/ai_grounded_resource_provider.dart';
import 'package:turna/application/ai/engine/ai_cache.dart';
import 'package:turna/application/ai/engine/ai_engine.dart';
import 'package:turna/application/ai/engine/ai_engine_config.dart';
import 'package:turna/application/ai/engine/ai_engine_config_holder.dart';
import 'package:turna/application/ai/engine/ai_http_client.dart';
import 'package:turna/application/ai/engine/ai_provider_preset.dart';
import 'package:turna/application/ai/practice/ai_course_presets.dart';
import 'package:turna/application/ai/practice/ai_practice_generator.dart';
import 'package:turna/application/ai/practice/ai_practice_job_queue.dart';
import 'package:turna/application/ai/practice/ai_practice_source_context.dart';
import 'package:turna/application/language_provider.dart';
import 'package:turna/di/injection.dart';
import 'package:turna/domain/ai/ai_course.dart';
import 'package:turna/domain/repositories/i_ai_practice_repository.dart';
import 'package:turna/l10n/app_strings.dart';
import 'package:turna/service/locator.dart';
import 'package:turna/views/ai/components/ai_practice_generate_sheet.dart';
import 'package:turna/views/widgets/turna_sheet.dart';

class _InMemoryPracticeRepo implements IAiPracticeRepository {
  final Map<String, AiCourse> courses = {};

  @override
  Future<AiCourse?> byId(String id) async => courses[id];

  @override
  Future<void> deleteMany(Iterable<String> ids) async {
    for (final id in ids) {
      courses.remove(id);
    }
  }

  @override
  Future<List<AiCourse>> list({String? languageCode, int? limit}) async =>
      courses.values.toList();

  @override
  Future<int> markInterruptedOnStartup() async => 0;

  @override
  Future<int> pruneExpired({required DateTime now}) async => 0;

  @override
  Future<void> setPinned(
    Iterable<String> ids, {
    required bool pinned,
    DateTime? now,
  }) async {}

  @override
  Future<void> upsertCourse(AiCourse course) async {
    courses[course.id] = course;
  }

  @override
  Future<void> upsertVersion(AiCourseVersion version) async {}
}

class _StubSourceContext implements AiPracticeSourceContextBuilder {
  @override
  Future<String> build(AiPracticeSource kind) async => '';
}

http.Response _outlineResponse() {
  final outline = {
    'id': 'ai-outline-1',
    'name': '咖啡馆点单',
    'description': '日常点单',
    'words': [
      {'id': 'w1', 'term': 'çay', 'translation': '茶'},
      {'id': 'w2', 'term': 'hesap', 'translation': '账单'},
    ],
    'expressions': const <dynamic>[],
    'grammarPoints': const <dynamic>[],
    'units': [
      {
        'id': 'u1',
        'name': '第一单元：点饮品',
        'lessons': [
          {
            'id': 'l1',
            'name': '认识饮品词',
            'template': 'intro',
            'targetWordIds': ['w1'],
          },
          {
            'id': 'l2',
            'name': '结账表达',
            'template': 'dialogue',
            'targetWordIds': ['w2'],
          },
        ],
      },
    ],
  };
  final body = jsonEncode({
    'choices': [
      {
        'finish_reason': 'stop',
        'message': {'role': 'assistant', 'content': jsonEncode(outline)},
      },
    ],
  });
  return http.Response.bytes(
    utf8.encode(body),
    200,
    headers: {'content-type': 'application/json; charset=utf-8'},
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late AppPrefs prefs;
  late LanguageProvider languageProvider;
  late AiEngineConfigHolder configHolder;
  late AiPracticeJobQueue queue;
  late _InMemoryPracticeRepo repo;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    final sp = await StreamingSharedPreferences.instance;
    prefs = AppPrefs(sp);
    getIt.registerLazySingleton<AppPrefs>(() => prefs);

    languageProvider = LanguageProvider(prefs);
    configHolder = AiEngineConfigHolder();
    await configHolder.updateConfig(
      const AiEngineConfig(
        preset: kCustomPreset,
        apiKey: 'k-test',
        modelChat: 'm',
        modelJson: 'm',
        customBaseUrl: 'https://example.test/v1',
        cacheEnabled: false,
      ),
    );

    repo = _InMemoryPracticeRepo();
    final engine = AiEngine(
      AiHttpClient.withClient(MockClient((_) async => _outlineResponse())),
      AiCache.forTest(maxEntries: 0, enabled: false),
    );
    queue = AiPracticeJobQueue(
      repo,
      AiPracticeGenerator(engine, AiGroundedResourceProvider.detached()),
      _StubSourceContext(),
      configHolder,
      languageProvider,
    );
  });

  tearDown(() {
    getIt.reset();
  });

  Future<void> pumpCustomSheet(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<LanguageProvider>.value(
            value: languageProvider,
          ),
          ChangeNotifierProvider<AiEngineConfigHolder>.value(
            value: configHolder,
          ),
          ChangeNotifierProvider<AiPracticeJobQueue>.value(value: queue),
        ],
        child: MaterialApp(
          home: Scaffold(
            body: TurnaSheetPanel(
              title: AppStrings.aiPracticeGenerateTitle,
              body: const AiPracticeGenerateSheet(initialCustomMode: true),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets(
      'custom course sheet renders presets, expanded controls, and advanced options',
      (tester) async {
    await pumpCustomSheet(tester);

    // All 5 presets are visible.
    for (final preset in AiCoursePresets.all) {
      expect(find.text(preset.label), findsOneWidget);
    }

    // Target language, source language, density, and outline preview CTA exist.
    expect(
        find.text(AppStrings.aiPracticeCustomTargetLanguage), findsOneWidget);
    expect(
        find.text(AppStrings.aiPracticeCustomSourceLanguage), findsOneWidget);
    expect(find.text(AppStrings.aiPracticeItemsPerLesson), findsOneWidget);
    expect(find.text(AppStrings.aiPracticePreviewOutline), findsOneWidget);

    // Tap preset "强化刷题" -> updates units=3, lessons=3, template=综合测验.
    await tester.tap(find.text('强化刷题'));
    await tester.pumpAndSettle();
    expect(find.text(AppStrings.aiPracticeTemplateMastery), findsOneWidget);
    expect(find.text(AppStrings.aiPracticeDensityIntensive), findsOneWidget);

    // Open units picker and verify expanded 1..10 range.
    await tester.tap(find.text(AppStrings.aiPracticeCustomUnits));
    await tester.pumpAndSettle();
    expect(find.text('10'), findsOneWidget);
    await tester.tap(find.text('5'));
    await tester.pumpAndSettle();

    // 5 units * 3 lessons = 15 > 12 -> shows large-course checkpoint hint.
    expect(find.text(AppStrings.aiPracticeLargeCourseHint), findsOneWidget);

    // Expand advanced options -> shows preferred types, focus items, explain toggle.
    await tester.tap(find.text(AppStrings.aiPracticeAdvancedToggle));
    await tester.pumpAndSettle();
    expect(find.text(AppStrings.aiPracticePreferredTypes), findsOneWidget);
    expect(find.text(AppStrings.aiPracticeFocusItems), findsOneWidget);
    expect(find.text(AppStrings.aiPracticeExplainToggle), findsOneWidget);
  });

  testWidgets('two-step outline preview opens editable AiOutlineReviewSheet',
      (tester) async {
    await pumpCustomSheet(tester);

    // Fill required topic.
    await tester.enterText(find.byType(TextField).first, '咖啡馆点单');
    await tester.pumpAndSettle();

    // Tap "先审大纲再生成".
    await tester.tap(find.text(AppStrings.aiPracticePreviewOutline));
    await tester.pump();
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 100)),
    );
    await tester.pumpAndSettle();

    // Outline review sheet is shown with units, lessons, words, and confirm CTA.
    expect(find.text(AppStrings.aiOutlineReviewTitle), findsOneWidget);
    expect(find.text('çay · 茶'), findsOneWidget);
    expect(find.text(AppStrings.aiOutlineConfirmGenerate(2)), findsOneWidget);
  });
}
