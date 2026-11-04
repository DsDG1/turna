// Widget tests for the redesigned RemoteBackupPage (Plan §9.3): explicit
// save-and-test, credential placeholder instead of echo-back, backup/restore
// gated on a SAVED configuration.

// Package imports:
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:streaming_shared_preferences/streaming_shared_preferences.dart';

// Project imports:
import 'package:turna/di/injection.dart';
import 'package:turna/domain/repositories/i_credential_store.dart';
import 'package:turna/l10n/app_strings.dart';
import 'package:turna/service/locator.dart';
import 'package:turna/service/remote_backup/backup_manifest.dart';
import 'package:turna/service/remote_backup/backup_snapshot_service.dart';
import 'package:turna/service/remote_backup/remote_backup_config.dart';
import 'package:turna/service/remote_backup/remote_backup_service.dart';
import 'package:turna/service/remote_backup/webdav_client.dart';
import 'package:turna/views/settings/remote_backup_page.dart';

class _FakeCredentialStore implements ICredentialStore {
  final Map<String, String> storage = {};

  @override
  bool get isPersistent => true;

  @override
  Future<void> write(String id, String value) async => storage[id] = value;

  @override
  Future<String?> read(String id) async => storage[id];

  @override
  Future<void> delete(String id) async => storage.remove(id);

