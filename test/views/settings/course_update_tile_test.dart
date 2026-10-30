import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:turna/l10n/app_strings.dart';
import 'package:turna/service/content_ota/course_ota_service.dart';
import 'package:turna/views/settings/components/settings_course_update_tile.dart';

void main() {
  CourseOtaResult result() => CourseOtaResult(
        languageCode: 'tr',
        version: const (index: 3, expressions: 1),
        packageSha256: 'a' * 64,
        directory: Directory('test'),
        notes: '测试更新',
      );

  Future<void> pumpTile(
    WidgetTester tester, {
    required CourseUrlUpdate update,
    required Future<bool> Function(String) refresh,
  }) {
    return tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SettingsCourseUpdateTile(
            updateFromUrl: update,
            refreshContent: refresh,
            languageCode: 'tr',
          ),
        ),
      ),
    );
  }

  Future<void> openDialog(WidgetTester tester) async {
    await tester.tap(find.text(AppStrings.settingsCourseUpdateTitle));
    await tester.pumpAndSettle();
  }

  testWidgets('successful download refreshes builtin content and shows version',
      (tester) async {
    String? receivedUrl;
    String? downloadLanguage;
    String? refreshedLanguage;
    await pumpTile(
      tester,
      update: (
        rawUrl, {
        required languageCode,
        onPhase,
        onProgress,
      }) async {
        receivedUrl = rawUrl;
        downloadLanguage = languageCode;
        return result();
      },
      refresh: (code) async {
        refreshedLanguage = code;
        return true;
      },
    );
    await openDialog(tester);
    await tester.enterText(
      find.byType(TextField),
      '  https://example.com/course-feed.json  ',
    );

    await tester.tap(find.text(AppStrings.settingsCourseUpdateAction));
    await tester.pumpAndSettle();

    expect(receivedUrl, 'https://example.com/course-feed.json');
    expect(downloadLanguage, 'tr');
    expect(refreshedLanguage, 'tr');
    expect(
        find.text(AppStrings.settingsCourseUpdateSuccess(3)), findsOneWidget);
    expect(find.byType(AlertDialog), findsNothing);
  });

  testWidgets('download failure stays in dialog and does not reseed',
      (tester) async {
    var refreshCalls = 0;
    await pumpTile(
      tester,
      update: (
        rawUrl, {
        required languageCode,
        onPhase,
        onProgress,
      }) async =>
          throw const CourseOtaException('课程包 SHA-256 校验失败'),
      refresh: (_) async {
        refreshCalls++;
        return true;
      },
    );
    await openDialog(tester);
    await tester.enterText(find.byType(TextField), 'https://example.com/feed');

    await tester.tap(find.text(AppStrings.settingsCourseUpdateAction));
    await tester.pumpAndSettle();

    expect(refreshCalls, 0);
    expect(find.byType(AlertDialog), findsOneWidget);
    expect(find.textContaining('课程包 SHA-256 校验失败'), findsOneWidget);
  });

  testWidgets('empty URL is rejected before any network call', (tester) async {
    var updateCalls = 0;
    await pumpTile(
      tester,
      update: (
        rawUrl, {
        required languageCode,
        onPhase,
        onProgress,
      }) async {
        updateCalls++;
        return result();
      },
      refresh: (_) async => true,
    );
    await openDialog(tester);

    await tester.tap(find.text(AppStrings.settingsCourseUpdateAction));
    await tester.pump();

    expect(updateCalls, 0);
    expect(
        find.text(AppStrings.settingsCourseUpdateUrlRequired), findsOneWidget);
  });

  testWidgets(
      'apply failure retries installed package without downloading again',
      (tester) async {
    var updateCalls = 0;
    var refreshCalls = 0;
    await pumpTile(
      tester,
      update: (
        rawUrl, {
        required languageCode,
        onPhase,
        onProgress,
      }) async {
        updateCalls++;
        return result();
      },
      refresh: (_) async {
        refreshCalls++;
        if (refreshCalls == 1) throw StateError('远程备份正在进行中');
        return true;
      },
    );
    await openDialog(tester);
    await tester.enterText(find.byType(TextField), 'https://example.com/feed');
    await tester.tap(find.text(AppStrings.settingsCourseUpdateAction));
    await tester.pumpAndSettle();

    expect(updateCalls, 1);
    expect(refreshCalls, 1);
    expect(find.textContaining('课程包已下载，但应用更新失败'), findsOneWidget);

    await tester.tap(find.text(AppStrings.settingsCourseUpdateRetryApply));
    await tester.pumpAndSettle();

    expect(updateCalls, 1);
    expect(refreshCalls, 2);
    expect(
        find.text(AppStrings.settingsCourseUpdateSuccess(3)), findsOneWidget);
  });

  testWidgets('package progress is rendered while download is in flight',
      (tester) async {
    final pending = Completer<CourseOtaResult>();
    await pumpTile(
      tester,
      update: (
        rawUrl, {
        required languageCode,
        onPhase,
        onProgress,
      }) {
        onPhase?.call(CourseOtaPhase.downloadingPackage);
        onProgress?.call(50, 100);
        return pending.future;
      },
      refresh: (_) async => true,
    );
    await openDialog(tester);
    await tester.enterText(
        find.byType(TextField), 'https://example.com/pack.zip');

    await tester.tap(find.text(AppStrings.settingsCourseUpdateAction));
    await tester.pump();
    await tester.pump();

    final indicator = tester.widget<LinearProgressIndicator>(
      find.byType(LinearProgressIndicator),
    );
    expect(indicator.value, 0.5);
    expect(find.text('50 / 100 字节'), findsOneWidget);

    pending.complete(result());
    await tester.pumpAndSettle();
    expect(
        find.text(AppStrings.settingsCourseUpdateSuccess(3)), findsOneWidget);
  });
}
