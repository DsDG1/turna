// Dart imports:
import 'dart:io';

// Package imports:
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqlite3/sqlite3.dart' as sql;
import 'package:streaming_shared_preferences/streaming_shared_preferences.dart';

// Project imports:
import 'package:turna/application/anki_official/storage/official_anki_sqlite.dart';
import 'package:turna/data/course_database.dart';
import 'package:turna/service/locator.dart';
import 'package:turna/service/remote_backup/backup_manifest.dart';
import 'package:turna/service/remote_backup/backup_snapshot_service.dart';
import 'package:turna/domain/repositories/i_credential_store.dart';
import 'package:turna/service/remote_backup/remote_backup_config.dart';
import 'package:turna/service/remote_backup/remote_backup_service.dart';
import 'package:turna/service/remote_backup/remote_backup_store.dart';
import 'package:turna/service/remote_backup/restore_staging.dart';

/// Directory-backed fake that mirrors the remote layout locally and records
/// the operation order for upload-ordering assertions.
class FakeRemoteBackupStore extends RemoteBackupStore {
  FakeRemoteBackupStore(this.storage);

  final Directory storage;
  final List<String> ops = <String>[];
  RemoteBackupManifest? manifest;

  @override
  Future<void> ensureLayout() async {
    ops.add('layout');
    await Directory(p.join(storage.path, 'backups')).create(recursive: true);
    await Directory(p.join(storage.path, 'media')).create(recursive: true);
  }

  @override
  Future<RemoteBackupManifest?> fetchManifest() async => manifest;

  @override
  Future<void> publishManifest(RemoteBackupManifest m) async {
    manifest = m;
    ops.add('manifest');
  }

  @override
  Future<void> uploadCoreZip(String backupId, File coreZip) async {
    final dir = Directory(p.join(storage.path, 'backups', backupId))
      ..createSync(recursive: true);
    await coreZip.copy(p.join(dir.path, 'core.zip'));
    ops.add('core:$backupId');
  }

  @override
  Future<bool> hasMediaObject(String sha256) async =>
      File(p.join(storage.path, 'media', sha256)).existsSync();

  @override
  Future<void> uploadMediaObject(String sha256, File source) async {
    await source.copy(p.join(storage.path, 'media', sha256));
    ops.add('media:$sha256');
  }

  @override
  Future<void> downloadCoreZip(RemoteBackupManifest m, File dest) async {
    await File(p.join(storage.path, m.coreZipObject)).copy(dest.path);
  }

  @override
  Future<void> downloadMediaObject(String sha256, File dest) async {
    await File(p.join(storage.path, 'media', sha256)).copy(dest.path);
  }

  @override
  Future<void> deleteBackup(String backupId) async {
    ops.add('delete:$backupId');
    final dir = Directory(p.join(storage.path, 'backups', backupId));
    if (dir.existsSync()) dir.deleteSync(recursive: true);
  }
}

