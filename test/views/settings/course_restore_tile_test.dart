import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:turna/l10n/app_strings.dart';
import 'package:turna/service/content_ota/course_ota_service.dart';
import 'package:turna/views/settings/components/settings_course_restore_tile.dart';

void main() {
  Future<void> pumpTile(
    WidgetTester tester, {
    required CourseContentClear clear,
    required CourseContentRefresh refresh,
    Future<void> Function()? acknowledge,
  }) {
    return tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SettingsCourseRestoreTile(
            clearInstalled: clear,
            refreshContent: refresh,
            acknowledgeContentVersion: acknowledge ?? () async {},
            languageCode: 'tr',
          ),
        ),
      ),
    );
  }

  Future<void> openDialog(WidgetTester tester) async {
    await tester.tap(find.text(AppStrings.settingsCourseRestoreTitle));
    await tester.pumpAndSettle();
  }

  testWidgets('the confirmation dialog gates the deletion', (tester) async {
    var clearCalls = 0;
    await pumpTile(
      tester,
      clear: (_) async {
        clearCalls++;
        return true;
      },
      refresh: (_) async => true,
    );

    await openDialog(tester);

    expect(find.byType(AlertDialog), findsOneWidget);
    expect(find.text(AppStrings.settingsCourseRestoreDialogMessage),
        findsOneWidget);
    expect(clearCalls, 0);
  });

  testWidgets('cancelling keeps the installed package', (tester) async {
    var clearCalls = 0;
    await pumpTile(
      tester,
      clear: (_) async {
        clearCalls++;
        return true;
      },
      refresh: (_) async => true,
    );

    await openDialog(tester);
    await tester.tap(find.text(AppStrings.commonCancel));
    await tester.pumpAndSettle();

    expect(clearCalls, 0);
    expect(find.byType(SnackBar), findsNothing);
  });

  testWidgets('confirming clears, reseeds and acknowledges the version',
      (tester) async {
    final calls = <String>[];
    String? refreshedLanguage;
    await pumpTile(
      tester,
      clear: (code) async {
        calls.add('clear:$code');
        return true;
      },
      refresh: (code) async {
        calls.add('refresh');
        refreshedLanguage = code;
        return true;
      },
      acknowledge: () async => calls.add('ack'),
    );

    await openDialog(tester);
    await tester.tap(find.text(AppStrings.settingsCourseRestoreConfirm));
    await tester.pumpAndSettle();

    expect(calls, ['clear:tr', 'refresh', 'ack']);
    expect(refreshedLanguage, 'tr');
    expect(find.text(AppStrings.settingsCourseRestoreDone), findsOneWidget);
  });

  testWidgets('a failed deletion skips the reseed', (tester) async {
    var refreshCalls = 0;
    await pumpTile(
      tester,
      clear: (_) async => throw const CourseOtaException('课程目录不可写'),
      refresh: (_) async {
        refreshCalls++;
        return true;
      },
    );

    await openDialog(tester);
    await tester.tap(find.text(AppStrings.settingsCourseRestoreConfirm));
    await tester.pumpAndSettle();

    expect(refreshCalls, 0);
    expect(
      find.text(AppStrings.settingsCourseRestoreFailed('课程目录不可写')),
      findsOneWidget,
    );
  });

  testWidgets('a failed reseed still reports that the package was removed',
      (tester) async {
    var acknowledgeCalls = 0;
    await pumpTile(
      tester,
      clear: (_) async => true,
      refresh: (_) async => throw const CourseOtaException('复习正在进行中'),
      acknowledge: () async => acknowledgeCalls++,
    );

    await openDialog(tester);
    await tester.tap(find.text(AppStrings.settingsCourseRestoreConfirm));
    await tester.pumpAndSettle();

    expect(acknowledgeCalls, 0);
    expect(
      find.text(AppStrings.settingsCourseRestoreReseedFailed('复习正在进行中')),
      findsOneWidget,
    );
  });

  testWidgets('nothing installed reports bundled content without reseeding',
      (tester) async {
    var refreshCalls = 0;
    await pumpTile(
      tester,
      clear: (_) async => false,
      refresh: (_) async {
        refreshCalls++;
        return true;
      },
    );

    await openDialog(tester);
    await tester.tap(find.text(AppStrings.settingsCourseRestoreConfirm));
    await tester.pumpAndSettle();

    expect(refreshCalls, 0);
    expect(
      find.text(AppStrings.settingsCourseRestoreNothingInstalled),
      findsOneWidget,
    );
  });
}
