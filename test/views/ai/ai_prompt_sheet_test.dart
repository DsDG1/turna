// Flutter imports:
import 'package:flutter/material.dart';

// Package imports:
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:streaming_shared_preferences/streaming_shared_preferences.dart';

// Project imports:
import 'package:turna/application/ai/ai_explain_prefs.dart';
import 'package:turna/application/ai/ai_prompt_catalog.dart';
import 'package:turna/application/ai/ai_prompt_overrides.dart';
import 'package:turna/application/language_provider.dart';
import 'package:turna/di/injection.dart';
import 'package:turna/l10n/app_strings.dart';
import 'package:turna/service/locator.dart';
import 'package:turna/views/ai/ai_prompt_sheet.dart';

/// 系统提示词面板：默认文本可见、可复制，自定义只追加。
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late AppPrefs prefs;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    final sp = await StreamingSharedPreferences.instance;
    prefs = AppPrefs(sp);
    getIt.registerLazySingleton<AppPrefs>(() => prefs);
    AiPromptOverridesStore.resetFallbackForTest();
  });

  tearDown(() {
    getIt.reset();
    AiPromptOverridesStore.resetFallbackForTest();
  });

  Future<void> pumpSheet(WidgetTester tester) async {
    // 面板内容较高（提示词 + 编辑器 + 按钮）。给一个高窗口，避免 ListView
    // 惰性构建把下方按钮漏掉导致点不到。
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      ChangeNotifierProvider<LanguageProvider>(
        create: (_) => LanguageProvider(prefs),
        child: const MaterialApp(
          home: Scaffold(body: AiPromptSheet()),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('shows the effective default prompt and the runtime notice',
      (tester) async {
    await pumpSheet(tester);

    expect(find.text(AppStrings.aiPromptSheetTitle), findsOneWidget);
    // 每个功能都能切到；首屏是自由问答。
    for (final f in AiPromptFeature.values) {
      expect(find.text(f.label), findsWidgets, reason: '缺少功能芯片 ${f.label}');
    }
    // 生效版本里必须能看到默认提示词的开头（SelectableText 拼接成一段）。
    expect(
      find.textContaining('language-learning companion'),
      findsOneWidget,
    );
    expect(find.text(AppStrings.aiPromptUsingDefault), findsOneWidget);
  });

  testWidgets('saving an override persists it and keeps the default text',
      (tester) async {
    await pumpSheet(tester);

    await tester.enterText(find.byType(TextField), '先给例句再解释。');
    await tester.pumpAndSettle();

    await tester.tap(find.text(AppStrings.aiPromptSave));
    await tester.pumpAndSettle();

    final store = AiPromptOverridesStore.resolve();
    expect(store.textFor(AiPromptFeature.freeChat), '先给例句再解释。');

    // 生效版本 = 默认 + 追加，两者同时在场。
    final prompt = AiPromptCatalog.preview(
      feature: AiPromptFeature.freeChat,
      language: 'Turkish',
      prefs: const AiExplainPrefsSnapshot(),
      override: store.textFor(AiPromptFeature.freeChat),
    );
    expect(prompt, contains('language-learning companion'));
    expect(prompt, contains('先给例句再解释。'));

    // 恢复默认清空覆盖，但默认提示词仍在。
    await tester.tap(find.text(AppStrings.aiPromptResetDefault));
    await tester.pumpAndSettle();
    expect(store.textFor(AiPromptFeature.freeChat), '');
  });
}
