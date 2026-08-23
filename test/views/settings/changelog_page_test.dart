// Widget test: parsing + asset loading for ChangelogFromAsset.
//
// rootBundle / PlatformAssetBundle 通过 raw bytes 发送 `flutter/assets`
// 消息,不是 method call,因此测试必须用 `setMockMessageHandler` 而不是
// `setMockMethodCallHandler`。返回 `ByteData.sublistView(utf8.encode(md))`
// 才能让 widget 拿到非空 markdown。

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
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
    expect(find.text('0.5'), findsWidgets);
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
}