  @override
  Future<void> deleteAll() async => storage.clear();
}

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
  late _FakeCredentialStore credentials;
  late RemoteBackupConfigStore configStore;
  late _FakeRemoteBackupService service;

  setUp(() async {
    await getIt.reset();
    SharedPreferences.setMockInitialValues({});
    sp = await StreamingSharedPreferences.instance;
    await sp.remove(LocalStateKeys.remoteBackupConfig);
    await sp.remove(RemoteBackupConfigStore.migrationMarkerKey);
    prefs = AppPrefs(sp);
    credentials = _FakeCredentialStore();
    getIt.registerLazySingleton<AppPrefs>(() => prefs);
    configStore = RemoteBackupConfigStore(prefs, credentialStore: credentials);
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

  /// Drags the page list until [finder] is built and fully on-screen.
  /// Bidirectional sweep: built-but-above-viewport targets drag back down,
  /// and targets that never got built (e.g. the save button near the list
  /// top after scrolling to the actions card) get a backward sweep once the
  /// forward half of the budget is spent.
  Future<void> scrollTo(WidgetTester tester, Finder finder) async {
    var forward = true;
    for (var i = 0; i < 24; i++) {
      if (tester.any(finder)) {
        final rect = tester.getRect(finder.first);
        if (rect.top >= 0 && rect.bottom <= 600) return;
        // Bottom edge past the viewport → scroll forward; top edge above
        // it → scroll back up.
        forward = rect.bottom > 600;
      } else if (i >= 12) {
        forward = false;
      }
      await tester.drag(pageScrollable, Offset(0, forward ? -250 : 250));
      await tester.pumpAndSettle();
    }
    fail('never became visible: $finder');
  }

  /// Types the endpoint + password and taps the explicit save-and-test
  /// button. After this the endpoint + credential are PERSISTED.
  Future<void> saveConfig(WidgetTester tester) async {
    // Drive the controllers through the widget configs (same instances the
    // page owns): consecutive tester.enterText calls on different fields
    // inside this scroll view delivered only the first value (input client
    // switch lag), while the controller-level set exercises the identical
    // listener/save path deterministically.
    final fields = find.byType(TextField);
    tester.widget<TextField>(fields.at(0)).controller!.text =
        'https://dav.example.com';
    await tester.pump();
    tester.widget<TextField>(fields.at(1)).controller!.text = 'alice';
    await tester.pump();
    tester.widget<TextField>(fields.at(2)).controller!.text = 'secret';
    await tester.pumpAndSettle();
    await scrollTo(tester, find.text(AppStrings.remoteBackupSaveAndTest));
    await tester.tap(find.text(AppStrings.remoteBackupSaveAndTest));
    await tester.pumpAndSettle();
    // The result row renders right below the button; bring it into the
    // build window of the lazy ListView before asserting on it.
    await scrollTo(tester, find.text(AppStrings.remoteBackupTestOk));
  }

  testWidgets('renders the connection → recent → actions workflow',
      (tester) async {
    await pumpPage(tester);

    expect(find.text(AppStrings.remoteBackupServerSection), findsOneWidget);
    // 最近结果：本机一行「尚未备份过」；远程未查询时显示占位破折号。
    await scrollTo(tester, find.text(AppStrings.remoteBackupRecentSection));
    expect(find.text(AppStrings.remoteBackupRecentSection), findsOneWidget);
    expect(find.text(AppStrings.remoteBackupLastLocalLabel), findsOneWidget);
    expect(find.text(AppStrings.remoteBackupLastRemoteLabel), findsOneWidget);
    expect(find.text(AppStrings.remoteBackupNoBackupYet), findsOneWidget);
    expect(find.text('—'), findsOneWidget);
    await scrollTo(tester, find.text(AppStrings.remoteBackupActionsSection));
    expect(find.text(AppStrings.remoteBackupActionsSection), findsOneWidget);
    expect(find.text(AppStrings.remoteBackupBackupNow), findsOneWidget);
    expect(find.text(AppStrings.remoteBackupRestoreFromRemote), findsOneWidget);
    await scrollTo(tester, find.text(AppStrings.remoteBackupRestoreFromRemote));
    expect(
      find.text(AppStrings.remoteBackupRestoreSubtitle),
      findsOneWidget,
      reason: 'restore keeps its static subtitle; the remote status now '
          'lives in the recent-results row, not on the action tile',
    );
  });

  testWidgets('save-and-test persists endpoint + credential and reports ok',
      (tester) async {
    await pumpPage(tester);
    await saveConfig(tester);

    // Connection test succeeded through the result row…
    expect(find.text(AppStrings.remoteBackupTestOk), findsOneWidget);
    // …and nothing was ever persisted per keystroke: the endpoint JSON has
    // no password and the credential lives in the secure store only.
    expect(configStore.loadEndpoint().serverUrl, 'https://dav.example.com');
    final raw = prefs.preferences
        .getString(LocalStateKeys.remoteBackupConfig, defaultValue: '')
        .getValue();
    expect(raw.contains('secret'), isFalse);
    expect(
      credentials.storage[RemoteBackupConfigStore.securePasswordId],
      'secret',
    );
  });

  testWidgets('stored credential shows a placeholder, never the password',
      (tester) async {
    await configStore.saveEndpoint(const RemoteBackupEndpointConfig(
      serverUrl: 'https://dav.example.com',
      username: 'alice',
    ));
    await configStore.savePassword('super-secret');

    await pumpPage(tester);
    await tester.enterText(
      find
          .widgetWithText(TextField, AppStrings.remoteBackupServerUrlHint)
          .first,
      'https://dav.example.com',
    );
    await tester.pump();

    // The URL / username fields are prefilled; the password field shows the
    // "already saved" hint and the real password never appears as text.
    expect(find.text('super-secret'), findsNothing);
    expect(find.textContaining('已保存凭据'), findsWidgets);
  });

  testWidgets('backup now runs after a saved configuration', (tester) async {
    await pumpPage(tester);
    await saveConfig(tester);
    await scrollTo(tester, find.text(AppStrings.remoteBackupBackupNow));

    await tester.tap(find.text(AppStrings.remoteBackupBackupNow));
    await tester.pumpAndSettle();

    expect(service.backupCalls, 1);
    expect(find.text(AppStrings.remoteBackupSuccess('2.0 KB')), findsOneWidget);
  });

  testWidgets('restore requires a saved configuration AND an explicit confirm',
      (tester) async {
    await pumpPage(tester);
    // Before saving: the restore action explains instead of doing anything.
    await scrollTo(tester, find.text(AppStrings.remoteBackupRestoreFromRemote));
    await tester.tap(find.text(AppStrings.remoteBackupRestoreFromRemote));
    await tester.pumpAndSettle();
    expect(service.restoreCalls, 0);
    expect(find.text('请先保存服务器配置与凭据'), findsOneWidget);

    // Save, then restore asks for the destructive confirmation.
    await scrollTo(tester, find.text(AppStrings.remoteBackupSaveAndTest));
    await saveConfig(tester);
    await scrollTo(tester, find.text(AppStrings.remoteBackupRestoreFromRemote));
    await tester.tap(find.text(AppStrings.remoteBackupRestoreFromRemote));
    await tester.pumpAndSettle();

    expect(
        find.text(AppStrings.remoteBackupRestoreDialogTitle), findsOneWidget);
    expect(service.restoreCalls, 0,
        reason: 'nothing downloads before the user confirms');

    await tester.tap(
        find.widgetWithText(TextButton, AppStrings.remoteBackupRestoreConfirm));
    await tester.pumpAndSettle();

    expect(service.restoreCalls, 1);
    expect(
        find.text(AppStrings.remoteBackupRestoreStagedTitle), findsOneWidget);

    await tester.tap(find.byType(TextButton).last);
    await tester.pumpAndSettle();
  });
}
