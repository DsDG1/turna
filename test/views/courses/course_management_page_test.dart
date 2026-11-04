// Widget tests for the course-management page: catalog rendering with meta
// info, and the opt-in visibility of the read-aloud entry in the card menu.

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:streaming_shared_preferences/streaming_shared_preferences.dart';
import 'package:turna/application/course_catalog.dart';
import 'package:turna/application/course_provider.dart';
import 'package:turna/application/settings_provider.dart';
import 'package:turna/domain/course/course_scope.dart';
import 'package:turna/l10n/app_strings.dart';
import 'package:turna/service/locator.dart';
import 'package:turna/views/courses/course_management_page.dart';
import 'package:turna/core/theme.dart';

/// Only what the management page reads: the catalog and the active wire.
class _FakeCourseProvider extends CourseProvider {
  _FakeCourseProvider(this.entries, this.activeWire);

  final List<CourseCatalogEntry> entries;
  final String activeWire;

  @override
  List<CourseCatalogEntry> get catalogEntries => entries;

  @override
  String get courseScope => activeWire;

  @override
  Future<void> setScope(CourseScope next) async {}

  @override
  Future<void> reloadCourse() async {}

  @override
  Future<void> persistCourseOrder(List<String> wires) async {}
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late AppPrefs prefs;
  late SettingsProvider settings;

