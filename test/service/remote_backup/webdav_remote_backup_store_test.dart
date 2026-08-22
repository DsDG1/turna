// Dart imports:
import 'dart:io';

// Package imports:
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

// Project imports:
import 'package:turna/service/remote_backup/backup_manifest.dart';
import 'package:turna/service/remote_backup/webdav_client.dart';
import 'package:turna/service/remote_backup/webdav_remote_backup_store.dart';

// Test imports:
import 'mini_dav_server.dart';

RemoteBackupManifest buildManifest(String backupId) => RemoteBackupManifest(
      backupId: backupId,
      createdAtUtc: DateTime.utc(2026, 8, 23, 12),
      deviceId: 'dev',
      deviceLabel: 'android',
      appVersion: '0.4.0',
      buildNumber: '42',
      platform: 'android',
      driftSchema: 18,
      catalogSchema: 8,
      coreZipObject: WebDavRemoteBackupStore.coreZipObjectFor(backupId),
      coreZipSha256: 'a' * 64,
      coreZipBytes: 10,
      mediaCount: 0,
      mediaBytes: 0,
      history: const [],
    );

void main() {
  late MiniDavServer server;
  late WebDavRemoteBackupStore store;

  setUp(() async {
    server = MiniDavServer(username: 'alice', password: 'secret');
    await server.start();
    final client = WebDavClient(
      baseUrl: server.baseUri,
      username: 'alice',
      password: 'secret',
    );
    addTearDown(client.close);
    store = WebDavRemoteBackupStore(client, remoteRoot: 'TurnaBackup');
  });

  tearDown(() async {
    await server.stop();
  });

  test('ensureLayout creates the remote folder tree', () async {
    await store.ensureLayout();
    final client = WebDavClient(
      baseUrl: server.baseUri,
      username: 'alice',
      password: 'secret',
    );
    addTearDown(client.close);
    expect(await client.exists('/TurnaBackup/backups'), isTrue);
    expect(await client.exists('/TurnaBackup/media'), isTrue);
  });

  test('fetchManifest returns null before anything is published', () async {
    await store.ensureLayout();
    expect(await store.fetchManifest(), isNull);
  });

  test('publishManifest is atomic and leaves no tmp file behind', () async {
    await store.ensureLayout();
    await store.publishManifest(buildManifest('bk-1'));
    final fetched = await store.fetchManifest();
    expect(fetched?.backupId, 'bk-1');
    expect(fetched?.coreZipObject, 'backups/bk-1/core.zip');
    final client = WebDavClient(
      baseUrl: server.baseUri,
      username: 'alice',
      password: 'secret',
    );
    addTearDown(client.close);
    expect(await client.exists('/TurnaBackup/manifest.json.tmp'), isFalse);
  });

  test('core zip upload / download roundtrip via the object path',
      () async {
    await store.ensureLayout();
    final manifest = buildManifest('bk-2');
    final payload = List<int>.generate(4096, (i) => i % 256);
    final tmp = await Directory.systemTemp.createTemp('store_test');
    addTearDown(() => tmp.deleteSync(recursive: true));
    final source = File(p.join(tmp.path, 'core.zip'));
    await source.writeAsBytes(payload, flush: true);

    await store.uploadCoreZip('bk-2', source);
    final dest = File(p.join(tmp.path, 'downloaded.zip'));
    await store.downloadCoreZip(manifest, dest);
    expect(await dest.readAsBytes(), payload);
  });

  test('media objects are content-addressed and deletable', () async {
    await store.ensureLayout();
    final tmp = await Directory.systemTemp.createTemp('store_media');
    addTearDown(() => tmp.deleteSync(recursive: true));
    final media = File(p.join(tmp.path, 'm.bin'));
    await media.writeAsBytes([1, 2, 3], flush: true);
    const sha = 'abc123';

    expect(await store.hasMediaObject(sha), isFalse);
    await store.uploadMediaObject(sha, media);
    expect(await store.hasMediaObject(sha), isTrue);

    final dest = File(p.join(tmp.path, 'out.bin'));
    await store.downloadMediaObject(sha, dest);
    expect(await dest.readAsBytes(), [1, 2, 3]);

    await store.deleteBackup('bk-none');
    await store.uploadCoreZip('bk-3', media);
    await store.deleteBackup('bk-3');
  });
}
