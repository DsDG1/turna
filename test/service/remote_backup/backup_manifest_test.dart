// Package imports:
import 'package:flutter_test/flutter_test.dart';

// Project imports:
import 'package:turna/service/remote_backup/backup_manifest.dart';

RemoteBackupManifest buildManifest({String backupId = 'bk-1'}) =>
    RemoteBackupManifest(
      backupId: backupId,
      createdAtUtc: DateTime.utc(2026, 8, 23, 10, 30),
      deviceId: 'device-a',
      deviceLabel: 'android',
      appVersion: '0.4.0',
      buildNumber: '42',
      platform: 'android',
      driftSchema: 18,
      catalogSchema: 8,
      coreZipObject: '/TurnaBackup/backups/bk-1/core.zip',
      coreZipSha256: 'deadbeef',
      coreZipBytes: 1234,
      mediaCount: 7,
      mediaBytes: 98765,
      history: const [],
    );

void main() {
  test('manifest roundtrips through json', () {
    final manifest = buildManifest();
    final restored = RemoteBackupManifest.fromJson(manifest.toJson());
    expect(restored.backupId, 'bk-1');
    expect(restored.driftSchema, 18);
    expect(restored.catalogSchema, 8);
    expect(restored.coreZipBytes, 1234);
    expect(restored.deviceId, 'device-a');
    expect(restored.createdAtUtc, DateTime.utc(2026, 8, 23, 10, 30));
  });

  test('a manifest from a newer schema is rejected', () {
    final json = buildManifest().toJson()
      ..['schema'] = kRemoteBackupManifestSchema + 1;
    expect(
      () => RemoteBackupManifest.fromJson(json),
      throwsA(isA<RemoteBackupManifestFutureVersion>()),
    );
  });

  test(
      'mergeHistory keeps previous generations, dedups and caps the '
      'retention window', () {
    // Server state: head bk-9 with a full history tail.
    final previous = buildManifest(backupId: 'bk-9');
    final history = <RemoteBackupManifestEntry>[
      for (var i = 8; i >= 1; i--)
        RemoteBackupManifestEntry(
          backupId: 'bk-$i',
          createdAtUtc: DateTime.utc(2026, 8, 20),
          coreZipObject: '/TurnaBackup/backups/bk-$i/core.zip',
          coreZipSha256: '$i',
          coreZipBytes: i,
          mediaCount: 0,
          mediaBytes: 0,
        ),
    ];
    final withTail = previous.copyWithHistory(history);

    final merged = RemoteBackupManifest.mergeHistory(withTail);

    expect(merged.first.backupId, 'bk-9');
    expect(merged.length, kRemoteBackupRetention);
    expect(
      merged.map((e) => e.backupId).toSet().length,
      merged.length,
      reason: 'history must not repeat a backupId',
    );
  });

  test('mergeHistory handles a first-ever backup (no previous manifest)', () {
    expect(RemoteBackupManifest.mergeHistory(null), isEmpty);
  });

  test('BackupArchiveMeta roundtrips', () {
    final meta = BackupArchiveMeta(
      appVersion: '0.4.0',
      buildNumber: '42',
      platform: 'android',
      deviceLabel: 'android',
      driftSchema: 18,
      catalogSchema: 8,
      createdAtUtc: DateTime.utc(2026, 8, 23),
      hasCollection: true,
      hasCatalog: true,
      hasMediaDb: false,
      prefsCount: 55,
    );
    final restored = BackupArchiveMeta.fromJson(meta.toJson());
    expect(restored.appVersion, '0.4.0');
    expect(restored.hasCollection, isTrue);
    expect(restored.hasMediaDb, isFalse);
    expect(restored.prefsCount, 55);
  });

  test('media manifest roundtrips', () {
    final manifest = <String, MediaManifestEntry>{
      'anki_media/imp1/a.mp3':
          const MediaManifestEntry(sha256: 'aa', bytes: 10),
      'official/collection.media/b.png':
          const MediaManifestEntry(sha256: 'bb', bytes: 20),
    };
    final restored = parseMediaManifest(encodeMediaManifest(manifest));
    expect(restored.keys, containsAll(manifest.keys));
    expect(restored['anki_media/imp1/a.mp3']?.bytes, 10);
    expect(restored['official/collection.media/b.png']?.sha256, 'bb');
  });
}

extension _CopyWithHistory on RemoteBackupManifest {
  RemoteBackupManifest copyWithHistory(List<RemoteBackupManifestEntry> h) =>
      RemoteBackupManifest(
        backupId: backupId,
        createdAtUtc: createdAtUtc,
        deviceId: deviceId,
        deviceLabel: deviceLabel,
        appVersion: appVersion,
        buildNumber: buildNumber,
        platform: platform,
        driftSchema: driftSchema,
        catalogSchema: catalogSchema,
        coreZipObject: coreZipObject,
        coreZipSha256: coreZipSha256,
        coreZipBytes: coreZipBytes,
        mediaCount: mediaCount,
        mediaBytes: mediaBytes,
        history: h,
      );
}
