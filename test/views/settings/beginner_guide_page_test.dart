// Widget test: parsing + asset loading for QuickStartFromAsset.
//
// rootBundle / PlatformAssetBundle 通过 raw bytes 发送 `flutter/assets`
// 消息,不是 method call,因此测试必须用 `setMockMessageHandler` 而不是
// `setMockMethodCallHandler`。返回 `ByteData.sublistView(utf8.encode(md))`
// 才能让 widget 拿到非空 markdown。

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:turna/application/guide_return_controller.dart';
import 'package:turna/di/injection.dart';
import 'package:turna/l10n/app_strings.dart';
import 'package:turna/service/tab_router.dart';
import 'package:turna/views/settings/beginner_guide_page.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const fakeQuickStart = '''
# Turna 使用指南

---

## 1. 课程结构

- Section → Unit → Lesson → Stage
- 8 个 CEFR 等级

---

## 2. 6 种课型模板

- intro / practice / listening / reading / review / mastery

---

## 3. 间隔重复

> 你不需要记"今天要复习哪些词"。
- 打开 App 看到 SRS 队列
- 看到几张就复习几张

---

## 4. 错题与弱词

- 错题本 FIFO
- 弱词复习 10 题
''';

  Future<ByteData?> okHandler(ByteData? message) async {
    return ByteData.sublistView(utf8.encode(fakeQuickStart));
  }

  Future<ByteData?> failHandler(ByteData? message) async {
    return null;
  }

  Future<void> installHandler(
      Future<ByteData?> Function(ByteData?) handler) async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMessageHandler('flutter/assets', handler);
  }

  test('parseQuickStartMarkdown extracts 4 sections with right titles', () {
    final sections = parseQuickStartMarkdown(fakeQuickStart);
    expect(sections.length, 4);
    expect(sections[0].number, '1.');
    expect(sections[0].title, '课程结构');
    expect(sections[1].title, '6 种课型模板');
    expect(sections[2].title, '间隔重复');
    expect(sections[3].title, '错题与弱词');
  });

  test('parseQuickStartMarkdown joins non-list lines as paragraphs', () {
    final sections = parseQuickStartMarkdown(fakeQuickStart);
    // 第 3 节"间隔重复"包含 `>` 引用块,会被当成一段 paragraph 渲染。
    expect(sections[2].paragraphs.length, greaterThanOrEqualTo(1));
    expect(sections[2].paragraphs.first, contains('不需要记'));
  });

  test('parseQuickStartMarkdown returns empty when no sections', () {
    expect(parseQuickStartMarkdown('# top\nplain text'), isEmpty);
  });

  testWidgets('QuickStartFromAsset renders sections from asset',
      (tester) async {
    await installHandler(okHandler);
    await tester.pumpWidget(
      const MaterialApp(home: QuickStartFromAsset()),
    );
    for (var i = 0; i < 5; i++) {
      await tester.runAsync(() => Future<void>.delayed(Duration.zero));
      await tester.pump();
    }
    expect(find.text('课程结构'), findsWidgets);
    expect(find.text('6 种课型模板'), findsWidgets);
    expect(find.text('间隔重复'), findsWidgets);
    expect(find.text('错题与弱词'), findsWidgets);
  });

  testWidgets('QuickStartFromAsset shows fallback when asset missing',
      (tester) async {
    // handler 返回 null 模拟 asset 读取失败。fallback 文本固定为
    // "无法读取 assets/quick_start.md"(AppStrings.quickStartLoadFallback),
    // 因此这里直接断言该字符串出现。
    await installHandler(failHandler);
    await tester.pumpWidget(
      const MaterialApp(
        home: QuickStartFromAsset(assetPath: 'assets/quick_start_missing.md'),
      ),
    );
    for (var i = 0; i < 20; i++) {
      await tester.runAsync(() => Future<void>.delayed(Duration.zero));
      await tester.pump();
    }
    // asset 返回 null 触发 load 抛错 → 显示 fallback 文本。
    expect(find.text(AppStrings.quickStartLoadFallback), findsWidgets);
  });

  testWidgets('BeginnerGuidePage is compact: feature titles, no quick-start',
      (tester) async {
    await getIt.reset();
    getIt.registerLazySingleton<GuideReturnController>(
      () => GuideReturnController(),
    );
    getIt.registerLazySingleton<TabRouter>(() => TabRouter());
    addTearDown(() async => getIt.reset());

    await tester.pumpWidget(
      const MaterialApp(home: BeginnerGuidePage()),
    );
    await tester.pumpAndSettle();

    // Compact guide: feature titles + try-now pills are present.
    expect(find.text(AppStrings.beginnerGuideTitle), findsWidgets);
    expect(find.text(AppStrings.beginnerGuideLearnTitle), findsOneWidget);
    expect(find.text(AppStrings.beginnerGuideTryNow), findsWidgets);
    // Long-form markdown helper is not embedded on this page.
    expect(find.byType(QuickStartFromAsset), findsNothing);
  });
}
