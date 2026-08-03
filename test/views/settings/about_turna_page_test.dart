// Widget test: AboutTurnaPage renders three tabs and the brand header.
//
// rootBundle / PlatformAssetBundle 通过 raw bytes 发送 `flutter/assets`
// 消息,不是 method call,因此测试必须用 `setMockMessageHandler` 而不是
// `setMockMethodCallHandler`。返回 `ByteData.sublistView(utf8.encode(md))`
// 才能让 widget 拿到非空 markdown。

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:turna/views/settings/about_turna_page.dart';
import 'package:turna/views/settings/beginner_guide_page.dart';
import 'package:turna/views/settings/changelog_page.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const minimalChangelog = '''
# Changelog

## 1.1.0 - 标题 A
- 第一条
- 第二条

## 1.0.0 - 标题 B
- 一条
''';

  const minimalQuickStart = '''
# Quick Start

## 1. 简介
- 说明
''';

  Future<ByteData?> assetsHandler(ByteData? message) async {
    final key =
        message == null ? '' : utf8.decode(message.buffer.asUint8List());
    if (key.endsWith('changelog.md')) {
      return ByteData.sublistView(utf8.encode(minimalChangelog));
    }
    if (key.endsWith('quick_start.md')) {
      return ByteData.sublistView(utf8.encode(minimalQuickStart));
    }
    return null;
  }

  Future<void> installHandler(
      Future<ByteData?> Function(ByteData?) handler) async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMessageHandler('flutter/assets', handler);
  }

  setUp(() {
    TestWidgetsFlutterBinding.ensureInitialized();
  });

  testWidgets('AboutTurnaPage shows 3 tabs and brand header', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: AboutTurnaPage(),
      ),
    );
    for (var i = 0; i < 5; i++) {
      await tester.runAsync(() => Future<void>.delayed(Duration.zero));
      await tester.pump();
    }

    expect(find.byType(TabBar), findsOneWidget);
    expect(find.text('关于'), findsOneWidget);
    expect(find.text('更新日志'), findsOneWidget);
    expect(find.text('使用指南'), findsOneWidget);
    expect(find.byType(TabBarView), findsOneWidget);
  });

  testWidgets('About page switch to changelog tab renders release cards',
      (tester) async {
    await installHandler(assetsHandler);
    await tester.pumpWidget(
      const MaterialApp(
        home: AboutTurnaPage(),
      ),
    );
    for (var i = 0; i < 5; i++) {
      await tester.runAsync(() => Future<void>.delayed(Duration.zero));
      await tester.pump();
    }

    // TabBarView 切换 + ChangelogFromAsset 加载需要更长异步链。
    // 直接通过 DefaultTabController 切换 index,避免点击坐标导致的歧义。
    final tabBar = find.byType(TabBar);
    expect(tabBar, findsOneWidget);
    final tabs = tester.widget<TabBar>(tabBar).tabs;
    await tester.tap(find.text('更新日志').last);
    for (var i = 0; i < 20; i++) {
      await tester.runAsync(() => Future<void>.delayed(Duration.zero));
      await tester.pump();
    }
    // 触发 TabBarView 切换动画完成。
    await tester.pumpAndSettle(const Duration(seconds: 1));

    // 验证 changelog tab 下 release 卡片渲染了。
    expect(find.byType(ChangelogReleaseCard), findsWidgets);
    // 至少看到 1.1.0 这个版本号。
    expect(find.text('1.1.0'), findsWidgets);
    // 锚点 tab 仍然存在。
    expect(tabs.length, 3);
  });

  testWidgets('About page switch to quick start tab renders sections',
      (tester) async {
    await installHandler(assetsHandler);
    await tester.pumpWidget(
      const MaterialApp(
        home: AboutTurnaPage(),
      ),
    );
    for (var i = 0; i < 5; i++) {
      await tester.runAsync(() => Future<void>.delayed(Duration.zero));
      await tester.pump();
    }

    await tester.tap(find.text('使用指南').last);
    for (var i = 0; i < 20; i++) {
      await tester.runAsync(() => Future<void>.delayed(Duration.zero));
      await tester.pump();
    }
    await tester.pumpAndSettle(const Duration(seconds: 1));

    // 验证 quick start tab 下 QuickStartFromAsset 已渲染并解析出 section。
    expect(find.byType(QuickStartFromAsset), findsOneWidget);
    expect(find.text('简介'), findsWidgets);
  });
}
