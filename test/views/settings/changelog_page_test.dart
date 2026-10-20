// Widget test: parsing + asset loading for ChangelogFromAsset.
//
// rootBundle / PlatformAssetBundle 通过 raw bytes 发送 `flutter/assets`
// 消息,不是 method call,因此测试必须用 `setMockMessageHandler` 而不是
// `setMockMethodCallHandler`。返回 `ByteData.sublistView(utf8.encode(md))`
// 才能让 widget 拿到非空 markdown。

import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:turna/l10n/app_strings.dart';
import 'package:turna/views/settings/changelog_page.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const fakeChangelog = '''
# Changelog

---

## 1.1.0 - 间隔重复与 AI 引擎升级 (2026-07-30)

- FSRS 连续记忆模型与本地参数优化
- Anki 智能牌组归类与牌型渲染重构
- AI 引擎刷新

---

## 1.0.0 - 土耳其语转向 (2026-07-29)

- 界面文案全面中文化
- Anki 牌组导入
- 课内 AI 提示助手

---

## 0.4.x - 体验与可访问性 (2026-07-11)

- 暗色 / 亮色 / 跟随系统主题
- 字体大小、减弱动效

---
''';

  Future<ByteData?> okHandler(ByteData? message) async {
    return ByteData.sublistView(utf8.encode(fakeChangelog));
  }

  Future<ByteData?> failHandler(ByteData? message) async {
    return null;
  }

  Future<void> installHandler(
      Future<ByteData?> Function(ByteData?) handler) async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMessageHandler('flutter/assets', handler);
  }

  setUp(() {
    rootBundle.clear();
  });

  test('parseChangelogMarkdown extracts at least 3 releases', () {
    final releases = parseChangelogMarkdown(fakeChangelog);
    expect(releases.length, greaterThanOrEqualTo(3));
    expect(releases.first.version, '1.1.0');
    expect(releases.first.title, contains('AI'));
    expect(releases.first.items.length, greaterThanOrEqualTo(3));
  });

  test('parseChangelogMarkdown ignores empty / separator lines', () {
    final releases =
        parseChangelogMarkdown('# Top\n\n---\n\n## 9.9.9 - Hi\n- only');
    expect(releases.length, 1);
    expect(releases.first.version, '9.9.9');
    expect(releases.first.title, 'Hi');
    expect(releases.first.items, ['only']);
  });

  // 阶段数文案此前硬编码「从原型到 0.9 的 9 个阶段」，每加一个里程碑
  // 就会立刻说谎。改为从 journeySteps 派生后，这条断言把它钉住：
  // 阶段数与终点版本必须与数据源一致，不能各写各的。
  test('journey overview text is derived from journeySteps', () {
    const steps = ChangelogPage.journeySteps;
    expect(steps, isNotEmpty);
    final expected = 'Varnamala Plus 从原型到 ${steps.last.label} 的 '
        '${steps.length} 个阶段';
    expect(expected, contains('${steps.length} 个阶段'));
    expect(expected, contains(steps.last.label));
  });

  // 应用内 changelog 有两个来源：assets/changelog.md（主）与
  // ReleaseManifest.fallbackReleases（asset 加载失败时的后援）。
  // 两者的**首个 release id 必须一致**——否则用户在「asset 读得到」和
  // 「asset 读不到」两种状态下会看到不同的最新版。
  test('bundled changelog and fallback manifest agree on the latest release',
      () {
    final bundled = parseChangelogMarkdown(
      File('assets/changelog.md').readAsStringSync(),
    );
    expect(bundled, isNotEmpty, reason: 'assets/changelog.md 解析为空');
    expect(
      bundled.first.version,
      ChangelogPage.fallbackReleases.first.version,
      reason: 'assets/changelog.md 与 ReleaseManifest.fallbackReleases '
          '的首个 release id 不一致',
    );
  });

  testWidgets('ChangelogFromAsset falls back to legacy releases on load error',
      (tester) async {
    await installHandler(failHandler);
    await tester.pumpWidget(
      MaterialApp(
        home: ChangelogFromAsset(
          assetPath: 'assets/does_not_exist.md',
          showFallbackBanner: true,
          fallbackReleases: ChangelogPage.fallbackReleases,
        ),
      ),
    );
    for (var i = 0; i < 5; i++) {
      await tester.runAsync(() => Future<void>.delayed(Duration.zero));
      await tester.pump();
    }
    // Same reasoning as the asset test: the journey card's height scales with
    // the number of milestones, so the older fallback cards may start below
    // the fold. Scroll to them instead of assuming they are on screen.
    await tester.scrollUntilVisible(
      find.text('0.5'),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.text('0.5'), findsWidgets);
    await tester.scrollUntilVisible(
      find.text('0.4'),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.text('0.4'), findsWidgets);
  });

  testWidgets('ChangelogFromAsset renders parsed releases from asset',
      (tester) async {
    await installHandler(okHandler);
    await tester.pumpWidget(
      MaterialApp(
        home: ChangelogFromAsset(
          assetPath: 'assets/changelog.md',
          showFallbackBanner: false,
          fallbackReleases: const [],
        ),
      ),
    );
    for (var i = 0; i < 5; i++) {
      await tester.runAsync(() => Future<void>.delayed(Duration.zero));
      await tester.pump();
    }
    final releases = parseChangelogMarkdown(fakeChangelog);
    expect(releases.length, 3);
    // Scroll both later cards into the tree before asserting. The journey
    // overview card grows with every released milestone (one row per step),
    // so a release card that used to sit in the first screen is pushed out
    // of the default 800x600 viewport as soon as a version is added. Asserting
    // on "is it rendered at all" must not depend on how tall that card is.
    await tester.scrollUntilVisible(
      find.text('1.1.0'),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.text('1.1.0'), findsWidgets);
    // Scroll until 1.0.0 card becomes part of the rendered widget tree
    // (default test viewport is 800x600; production journey + first release
    // card may push later cards beyond the ListView cacheExtent).
    await tester.scrollUntilVisible(
      find.text('1.0.0'),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.text('1.0.0'), findsWidgets);
  });

  test('parseChangelogMarkdown returns empty list when no sections', () {
    expect(parseChangelogMarkdown('# only h1\nno sections here'), isEmpty);
  });

  // 「一键复制」：Clipboard.setData 走 platform method channel，用
  // setMockMethodCallHandler 捕获，避免真实剪贴板。
  testWidgets('一键复制 copies the rendered asset markdown', (tester) async {
    await installHandler(okHandler);
    String? copied;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, (call) async {
      if (call.method == 'Clipboard.setData') {
        copied = (call.arguments as Map?)?['text'] as String?;
      }
      return null;
    });
    addTearDown(() {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(SystemChannels.platform, null);
    });

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ChangelogFromAsset(
            assetPath: 'assets/changelog.md',
            fallbackReleases: const [],
          ),
        ),
      ),
    );
    for (var i = 0; i < 5; i++) {
      await tester.runAsync(() => Future<void>.delayed(Duration.zero));
      await tester.pump();
    }
    await tester.scrollUntilVisible(
      find.text(AppStrings.changelogCopyButton),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.tap(find.text(AppStrings.changelogCopyButton));
    await tester.pump();

    // 复制的是 asset 原文（当前实际展示内容），不是内置后援。
    expect(copied, isNotNull);
    expect(copied, contains('# Changelog'));
    expect(copied, contains('1.1.0'));
    expect(find.text(AppStrings.changelogCopied), findsOneWidget);
  });

  testWidgets('一键复制 falls back to built-in releases on load error',
      (tester) async {
    await installHandler(failHandler);
    String? copied;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, (call) async {
      if (call.method == 'Clipboard.setData') {
        copied = (call.arguments as Map?)?['text'] as String?;
      }
      return null;
    });
    addTearDown(() {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(SystemChannels.platform, null);
    });

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ChangelogFromAsset(
            assetPath: 'assets/does_not_exist.md',
            fallbackReleases: ChangelogPage.fallbackReleases,
          ),
        ),
      ),
    );
    for (var i = 0; i < 5; i++) {
      await tester.runAsync(() => Future<void>.delayed(Duration.zero));
      await tester.pump();
    }
    await tester.scrollUntilVisible(
      find.text(AppStrings.changelogCopyButton),
      400,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.tap(find.text(AppStrings.changelogCopyButton));
    await tester.pump();

    // 后援拼接文本含历程与最新版本 0.8。
    expect(copied, isNotNull);
    expect(copied, contains('## 更新历程'));
    expect(copied, contains('### 0.8 —'));
    expect(find.text(AppStrings.changelogCopied), findsOneWidget);
  });
}
