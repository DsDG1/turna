// Dart imports:
import 'dart:convert';
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
import 'package:turna/service/remote_backup/archive_io.dart';
import 'package:turna/service/remote_backup/backup_manifest.dart';
import 'package:turna/service/remote_backup/backup_snapshot_service.dart';
import 'package:turna/service/remote_backup/remote_backup_busy_gate.dart';
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

/// Store whose core upload can fail on demand — interruption coverage for
/// the backup/recovery tests (plan P0).
class _FailingStore extends FakeRemoteBackupStore {
  _FailingStore(super.storage);

  bool failCoreUpload = false;

  @override
  Future<void> uploadCoreZip(String backupId, File coreZip) async {
    if (failCoreUpload) {
      throw const SocketException('connection reset mid-upload');
    }
    await super.uploadCoreZip(backupId, coreZip);
  }
}

/// Snapshot service that simulates writes racing the snapshot period
/// (plan P0 consistency boundary): [lateScope] enters a study scope right
/// when the build starts, [mutateAfterBuild] runs after the immutable
/// staging copies exist.
class _RacingSnapshotService extends BackupSnapshotService {
  _RacingSnapshotService({
    required super.db,
    required super.packageInfo,
    required super.officialProfileRoot,
    required super.legacyMediaRoot,
    required this.gate,
    this.lateScope,
    this.mutateAfterBuild,
  });

  final StudyActivityGate gate;
  final void Function()? lateScope;
  final void Function(BackupSnapshot snapshot)? mutateAfterBuild;

