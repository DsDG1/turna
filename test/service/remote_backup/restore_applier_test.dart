// Dart imports:
import 'dart:convert';
import 'dart:io';

// Package imports:
import 'package:crypto/crypto.dart';
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
import 'package:turna/service/remote_backup/backup_snapshot_service.dart';
import 'package:turna/service/remote_backup/remote_backup_config.dart';
import 'package:turna/service/remote_backup/restore_applier.dart';
import 'package:turna/service/remote_backup/restore_staging.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  ensureOfficialAnkiSqlite();

  late Directory tmp;
  late Directory appSupport;
  late Directory appDocuments;
  late Directory profileRoot;
  late CourseDatabase db;
  late AppPrefs prefs;

  String sha256File(List<int> bytes) {
    final digest = sha256.convert(bytes);
    return digest.toString();
  }

  void regenerateSums(Directory staging, BackupSnapshot snapshot) {
    final names = <String>[
      'prefs.json',
      'course.db',
      if (snapshot.meta.hasCollection) 'collection.anki2',
      if (snapshot.meta.hasCatalog) 'official_catalog.sqlite',
      if (snapshot.meta.hasMediaDb) 'collection.media.db2',
      'media_manifest.json',
      'meta.json',
    ];
    final digestOf = <String, String>{};
    for (final name in names) {
      digestOf[name] =
          sha256File(File(p.join(staging.path, name)).readAsBytesSync());
    }
    File(p.join(staging.path, 'SHA256SUMS')).writeAsStringSync(
      "${[for (final name in names) '${digestOf[name]}  $name'].join('\n')}\n",
    );
  }

  /// Builds a staged restore by running a real snapshot into the staging
  /// layout, then placing media objects and the marker exactly like
  /// RemoteBackupService.restoreToStaging would after a download.
  Future<void> stageRestore({bool newerSchema = false}) async {
    final snapshotService = BackupSnapshotService(
      db: db,
      packageInfo: PackageInfo(
        appName: 'turna',
        packageName: 'me.dsdogs.turna',
        version: '0.4.0',
        buildNumber: '42',
      ),
      officialProfileRoot: profileRoot,
      legacyMediaRoot: Directory(p.join(appSupport.path, 'anki_media')),
    );

    // Local source data the snapshot is taken from.
    for (final name in [
      'collection.anki2',
      'official_catalog.sqlite',
      'collection.media.db2'
    ]) {
      final source = sql.sqlite3.open(p.join(profileRoot.path, name));
      source.execute('CREATE TABLE t(x)');
      source.execute("INSERT INTO t VALUES ('$name')");
      source.dispose();
    }
    Directory(p.join(profileRoot.path, 'collection.media')).createSync();
    File(p.join(profileRoot.path, 'collection.media', 'a.png'))
        .writeAsBytesSync([1, 2, 3]);
    final legacy = Directory(p.join(appSupport.path, 'anki_media'))
      ..createSync();
    File(p.join(legacy.path, 'imp1', 'a.mp3'))
      ..createSync(recursive: true)
      ..writeAsBytesSync([4, 5, 6]);

    final snapshot = await snapshotService.build(
        stagingDir: RestoreStagingLayout.root(appSupport));

    // The snapshot staged the *source* files; relocate the media objects
    // into staging/media/<sha> as the downloader does.
    final mediaDir = RestoreStagingLayout.media(appSupport)
      ..createSync(recursive: true);
    for (final object in snapshot.mediaObjects.entries) {
      await File(object.value).copy(p.join(mediaDir.path, object.key));
    }
    // core.zip rides along in staging; the applier ignores it.
    if (newerSchema) {
      final metaFile = File(
          p.join(RestoreStagingLayout.root(appSupport).path, 'meta.json'));
      final meta = jsonDecode(metaFile.readAsStringSync())
          as Map<String, dynamic>;
      meta['driftSchema'] = 99;
      metaFile.writeAsStringSync(jsonEncode(meta));
      // meta.json is covered by SHA256SUMS — recompute the sums file.
      regenerateSums(RestoreStagingLayout.root(appSupport), snapshot);
    }
    await File(RestoreStagingLayout.marker(appSupport).path).writeAsString(
        RestoreStagingLayout.encodeMarker(
            backupId: snapshot.backupId,
            createdAtUtc: snapshot.meta.createdAtUtc,
            sourceAppVersion: snapshot.meta.appVersion));
  }



  setUp(() async {
    tmp = await Directory.systemTemp.createTemp('turna_restore_applier');
    appSupport = Directory(p.join(tmp.path, 'support'))..createSync();
    appDocuments = Directory(p.join(tmp.path, 'documents'))..createSync();
    profileRoot = Directory(p.join(appSupport.path, 'official_anki', 'default'))
      ..createSync(recursive: true);

    db = CourseDatabase(
        NativeDatabase.memory()); // schema source, not restored into

    SharedPreferences.setMockInitialValues(<String, Object>{
      'game.score': 500, // travels through the snapshot into the restore
      'remoteBackup.deviceId': 'local-device',
    });
    final sp = await StreamingSharedPreferences.instance;
    prefs = AppPrefs(sp);
    ensureRemoteBackupDeviceId(prefs);
  });

  tearDown(() async {
    await db.close();
    if (tmp.existsSync()) tmp.deleteSync(recursive: true);
  });

  RestoreApplier buildApplier() => RestoreApplier(
        prefs: prefs,
        appSupport: appSupport,
        appDocuments: appDocuments,
        officialProfileRoot: profileRoot,
        currentDriftSchema: 18,
        currentCatalogSchema: 8,
      );

  test('no marker → noPending, no side effects', () async {
    final outcome = await buildApplier().applyIfPending();
    expect(outcome, RestoreApplyOutcome.noPending);
    expect(appDocuments.listSync(), isEmpty);
  });

  test('applied: databases replaced, media placed, prefs written, staging '
      'cleaned', () async {
    await stageRestore();
    // Diverge the local state the restore must overwrite.
    await prefs.preferences.setInt('game.score', 1);
    File(p.join(appDocuments.path, 'course.db'))
        .writeAsBytesSync([9, 9, 9, 9]);
    File(p.join(appDocuments.path, 'course.db-wal')).writeAsBytesSync([1]);

    final outcome = await buildApplier().applyIfPending();
    expect(outcome, RestoreApplyOutcome.applied);

    final course = sql.sqlite3.open(p.join(appDocuments.path, 'course.db'),
        mode: sql.OpenMode.readOnly);
    expect(
      course.select('PRAGMA user_version').first['user_version'],
      18,
    );
    course.dispose();
    expect(File(p.join(appDocuments.path, 'course.db-wal')).existsSync(),
        isFalse,
        reason: 'stale WAL must not survive a restore');

    final collection = sql.sqlite3.open(
        p.join(profileRoot.path, 'collection.anki2'),
        mode: sql.OpenMode.readOnly);
    expect(collection.select('SELECT x FROM t').first['x'], 'collection.anki2');
    collection.dispose();

    expect(File(p.join(appDocuments.path, 'anki_media', 'imp1', 'a.mp3'))
        .readAsBytesSync(), [4, 5, 6]);
    expect(
        File(p.join(profileRoot.path, 'collection.media', 'a.png'))
            .readAsBytesSync(),
        [1, 2, 3]);

    expect(
      prefs.preferences.getInt('game.score', defaultValue: -1).getValue(),
      500,
      reason: 'restored prefs overwrite local values',
    );

    expect(RestoreStagingLayout.marker(appSupport).existsSync(), isFalse);
    expect(RestoreStagingLayout.root(appSupport).existsSync(), isFalse);
    expect(
      prefs.preferences
          .getString(LocalStateKeys.remoteBackupLastRestoredAt,
              defaultValue: '')
          .getValue(),
      isNotEmpty,
    );
    expect(
      prefs.preferences
          .getString(LocalStateKeys.remoteBackupDeviceId, defaultValue: '')
          .getValue(),
      'local-device',
      reason: 'device identity must survive a restore',
    );
  });

  test('blocked: a newer-schema backup is refused and staging is discarded',
      () async {
    await stageRestore(newerSchema: true);
    final courseFile = File(p.join(appDocuments.path, 'course.db'))
      ..createSync(recursive: true);
    courseFile.writeAsBytesSync([7]);

    final outcome = await buildApplier().applyIfPending();
    expect(outcome, RestoreApplyOutcome.blocked);
    expect(courseFile.readAsBytesSync(), [7],
        reason: 'local data must be untouched when blocked');
    expect(RestoreStagingLayout.root(appSupport).existsSync(), isFalse);
    expect(
      prefs.preferences
          .getString(LocalStateKeys.remoteBackupRestoreBlockedReason,
              defaultValue: '')
          .getValue(),
      contains('升级'),
    );
  });

  test('corrupt marker is discarded as noPending', () async {
    await RestoreStagingLayout.root(appSupport).create(recursive: true);
    await RestoreStagingLayout.marker(appSupport).writeAsString('{broken');
    expect(
        await buildApplier().applyIfPending(), RestoreApplyOutcome.noPending);
    expect(RestoreStagingLayout.root(appSupport).existsSync(), isFalse);
  });
}