  final builtinEntry = CourseCatalogEntry(
    scope: const BuiltinCourseScope('turkish'),
    displayName: 'Builtin Turkish',
    isBuiltin: true,
  );
  final secondBuiltinEntry = CourseCatalogEntry(
    scope: const BuiltinCourseScope('japanese'),
    displayName: 'Builtin Japanese',
    isBuiltin: true,
    cardCount: 1204,
  );
  final officialAnkiEntry = CourseCatalogEntry(
    scope: const OfficialAnkiCourseScope(
      profileId: 'p1',
      sourceId: 'src-anki-1',
    ),
    displayName: '记忆卡牌组 A',
    isBuiltin: false,
    officialSourceId: 'src-anki-1',
    cardCount: 800,
  );

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    final streaming = await StreamingSharedPreferences.instance;
    prefs = AppPrefs(streaming);
    settings = SettingsProvider(prefs);
    // StreamingSharedPreferences is a singleton across tests in one file —
    // force a known starting point for the gate instead of relying on the
    // (possibly dirty) cached store.
    await settings.setTtsFeatureEnabled(false);
  });

  Future<void> pumpPage(WidgetTester tester) {
    final courses = _FakeCourseProvider(
      [builtinEntry, secondBuiltinEntry, officialAnkiEntry],
      builtinEntry.wireKey,
    );
    return tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<CourseProvider>.value(value: courses),
          ChangeNotifierProvider<SettingsProvider>.value(value: settings),
        ],
        child: MaterialApp(
          theme: TurnaTheme.lightTheme,
          home: const CourseManagementPage(),
        ),
      ),
    );
  }

  testWidgets('add-course cards survive 200% text scale on a narrow phone',
      (tester) async {
    // 真机收据（2026-10-20）：字体放大后导入卡标题行曾报
    // `RIGHT OVERFLOWED BY 3 PIXELS` —— 文字列原先没有宽度约束。
    await tester.binding.setSurfaceSize(const Size(360, 780));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final courses = _FakeCourseProvider(
      [builtinEntry, secondBuiltinEntry, officialAnkiEntry],
      builtinEntry.wireKey,
    );
    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<CourseProvider>.value(value: courses),
          ChangeNotifierProvider<SettingsProvider>.value(value: settings),
        ],
        child: MaterialApp(
          theme: TurnaTheme.lightTheme,
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context).copyWith(
              textScaler: const TextScaler.linear(2),
            ),
            child: child!,
          ),
          home: const CourseManagementPage(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.text(AppStrings.courseManagementImportTitle), findsOneWidget);
    expect(
      find.text(AppStrings.courseManagementImportPackTitle),
      findsOneWidget,
    );
  });

  testWidgets('renders catalog with meta info and the import entry card',
      (tester) async {
    await pumpPage(tester);

    expect(find.text('Builtin Turkish'), findsOneWidget);
    expect(find.text('Builtin Japanese'), findsOneWidget);
    // 记忆卡牌组与内置课程并列（ADR 0067：记忆卡回归课程域）。
    expect(find.text('记忆卡牌组 A'), findsOneWidget);
    // 内置语言卡副题是「内置课程」；卡数文案只在非内置（导入包）卡上出现。
    expect(
        find.text(AppStrings.courseManagementBuiltinSubtitle),
        findsNWidgets(2));
    expect(find.text(AppStrings.courseManagementMyCourses), findsOneWidget);
    expect(find.text(AppStrings.courseManagementImportTitle), findsOneWidget);
    expect(
      find.text(AppStrings.courseManagementImportPackTitle),
      findsOneWidget,
    );
  });

  testWidgets('memory-card import lives in course management (ADR 0067)',
      (tester) async {
    // 记忆卡回归课程域：导入入口与牌组条目都在课程管理，练习台不再有
    // 记忆卡入口。ADR 0050 §6 step 4 的口径不变：任何构建档都不禁用
    // 导入卡，重新出现禁用态说明降级又爬回来了。
    await pumpPage(tester);

    expect(find.text(AppStrings.courseManagementImportTitle), findsOneWidget);
    expect(find.byIcon(Icons.add_circle_outline_rounded), findsNWidgets(2));
    expect(find.byIcon(Icons.block_outlined), findsNothing);
  });

  testWidgets('read-aloud entries appear on a build that has TTS',
      (tester) async {
    await pumpPage(tester);
    await settings.setTtsFeatureEnabled(true);
    await tester.pumpAndSettle();

    // 三张卡（两门内置 + 一副牌组）都带菜单。
    expect(find.byType(PopupMenuButton<String>), findsNWidgets(3));
  });

  testWidgets(
      'read-aloud off (default): only removable courses carry a menu, '
      'and it has no TTS item', (tester) async {
    await pumpPage(tester);

    // 两门内置语言互为保留底线（≥2 时可卸载），牌组可卸载 → 三张卡都带菜单。
    expect(find.byType(PopupMenuButton<String>), findsNWidgets(3));

    await tester.tap(find.byType(PopupMenuButton<String>).first);
    await tester.pumpAndSettle();

    expect(find.text(AppStrings.courseTtsSettingsTitle), findsNothing);
    expect(find.text(AppStrings.courseManagementRemoveCourse), findsOneWidget);
  });

  testWidgets(
      'read-aloud on: every card menu offers TTS settings; the '
      'sheet opens from it', (tester) async {
    await pumpPage(tester);
    await settings.setTtsFeatureEnabled(true);
    await tester.pump();

    expect(find.byType(PopupMenuButton<String>), findsNWidgets(3));

    // The built-in card (first) menu only offers TTS settings.
    await tester.tap(find.byType(PopupMenuButton<String>).first);
    await tester.pumpAndSettle();
    expect(find.text(AppStrings.courseTtsSettingsTitle), findsOneWidget);
    // 两门内置语言互为底线（≥2 可卸载）→ 第一张卡的菜单同样带移除项。
    expect(find.text(AppStrings.courseManagementRemoveCourse), findsOneWidget);

    await tester.tap(find.text(AppStrings.courseTtsSettingsTitle).last);
    await tester.pumpAndSettle();
    expect(find.text(AppStrings.courseTtsAutoReadTitle), findsOneWidget);
  });

  testWidgets('remove from the menu opens the exact-source confirmation',
      (tester) async {
    await pumpPage(tester);

    await tester.tap(find.byType(PopupMenuButton<String>).first);
    await tester.pumpAndSettle();
    await tester.tap(find.text(AppStrings.courseManagementRemoveCourse));
    await tester.pumpAndSettle();

    expect(
        find.text(AppStrings.courseUninstallConfirmTitle), findsOneWidget);
    expect(find.textContaining('Builtin Japanese'), findsOneWidget);

    await tester.tap(find.text(AppStrings.commonCancel));
    await tester.pumpAndSettle();
  });

  test(
      'the course-pack import failure branches dismiss with pop(), not maybePop()',
      () {
    // The progress dialog is pushed with an un-awaited `showDialog` and, when
    // the import throws before the next frame, the dismissal lands while that
    // dialog route has not been installed yet. `maybePop` asks the topmost route
    // whether it wants to handle the pop, and `ModalRoute.willPop` asserts its
    // scope is non-null — an assertion, so it surfaced as an uncaught platform
    // error in the device log rather than as a handled failure. `pop` does not
    // consult the route and dismisses cleanly.
    //
    // Checked against the source because the timing that triggers it cannot be
    // arranged from a widget test: reproducing Flutter's own behaviour here
    // would pass no matter what this page does.
    final source = File('lib/views/courses/course_management_page.dart')
        .readAsStringSync();

    expect(
      RegExp(r'rootNavigator:\s*true\)\.maybePop\(\)').hasMatch(source),
      isFalse,
      reason: 'a self-dismissed progress dialog must use pop(); '
          'maybePop() asserts on a route whose scope is not installed yet',
    );
    // Guard against the guard going stale: the branches really are there.
    expect(
      RegExp(r'rootNavigator:\s*true\)\.pop\(\)').allMatches(source).length,
      greaterThanOrEqualTo(4),
      reason:
          'expected the success pop plus the three failure-branch dismissals',
    );
  });
}