/// Minimal in-memory credential store: the service resolves the WebDAV
/// password through it instead of SharedPreferences.
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

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  ensureOfficialAnkiSqlite();

  late Directory tmp;
  late CourseDatabase db;
  late AppPrefs prefs;
  late RemoteBackupConfigStore configStore;
  late BackupSnapshotService snapshotService;
  late FakeRemoteBackupStore store;
  late RemoteBackupService service;
  late Directory appSupport;

  final packageInfo = PackageInfo(
    appName: 'turna',
    packageName: 'me.dsdogs.turna',
    version: '0.4.0',
    buildNumber: '42',
  );

  setUp(() async {
    tmp = await Directory.systemTemp.createTemp('turna_rb_service');
    appSupport = Directory(p.join(tmp.path, 'app_support'))..createSync();
    db = CourseDatabase(
        NativeDatabase(File(p.join(appSupport.path, 'live_course.db'))));

    SharedPreferences.setMockInitialValues(<String, Object>{});
    final sp = await StreamingSharedPreferences.instance;
    prefs = AppPrefs(sp);
    configStore =
        RemoteBackupConfigStore(prefs, credentialStore: _FakeCredentialStore());
    await configStore.saveEndpoint(const RemoteBackupEndpointConfig(
      serverUrl: 'https://dav.example.com',
      username: 'alice',
    ));
    await configStore.savePassword('secret');

    final profileRoot =
        Directory(p.join(appSupport.path, 'official_anki', 'default'))
          ..createSync(recursive: true);
    for (final name in [
      'collection.anki2',
      'official_catalog.sqlite',
      'collection.media.db2'
    ]) {
      final database = sql.sqlite3.open(p.join(profileRoot.path, name));
      database.execute('CREATE TABLE t(x)');
      database.dispose();
    }
    Directory(p.join(profileRoot.path, 'collection.media')).createSync();
    File(p.join(profileRoot.path, 'collection.media', 'a.png'))
        .writeAsBytesSync([1, 2, 3]);

    final legacyMedia = Directory(p.join(appSupport.path, 'anki_media'))
      ..createSync();
    File(p.join(legacyMedia.path, 'imp1', 'a.mp3'))
      ..createSync(recursive: true)
      ..writeAsBytesSync([4, 5, 6]);

    snapshotService = BackupSnapshotService(
      db: db,
      packageInfo: packageInfo,
      officialProfileRoot: profileRoot,
      legacyMediaRoot: legacyMedia,
    );

    store = FakeRemoteBackupStore(
        Directory(p.join(tmp.path, 'server'))..createSync());
    service = RemoteBackupService(
      prefs: prefs,
      configStore: configStore,
      snapshotService: snapshotService,
      appSupport: appSupport,
      storeFactory: (_) => store,
    );
  });

  tearDown(() async {
    await db.close();
    if (tmp.existsSync()) tmp.deleteSync(recursive: true);
  });

  test('backupNow uploads media, then core, then manifest (in that order)',
      () async {
    final result = await service.backupNow();

    final manifest = store.manifest;
    expect(manifest, isNotNull);
    expect(manifest!.backupId, result.backupId);
    expect(manifest.coreZipObject, 'backups/${result.backupId}/core.zip');
    expect(manifest.driftSchema, 20);
    expect(manifest.mediaCount, 2);
    expect(manifest.history, isEmpty);

    final coreIndex = store.ops.indexWhere((op) => op.startsWith('core:'));
    final manifestIndex = store.ops.indexOf('manifest');
    final lastMediaIndex =
        store.ops.lastIndexWhere((op) => op.startsWith('media:'));
    expect(lastMediaIndex, lessThan(coreIndex),
        reason: 'media objects must upload before the core archive');
    expect(coreIndex, lessThan(manifestIndex),
        reason: 'the manifest must be published last');

    expect(result.mediaUploaded, 2);
    expect(result.mediaSkipped, 0);
    expect(service.lastLocalBackup()?.backupId, result.backupId);
    expect(
      Directory(p.join(appSupport.path, 'backup_staging')).existsSync(),
      isFalse,
      reason: 'local snapshot staging is cleaned after upload',
    );
  });

  test('a second backup with unchanged media skips every object', () async {
    final first = await service.backupNow();
    final second = await service.backupNow();

    expect(second.mediaUploaded, 0);
    expect(second.mediaSkipped, 2);
    expect(store.manifest!.backupId, second.backupId);
    expect(store.manifest!.history.first.backupId, first.backupId);
  });

  test('retention drops backup generations beyond the window', () async {
    final ids = <String>[];
    for (var i = 0; i < kRemoteBackupRetention + 2; i++) {
      ids.add((await service.backupNow()).backupId);
    }
    final deletes = store.ops.where((op) => op.startsWith('delete:')).toList();
    expect(deletes, isNotEmpty);
    final keep = store.manifest!.history.map((e) => e.backupId).toSet()
      ..add(store.manifest!.backupId);
    for (final op in deletes) {
      final id = op.substring('delete:'.length);
      expect(keep.contains(id), isFalse,
          reason: 'only out-of-window generations may be deleted');
    }
    expect(keep.contains(ids.first), isFalse);
    expect(keep.contains(ids.last), isTrue);
  });

  test('busy guard rejects concurrent backup attempts', () async {
    final guarded = RemoteBackupService(
      prefs: prefs,
      configStore: configStore,
      snapshotService: snapshotService,
      appSupport: appSupport,
      storeFactory: (_) => store,
      busyGuard: () => true,
    );
    await expectLater(
        guarded.backupNow(), throwsA(isA<RemoteBackupBusyException>()));
  });

  test('restoreToStaging stages a verifiable, marker-armed restore', () async {
    await service.backupNow();
    final manifest = store.manifest!;

    await service.restoreToStaging(manifest);

    final staging = RestoreStagingLayout.root(appSupport);
    expect(File(p.join(staging.path, 'prefs.json')).existsSync(), isTrue);
    expect(File(p.join(staging.path, 'course.db')).existsSync(), isTrue);
    expect(File(p.join(staging.path, 'collection.anki2')).existsSync(), isTrue);
    expect(
        File(p.join(staging.path, RestoreStagingLayout.markerName))
            .existsSync(),
        isTrue);
    final marker = RestoreStagingLayout.decodeMarker(
        File(p.join(staging.path, RestoreStagingLayout.markerName))
            .readAsStringSync());
    expect(marker?['backupId'], manifest.backupId);
    final mediaDir = RestoreStagingLayout.media(appSupport);
    expect(mediaDir.listSync().length, 2,
        reason: 'both media objects are staged by content hash');
  });

  test('restoreToStaging aborts on a checksum mismatch', () async {
    await service.backupNow();
    final manifest = store.manifest!;
    final tampered = RemoteBackupManifest(
      backupId: manifest.backupId,
      createdAtUtc: manifest.createdAtUtc,
      deviceId: manifest.deviceId,
      deviceLabel: manifest.deviceLabel,
      appVersion: manifest.appVersion,
      buildNumber: manifest.buildNumber,
      platform: manifest.platform,
      driftSchema: manifest.driftSchema,
      catalogSchema: manifest.catalogSchema,
      coreZipObject: manifest.coreZipObject,
      coreZipSha256: 'f' * 64,
      coreZipBytes: manifest.coreZipBytes,
      mediaCount: manifest.mediaCount,
      mediaBytes: manifest.mediaBytes,
      history: manifest.history,
    );
    await expectLater(service.restoreToStaging(tampered), throwsException);
    expect(
      RestoreStagingLayout.marker(appSupport).existsSync(),
      isFalse,
      reason: 'a failed download must never arm the restore marker',
    );
  });
}
