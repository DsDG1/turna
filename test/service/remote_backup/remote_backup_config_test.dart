// Package imports:
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:streaming_shared_preferences/streaming_shared_preferences.dart';

// Project imports:
import 'package:turna/service/locator.dart';
import 'package:turna/service/remote_backup/remote_backup_config.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late StreamingSharedPreferences sp;
  late AppPrefs prefs;
  late RemoteBackupConfigStore store;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    sp = await StreamingSharedPreferences.instance;
    prefs = AppPrefs(sp);
    store = RemoteBackupConfigStore(prefs);
  });

  test('defaults are empty and not configured', () {
    const config = RemoteBackupConfig();
    expect(config.isConfigured, isFalse);
    expect(config.includeMedia, isTrue);
    expect(config.remoteRoot, 'TurnaBackup');
  });

  test('normalized trims URL slashes and sanitizes the remote root', () {
    const config = RemoteBackupConfig(
      serverUrl: ' https://dav.example.com/ ',
      username: ' alice ',
      password: 'pw',
      remoteRoot: '/my backups: v2/',
    );
    final normalized = config.normalized();
    expect(normalized.serverUrl, 'https://dav.example.com');
    expect(normalized.username, 'alice');
    expect(normalized.remoteRoot, 'my_backups_v2');
  });

  test('save / load roundtrips through prefs', () async {
    await store.save(const RemoteBackupConfig(
      serverUrl: 'https://dav.example.com',
      username: 'alice',
      password: 'secret',
      includeMedia: false,
      remoteRoot: 'TurnaBackup',
    ));
    final loaded = store.load();
    expect(loaded.serverUrl, 'https://dav.example.com');
    expect(loaded.username, 'alice');
    expect(loaded.password, 'secret');
    expect(loaded.includeMedia, isFalse);
    expect(loaded.isConfigured, isTrue);
  });

  test('corrupt persisted JSON degrades to defaults', () async {
    await sp.setString(LocalStateKeys.remoteBackupConfig, '{not json');
    expect(store.load(), const RemoteBackupConfig());
  });

  test('ensureRemoteBackupDeviceId is stable across calls and stores hex', () {
    final first = ensureRemoteBackupDeviceId(prefs);
    expect(first, matches(RegExp(r'^[0-9a-f]{16}$')));
    expect(ensureRemoteBackupDeviceId(prefs), first);
  });
}
