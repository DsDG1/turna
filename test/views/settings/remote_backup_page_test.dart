// Package imports:
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:streaming_shared_preferences/streaming_shared_preferences.dart';

// Project imports:
import 'package:turna/di/injection.dart';
import 'package:turna/l10n/app_strings.dart';
import 'package:turna/service/locator.dart';
import 'package:turna/service/remote_backup/backup_manifest.dart';
import 'package:turna/service/remote_backup/backup_snapshot_service.dart';
import 'package:turna/service/remote_backup/remote_backup_config.dart';
import 'package:turna/service/remote_backup/remote_backup_service.dart';
import 'package:turna/service/remote_backup/webdav_client.dart';
import 'package:turna/views/settings/remote_backup_page.dart';

class _FakeRemoteBackupService implements RemoteBackupService {
  _FakeRemoteBackupService({this.manifest});

  final RemoteBackupManifest? manifest;
  int backupCalls = 0;
  int restoreCalls = 0;

  @override
  RemoteBackupResult? lastLocalBackup() => null;

  @override
  Future<RemoteBackupManifest?> fetchRemoteStatus() async => manifest;

  @override
  Future<WebDavProbeResult> testConnection() async =>
      const WebDavProbeResult(serverHeader: 'test', davHeader: '1, 2');

  @override
  Future<RemoteBackupResult> backupNow(
      {void Function(BackupSnapshotPhase phase)? onPhase,
      void Function(int hashed, int total)? onMediaProgress,
      void Function(int uploaded, int skipped)? onMediaUploadProgress}) async {
    backupCalls++;
    return RemoteBackupResult(
      backupId: 'bk-test',
      createdAtUtc: DateTime.utc(2026, 8, 23),
      coreZipBytes: 2048,
      mediaUploaded: 0,
      mediaSkipped: 0,
    );
  }

  @override
  Future<void> restoreToStaging(RemoteBackupManifest manifest,
      {void Function(int done, int total)? onMediaProgress}) async {
    restoreCalls++;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

RemoteBackupManifest _manifest() => RemoteBackupManifest(
      backupId: 'bk-remote',
      createdAtUtc: DateTime.utc(2026, 8, 22, 9, 30),
      deviceId: 'other-device',
      deviceLabel: 'android',
      appVersion: '0.4.0',
      buildNumber: '42',
      platform: 'android',
      driftSchema: 18,
      catalogSchema: 8,
      coreZipObject: 'backups/bk-remote/core.zip',
      coreZipSha256: 'a' * 64,
      coreZipBytes: 4096,
      mediaCount: 3,
      mediaBytes: 300,
      history: const [],
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late StreamingSharedPreferences sp;
  late AppPrefs prefs;
  late RemoteBackupConfigStore configStore;
  late _FakeRemoteBackupService service;

  setUp(() async {
    await getIt.reset();
    SharedPreferences.setMockInitialValues({});
    sp = await StreamingSharedPreferences.instance;
    prefs = AppPrefs(sp);
    getIt.registerLazySingleton<AppPrefs>(() => prefs);
    configStore = RemoteBackupConfigStore(prefs);
    getIt.registerLazySingleton<RemoteBackupConfigStore>(() => configStore);
    service = _FakeRemoteBackupService(manifest: _manifest());
    getIt.registerLazySingleton<RemoteBackupService>(() => service);
  });

  tearDown(() async {
    await getIt.reset();
  });

  Future<void> pumpPage(WidgetTester tester) async {
    await tester.pumpWidget(const MaterialApp(home: RemoteBackupPage()));
    await tester.pumpAndSettle();
  }

  /// The page ListView's own scrollable (TextFields embed their own).
  final Finder pageScrollable = find
      .descendant(
        of: find.byType(ListView),
        matching: find.byType(Scrollable),
      )
      .first;

  /// Drags the page list up until [finder] is built and fully on-screen.
  Future<void> scrollTo(WidgetTester tester, Finder finder) async {
    for (var i = 0; i < 12; i++) {
      if (tester.any(finder)) {
        final rect = tester.getRect(finder.first);
        if (rect.top >= 0 && rect.bottom <= 600) return;
      }
      await tester.drag(pageScrollable, const Offset(0, -250));
      await tester.pumpAndSettle();
    }
    fail('never became visible: $finder');
  }

  Future<void> fillConfig(WidgetTester tester) async {
    await tester.enterText(
        find.widgetWithText(TextField, AppStrings.remoteBackupServerUrlHint)
            .first,
        'https://dav.example.com');
    await tester.enterText(
        find.widgetWithText(TextField, AppStrings.remoteBackupUsernameHint)
            .first,
        'alice');
    await tester.enterText(
        find.widgetWithText(TextField, AppStrings.remoteBackupPasswordHint)
            .first,
        'secret');
    await tester.pump();
  }

  testWidgets('renders all three sections and the no-backup state',
      (tester) async {
    await pumpPage(tester);

    expect(find.text(AppStrings.remoteBackupServerSection), findsOneWidget);
    expect(find.text(AppStrings.remoteBackupBackupSection), findsOneWidget);
    await scrollTo(tester,
        find.text(AppStrings.remoteBackupRestoreSection));
    expect(find.text(AppStrings.remoteBackupRestoreSection), findsOneWidget);
    expect(find.text(AppStrings.remoteBackupNoBackupYet), findsOneWidget);
    expect(find.text(AppStrings.remoteBackupBackupNow), findsOneWidget);
    expect(find.text(AppStrings.remoteBackupRestoreFromRemote), findsOneWidget);
    await scrollTo(tester,
        find.text(AppStrings.remoteBackupRestoreFromRemote));
    expect(
      find.text(AppStrings.remoteBackupRestoreSubtitle),
      findsOneWidget,
      reason:
          'before configuring, the restore tile falls back to its static '
          'subtitle (no remote fetch happens unconfigured)',
    );
  });

  testWidgets('test connection reports success through the result row',
      (tester) async {
    await pumpPage(tester);
    await fillConfig(tester);

    await tester.tap(find.text(AppStrings.remoteBackupTestConnection));
    await tester.pumpAndSettle();

    expect(find.text(AppStrings.remoteBackupTestOk), findsOneWidget);
  });

  testWidgets('backup now shows a completion snackbar', (tester) async {
    await pumpPage(tester);
    await fillConfig(tester);
    await scrollTo(tester, find.text(AppStrings.remoteBackupBackupNow));

    await tester.tap(find.text(AppStrings.remoteBackupBackupNow));
    await tester.pumpAndSettle();

    expect(service.backupCalls, 1);
    expect(find.text(AppStrings.remoteBackupSuccess('2.0 KB')),
        findsOneWidget);
  });

  testWidgets('restore requires an explicit destructive confirmation',
      (tester) async {
    await pumpPage(tester);
    await fillConfig(tester);
    await scrollTo(tester,
        find.text(AppStrings.remoteBackupRestoreFromRemote));

    await tester.tap(find.text(AppStrings.remoteBackupRestoreFromRemote));
    await tester.pumpAndSettle();

    expect(find.text(AppStrings.remoteBackupRestoreDialogTitle),
        findsOneWidget);
    expect(service.restoreCalls, 0,
        reason: 'nothing downloads before the user confirms');

    await tester
        .tap(find.widgetWithText(TextButton, AppStrings.remoteBackupRestoreConfirm));
    await tester.pumpAndSettle();

    expect(service.restoreCalls, 1);
    expect(find.text(AppStrings.remoteBackupRestoreStagedTitle),
        findsOneWidget);

    await tester.tap(find.byType(TextButton).last);
    await tester.pumpAndSettle();
  });
}
