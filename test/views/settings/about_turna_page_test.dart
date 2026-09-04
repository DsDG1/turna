// Widget tests: AboutTurnaPage two-tab structure (关于/更新日志), version
// from AppBuildInfo (no hardcoded fallback), and registry-driven external
// links that render disabled-with-reason when unconfigured (Plan 2 §4.7/§7).

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:turna/application/settings/app_build_info.dart';
import 'package:turna/application/settings/external_link_registry.dart';
import 'package:turna/l10n/app_strings.dart';
import 'package:turna/views/settings/about_turna_page.dart';
import 'package:turna/views/settings/changelog_page.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const minimalChangelog = '''
# Changelog

## 0.7 - 标题 A
- 第一条
- 第二条

## 0.6 - 标题 B
- 一条
''';

  Future<ByteData?> assetsHandler(ByteData? message) async {
    final key =
        message == null ? '' : utf8.decode(message.buffer.asUint8List());
    if (key.endsWith('changelog.md')) {
      return ByteData.sublistView(utf8.encode(minimalChangelog));
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

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMessageHandler('flutter/assets', null);
  });

  testWidgets('about page shows exactly two tabs; usage guide removed',
      (tester) async {
    await tester.pumpWidget(
      MaterialApp(home: AboutTurnaPage(buildInfo: AppBuildInfo.testInstance)),
    );
    await tester.pump();

    final tabBar = find.byType(TabBar);
    expect(tabBar, findsOneWidget);
    expect(tester.widget<TabBar>(tabBar).tabs.length, 2);
    expect(find.text('关于'), findsOneWidget);
    expect(find.text('更新日志'), findsOneWidget);
    expect(find.text('使用指南'), findsNothing);
  });

  testWidgets('unconfigured external links render disabled with a reason',
      (tester) async {
    // Default registry: all URLs null (not confirmed yet per Plan 2 §0.1).
    await tester.pumpWidget(
      MaterialApp(home: AboutTurnaPage(buildInfo: AppBuildInfo.testInstance)),
    );
    await tester.pump();

    // The old hardcoded rshrc/Varnamala URLs must not appear anywhere.
    expect(find.textContaining('rshrc'), findsNothing);
    expect(find.textContaining('github.com'), findsNothing);

    // Disabled links explain themselves instead of dead-tapping.
    expect(find.text(AppStrings.externalLinkNotConfigured), findsWidgets);
    expect(find.byIcon(Icons.lock_outline_rounded), findsWidgets);

    // Tapping an unconfigured link shows the reason, never a launch attempt.
    await tester.tap(find.text(AppStrings.aboutUpstreamTitle));
    await tester.pump();
    expect(find.text(AppStrings.externalLinkNotConfigured), findsWidgets);
  });

  testWidgets('configured links become enabled', (tester) async {
    // Inject a configured registry — the page uses the default one, so
    // assert the descriptor-level contract instead (the page wires the same
    // registry through).
    const registry = ExternalLinkRegistry();
    final descriptor = registry.describe(ExternalLinkId.projectHome);
    expect(descriptor.enabled, isFalse);
    expect(descriptor.uri, isNull);

    const configured = ExternalLinkRegistry(
      urls: {
        ExternalLinkId.projectHome: 'https://turna.example.org',
        ExternalLinkId.issueTracker: 'http://evil.example.com',
      },
    );
    final home = configured.describe(ExternalLinkId.projectHome);
    expect(home.enabled, isTrue);
    expect(home.uri?.scheme, 'https');

    // Non-https (and non-loopback http) is rejected by the scheme guard.
    final evil = configured.describe(ExternalLinkId.issueTracker);
    expect(evil.enabled, isFalse,
        reason: 'http to a public host must be rejected');
  });

  testWidgets('version comes from AppBuildInfo with no hardcoded fallback',
      (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: AboutTurnaPage(
          buildInfo: const AppBuildInfo(versionName: '9.9.9', buildNumber: ''),
        ),
      ),
    );
    await tester.pump();

    expect(find.textContaining('9.9.9'), findsWidgets);
    expect(find.textContaining('0.7.0'), findsNothing,
        reason: 'no hardcoded fallback version may leak into the header');
  });

  testWidgets('changelog tab renders release cards from the asset',
      (tester) async {
    await installHandler(assetsHandler);
    await tester.pumpWidget(
      MaterialApp(home: AboutTurnaPage(buildInfo: AppBuildInfo.testInstance)),
    );
    await tester.pump();

    await tester.tap(find.text('更新日志').last);
    for (var i = 0; i < 20; i++) {
      await tester.runAsync(() => Future<void>.delayed(Duration.zero));
      await tester.pump();
    }
    await tester.pumpAndSettle(const Duration(seconds: 1));

    // v0.8 的「更新历程」卡片增至 8 个阶段后加高了首屏，release 卡片
    // 落到首屏之下——默认 finder 会跳过 offstage 子树。这里断言的语义
    // 是「资产内容已渲染成卡片」，用 skipOffstage:false 而非「在首屏内」。
    expect(
      find.byType(ChangelogReleaseCard, skipOffstage: false),
      findsWidgets,
    );
    // Asset now uses the unified 0.x numbering, matching the manifest.
    expect(find.text('0.7', skipOffstage: false), findsWidgets);
    expect(find.text('1.1.0', skipOffstage: false), findsNothing,
        reason: 'legacy 1.x ids must be renumbered to the 0.x scheme');
  });
}
