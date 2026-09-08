// Widget tests for the course-management page: catalog rendering with meta
// info, and the opt-in visibility of the read-aloud entry in the card menu.

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
import 'package:turna/views/theme.dart';

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
  final importedEntry = CourseCatalogEntry(
    scope: const LegacyAnkiCourseScope('import-1'),
    displayName: 'JLPT N5 词库',
    isBuiltin: false,
    legacyImportId: 'import-1',
    cardCount: 1204,
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
      [builtinEntry, importedEntry],
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

  testWidgets('renders catalog with meta info and the import entry card',
      (tester) async {
    await pumpPage(tester);

    expect(find.text('Builtin Turkish'), findsOneWidget);
    expect(find.text('JLPT N5 词库'), findsOneWidget);
    expect(find.text(AppStrings.courseManagementCardCount(1204)),
        findsOneWidget);
    expect(find.text(AppStrings.courseManagementBuiltinSubtitle),
        findsOneWidget);
    expect(find.text(AppStrings.courseManagementMyCourses), findsOneWidget);
    expect(find.text(AppStrings.courseManagementImportTitle), findsOneWidget);
  });

  testWidgets(
      'read-aloud off (default): only removable courses carry a menu, '
      'and it has no TTS item', (tester) async {
    await pumpPage(tester);

    // The built-in course has neither action → no menu at all.
    expect(find.byType(PopupMenuButton<String>), findsOneWidget);

    await tester.tap(find.byType(PopupMenuButton<String>));
    await tester.pumpAndSettle();

    expect(find.text(AppStrings.courseTtsSettingsTitle), findsNothing);
    expect(find.text(AppStrings.courseManagementRemoveCourse), findsOneWidget);
  });

  testWidgets('read-aloud on: every card menu offers TTS settings; the '
      'sheet opens from it', (tester) async {
    await pumpPage(tester);
    await settings.setTtsFeatureEnabled(true);
    await tester.pump();

    expect(find.byType(PopupMenuButton<String>), findsNWidgets(2));

    // The built-in card (first) menu only offers TTS settings.
    await tester.tap(find.byType(PopupMenuButton<String>).first);
    await tester.pumpAndSettle();
    expect(find.text(AppStrings.courseTtsSettingsTitle), findsOneWidget);
    expect(find.text(AppStrings.courseManagementRemoveCourse), findsNothing);

    await tester.tap(find.text(AppStrings.courseTtsSettingsTitle).last);
    await tester.pumpAndSettle();
    expect(find.text(AppStrings.courseTtsAutoReadTitle), findsOneWidget);
  });

  testWidgets('remove from the menu opens the exact-source confirmation',
      (tester) async {
    await pumpPage(tester);

    await tester.tap(find.byType(PopupMenuButton<String>));
    await tester.pumpAndSettle();
    await tester.tap(find.text(AppStrings.courseManagementRemoveCourse));
    await tester.pumpAndSettle();

    expect(find.text(AppStrings.ankiUninstallConfirmTitle), findsOneWidget);
    expect(find.textContaining('import-1'), findsOneWidget);

    await tester.tap(find.text(AppStrings.commonCancel));
    await tester.pumpAndSettle();
  });
}
