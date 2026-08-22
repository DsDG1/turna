// Dart imports:
import 'dart:convert';
import 'dart:io';

// Package imports:
import 'package:archive/archive_io.dart';
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
import 'package:turna/service/remote_backup/backup_manifest.dart';
import 'package:turna/service/remote_backup/backup_snapshot_service.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  ensureOfficialAnkiSqlite();

  late Directory tmp;
  late CourseDatabase db;
  late Directory profileRoot;
  late Directory legacyMedia;
  late BackupSnapshotService service;
  late List<BackupSnapshotPhase> phases;

  final packageInfo = PackageInfo(
    appName: 'turna',
    packageName: 'me.dsdogs.turna',
    version: '0.4.0',
    buildNumber: '42',
  );

  sql.Database makeSqlite(String path, String marker) {
    final database = sql.sqlite3.open(path);
    database.execute('CREATE TABLE t(x TEXT)');
    database.execute("INSERT INTO t VALUES ('$marker')");
    database.dispose();
    return database;
  }

  setUp(() async {
    tmp = await Directory.systemTemp.createTemp('turna_snapshot');
    db = CourseDatabase(NativeDatabase(File(p.join(tmp.path, 'live_course.db'))));

    SharedPreferences.setMockInitialValues(<String, Object>{
      'game.score': 120,
      'currentLanguage': 'tr',
      'settings.autoReadOnTap.builtin': true,
      'remoteBackup.config': '{"password":"do-not-leak"}',
      'system.healthEvent': '{"safeMode":false}',
      'anki.deck.imp1.newDone.20260823': 5,
      'ai.engineConfig':
          '{"apiKey":"sk-secret","preset":"custom","modelChat":"m"}',
    });
    await StreamingSharedPreferences.instance;

    profileRoot = Directory(p.join(tmp.path, 'profile'))..createSync();
    makeSqlite(p.join(profileRoot.path, 'collection.anki2'), 'col');
    makeSqlite(p.join(profileRoot.path, 'official_catalog.sqlite'), 'cat');
    makeSqlite(p.join(profileRoot.path, 'collection.media.db2'), 'mdb');

    legacyMedia = Directory(p.join(tmp.path, 'anki_media'))..createSync();
    File(p.join(legacyMedia.path, 'imp1', 'a.mp3'))
      ..createSync(recursive: true)
      ..writeAsBytesSync([1, 2, 3]);
    File(p.join(legacyMedia.path, 'imp1', 'b.mp3'))
      ..createSync(recursive: true)
      ..writeAsBytesSync([1, 2, 3]); // same content → dedup to one object
    Directory(p.join(profileRoot.path, 'collection.media')).createSync();
    File(p.join(profileRoot.path, 'collection.media', 'x.png'))
        .writeAsBytesSync([9, 9, 9]);

    service = BackupSnapshotService(
      db: db,
      packageInfo: packageInfo,
      officialProfileRoot: profileRoot,
      legacyMediaRoot: legacyMedia,
    );
    phases = <BackupSnapshotPhase>[];
  });

  tearDown(() async {
    await db.close();
    if (tmp.existsSync()) tmp.deleteSync(recursive: true);
  });

  Future<Map<String, dynamic>> readJsonEntry(Archive archive, String name) =>
      Future<Map<String, dynamic>>.value(
        jsonDecode(utf8.decode(archive.findFile(name)!.content))
            as Map<String, dynamic>,
      );

  test('build produces a complete, verifiable snapshot', () async {
    final staging = Directory(p.join(tmp.path, 'staging'));
    final snapshot =
        await service.build(stagingDir: staging, onPhase: phases.add);

    expect(snapshot.backupId, startsWith('bk-'));
    expect(snapshot.coreZip.existsSync(), isTrue);
    expect(snapshot.coreZipSha256, isNotEmpty);
    expect(snapshot.meta.hasCollection, isTrue);
    expect(snapshot.meta.hasCatalog, isTrue);
    expect(snapshot.meta.hasMediaDb, isTrue);
    expect(snapshot.meta.driftSchema, 18);
    expect(snapshot.meta.catalogSchema, 8);
    expect(snapshot.meta.appVersion, '0.4.0');
    expect(phases.first, BackupSnapshotPhase.collectingPrefs);
    expect(phases.last, BackupSnapshotPhase.packingArchive);

    final input = InputFileStream(snapshot.coreZip.path);
    final archive = ZipDecoder().decodeStream(input);
    await input.close();
    final names = archive.files.map((f) => f.name).toSet();
    expect(
      names,
      containsAll([
        'prefs.json',
        'course.db',
        'collection.anki2',
        'official_catalog.sqlite',
        'collection.media.db2',
        'media_manifest.json',
        'meta.json',
        'SHA256SUMS',
      ]),
    );

    final prefsPayload = await readJsonEntry(archive, 'prefs.json');
    expect(prefsPayload['game.score'], 120);
    expect(prefsPayload['currentLanguage'], 'tr');
    expect(prefsPayload['settings.autoReadOnTap.builtin'], isTrue);
    expect(prefsPayload.containsKey('remoteBackup.config'), isFalse,
        reason: 'device-local backup credentials must not travel');
    expect(prefsPayload.containsKey('system.healthEvent'), isFalse);
    expect(prefsPayload.containsKey('anki.deck.imp1.newDone.20260823'), isFalse,
        reason: 'per-day counters must not travel');
    final aiConfig =
        jsonDecode(prefsPayload['ai.engineConfig'] as String) as Map<String, dynamic>;
    expect(aiConfig['apiKey'], '', reason: 'API key must be stripped');
    expect(aiConfig['preset'], 'custom');

    // Staged course.db is a real migrated drift database.
    final stagedCourse = sql.sqlite3.open(p.join(staging.path, 'course.db'),
        mode: sql.OpenMode.readOnly);
    expect(
      stagedCourse.select('PRAGMA user_version').first['user_version'],
      18,
    );
    stagedCourse.dispose();

    final stagedCollection = sql.sqlite3.open(
        p.join(staging.path, 'collection.anki2'),
        mode: sql.OpenMode.readOnly);
    expect(stagedCollection.select('SELECT x FROM t').first['x'], 'col');
    stagedCollection.dispose();

    final media = parseMediaManifest(
        File(p.join(staging.path, 'media_manifest.json')).readAsStringSync());
    expect(
      media.keys,
      containsAll([
        'anki_media/imp1/a.mp3',
        'anki_media/imp1/b.mp3',
        'official/collection.media/x.png',
      ]),
    );
    expect(media['anki_media/imp1/a.mp3']?.sha256,
        media['anki_media/imp1/b.mp3']?.sha256);
    expect(snapshot.mediaObjects.length, 2,
        reason: 'identical content dedups to one upload object');

    final sums = File(p.join(staging.path, 'SHA256SUMS')).readAsLinesSync();
    expect(sums.length, 7);
    expect(sums.first, matches(RegExp(r'^[0-9a-f]{64}  .+$')));
  });

  test('absent official databases snapshot as absent, not as garbage',
      () async {
    final emptyProfile = Directory(p.join(tmp.path, 'empty_profile'))
      ..createSync();
    final bareService = BackupSnapshotService(
      db: db,
      packageInfo: packageInfo,
      officialProfileRoot: emptyProfile,
      legacyMediaRoot: Directory(p.join(tmp.path, 'no_media')),
    );
    final snapshot = await bareService
        .build(stagingDir: Directory(p.join(tmp.path, 'staging2')));

    expect(snapshot.meta.hasCollection, isFalse);
    expect(snapshot.meta.hasCatalog, isFalse);
    expect(snapshot.meta.hasMediaDb, isFalse);
    final input = InputFileStream(snapshot.coreZip.path);
    final archive = ZipDecoder().decodeStream(input);
    await input.close();
    final names = archive.files.map((f) => f.name).toSet();
    expect(names.contains('collection.anki2'), isFalse);
    expect(names.contains('official_catalog.sqlite'), isFalse);
    expect(names.contains('collection.media.db2'), isFalse);
    expect(snapshot.mediaObjects, isEmpty);
  });

  test('includeMedia=false produces an empty media manifest', () async {
    final snapshot = await service.build(
      stagingDir: Directory(p.join(tmp.path, 'staging3')),
      includeMedia: false,
    );
    expect(snapshot.mediaManifest, isEmpty);
    expect(snapshot.mediaObjects, isEmpty);
    final media = parseMediaManifest(
        File(p.join(tmp.path, 'staging3', 'media_manifest.json'))
            .readAsStringSync());
    expect(media, isEmpty);
  });

  test('staging dir is wiped between builds', () async {
    final staging = Directory(p.join(tmp.path, 'staging4'))..createSync();
    File(p.join(staging.path, 'stale.txt')).writeAsStringSync('old');
    await service.build(stagingDir: staging);
    expect(File(p.join(staging.path, 'stale.txt')).existsSync(), isFalse);
  });
}