  @override
  Future<BackupSnapshot> build({
    required Directory stagingDir,
    bool includeMedia = true,
    void Function(BackupSnapshotPhase phase)? onPhase,
    void Function(int hashed, int total)? onMediaProgress,
    void Function()? busyCheck,
    Future<void> Function(File source, File dest)? copyImpl,
  }) {
    lateScope?.call();
    return super
        .build(
          stagingDir: stagingDir,
          includeMedia: includeMedia,
          onPhase: onPhase,
          onMediaProgress: onMediaProgress,
          busyCheck: busyCheck,
        )
        .then((snapshot) {
      mutateAfterBuild?.call(snapshot);
      return snapshot;
    });
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
    // Windows 上杀软扫描或句柄延迟释放会让递归删除偶发 errno 32；重试
    // 几轮，仍失败就留给系统临时目录清理。
    for (var attempt = 0; attempt < 5; attempt++) {
      if (!tmp.existsSync()) return;
      try {
        tmp.deleteSync(recursive: true);
        return;
      } on FileSystemException {
        await Future<void>.delayed(const Duration(milliseconds: 200));
      }
    }
  });

  test('backupNow uploads media, then core, then manifest (in that order)',
      () async {
    final result = await service.backupNow();

    final manifest = store.manifest;
    expect(manifest, isNotNull);
    expect(manifest!.backupId, result.backupId);
    expect(manifest.coreZipObject, 'backups/${result.backupId}/core.zip');
    expect(manifest.driftSchema, CourseDatabase.kSchemaVersion);
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

  test('a study activity running rejects the backup (busy guard)', () async {
    final gate = StudyActivityGate()..begin('anki_review_session');
    final guarded = RemoteBackupService(
      prefs: prefs,
      configStore: configStore,
      snapshotService: snapshotService,
      appSupport: appSupport,
      activityGate: gate,
      storeFactory: (_) => store,
    );
    await expectLater(
        guarded.backupNow(), throwsA(isA<RemoteBackupBusyException>()));
    gate.end('anki_review_session');
  });

  test('a study activity starting mid-snapshot aborts the backup cleanly',
      () async {
    final gate = StudyActivityGate();
    var raced = false;
    final racing = _RacingSnapshotService(
      db: db,
      packageInfo: packageInfo,
      officialProfileRoot:
          Directory(p.join(appSupport.path, 'official_anki', 'default')),
      legacyMediaRoot: Directory(p.join(appSupport.path, 'anki_media')),
      gate: gate,
      lateScope: () {
        if (raced) return;
        raced = true;
        gate.debugForceScope('ungated_writer');
      },
    );
    final guarded = RemoteBackupService(
      prefs: prefs,
      configStore: configStore,
      snapshotService: racing,
      appSupport: appSupport,
      activityGate: gate,
      storeFactory: (_) => store,
    );

    await expectLater(
        guarded.backupNow(), throwsA(isA<RemoteBackupBusyException>()));
    expect(store.manifest, isNull,
        reason: 'an aborted snapshot must never publish a manifest');
    expect(store.ops.where((op) => op.startsWith('core:')), isEmpty,
        reason: 'nothing may be uploaded from an aborted snapshot');
    expect(
      Directory(p.join(appSupport.path, 'backup_staging')).existsSync(),
      isFalse,
      reason: 'failed backups clean their staging directory',
    );
    // The boundary recovers: once the ungated writer finishes, the next
    // backup succeeds.
    gate.end('ungated_writer');
    gate.resetForTest();
    final recovered = await guarded.backupNow();
    expect(store.manifest!.backupId, recovered.backupId);
  });

  test('media/prefs/db uploads read the immutable snapshot, not live files',
      () async {
    await prefs.preferences.setString('currentLanguage', 'tr');
    final racing = _RacingSnapshotService(
      db: db,
      packageInfo: packageInfo,
      officialProfileRoot:
          Directory(p.join(appSupport.path, 'official_anki', 'default')),
      legacyMediaRoot: Directory(p.join(appSupport.path, 'anki_media')),
      gate: StudyActivityGate(),
      mutateAfterBuild: (snapshot) {
        // Simulate every live store mutating after the snapshot was taken:
        // media file rewritten, a pref changed, course.db table created.
        File(p.join(appSupport.path, 'anki_media', 'imp1', 'a.mp3'))
            .writeAsBytesSync([99, 99, 99]);
        prefs.preferences.setString('currentLanguage', 'fr');
        db.customStatement('CREATE TABLE IF NOT EXISTS late_write(x)');
      },
    );
    final service = RemoteBackupService(
      prefs: prefs,
      configStore: configStore,
      snapshotService: racing,
      appSupport: appSupport,
      storeFactory: (_) => store,
    );

    await service.backupNow();

    // Round-trip: restore the published generation and re-derive the truth
    // from it (restore verifies SHA256SUMS internally).
    await service.restoreToStaging(store.manifest!);
    final stagingRoot = RestoreStagingLayout.root(appSupport);
    final prefsPayload = jsonDecode(
        File(p.join(stagingRoot.path, 'prefs.json')).readAsStringSync())
        as Map<String, dynamic>;
    expect(prefsPayload['currentLanguage'], 'tr',
        reason: 'a pref written after the snapshot must not leak into it');
    final stagedCourse = sql.sqlite3.open(
        p.join(stagingRoot.path, 'course.db'),
        mode: sql.OpenMode.readOnly);
    final lateTable = stagedCourse.select(
        "SELECT count(*) AS n FROM sqlite_master WHERE name = 'late_write'");
    expect(lateTable.first['n'], 0,
        reason: 'a db write landing after the snapshot must not leak in');
    stagedCourse.dispose();

    // The uploaded media object still carries the bytes captured at
    // snapshot time ([4,5,6]), and its content-addressed name matches them.
    final media = parseMediaManifest(File(
            p.join(stagingRoot.path, RestoreStagingLayout.mediaManifestEntry))
        .readAsStringSync());
    final sha = media['anki_media/imp1/a.mp3']!.sha256;
    final stagedObject =
        File(p.join(RestoreStagingLayout.media(appSupport).path, sha));
    expect(stagedObject.existsSync(), isTrue);
    expect(stagedObject.readAsBytesSync(), [4, 5, 6],
        reason:
            'uploads read the verified staging copy, not the mutated live file');
    // And the live (mutated) media did not silently poison the object name.
    expect(sha, isNot(archiveFileSha256(
        p.join(appSupport.path, 'anki_media', 'imp1', 'a.mp3'))));
  });

  test('an interrupted upload keeps the previous generation and recovers',
      () async {
    final flaky = _FailingStore(store.storage);
    final service = RemoteBackupService(
      prefs: prefs,
      configStore: configStore,
      snapshotService: snapshotService,
      appSupport: appSupport,
      storeFactory: (_) => flaky,
    );

    final first = await service.backupNow();
    flaky.failCoreUpload = true;
    await expectLater(service.backupNow(), throwsException);
    expect(flaky.manifest!.backupId, first.backupId,
        reason: 'an interrupted upload must never replace the manifest');
    expect(
      Directory(p.join(appSupport.path, 'backup_staging')).existsSync(),
      isFalse,
      reason: 'the failed run cleans its staging directory',
    );

    flaky.failCoreUpload = false;
    final third = await service.backupNow();
    expect(flaky.manifest!.backupId, third.backupId);
    expect(
        flaky.manifest!.history.map((e) => e.backupId), contains(first.backupId));
    expect(
        flaky.manifest!.history.map((e) => e.backupId),
        isNot(contains(predicate<String>(
            (id) => id != first.backupId && id != third.backupId))),
        reason: 'the interrupted generation was never published');
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
