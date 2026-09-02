import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:turna/application/anki_official/official_anki_paths.dart';
import 'package:turna/application/anki_official/storage/official_anki_database.dart';
import 'package:turna/application/anki_official/storage/official_anki_source_dao.dart';
import 'package:turna/application/maintenance/official_anki_ghost_purge_service.dart';

void main() {
  test('fails closed when catalog still has sources', () async {
    final catalog = OfficialAnkiDatabase.memory();
    addTearDown(catalog.close);
    final root = Directory.systemTemp.createTempSync('turna-ghost-src-');
    addTearDown(() {
      try {
        root.deleteSync(recursive: true);
      } catch (_) {}
    });
    final paths = OfficialAnkiPaths(
      profileId: 'profile-default-01',
      profileRoot: root,
    );
    OfficialAnkiSourceDao(catalog).upsertSource(
      sourceId: 'src-live',
      profileId: paths.profileId,
      sourceHash: 'hash',
      sourceSize: 1,
      displayName: 'Live',
      state: 'active',
      backendCommit: 'test',
      nowMillis: 1,
    );
    File(p.join(root.path, 'collection.anki2')).writeAsBytesSync([1, 2, 3]);

    final result = await const OfficialAnkiGhostPurgeService().run(
      catalog: catalog,
      paths: paths,
    );
    expect(result.ok, isFalse);
    expect(result.errorCode, 'sources_present');
    expect(File(p.join(root.path, 'collection.anki2')).existsSync(), isTrue);
  });

  test('deletes leftover collection files when the ledger is empty', () async {
    final catalog = OfficialAnkiDatabase.memory();
    addTearDown(catalog.close);
    final bundle = Directory.systemTemp.createTempSync('turna-ghost-ok-');
    addTearDown(() {
      try {
        bundle.deleteSync(recursive: true);
      } catch (_) {}
    });
    final root = Directory(p.join(bundle.path, 'official_anki', 'default'))
      ..createSync(recursive: true);
    final paths = OfficialAnkiPaths(
      profileId: 'profile-default-01',
      profileRoot: root,
    );
    File(p.join(root.path, 'collection.anki2')).writeAsBytesSync([1, 2, 3, 4]);
    Directory(p.join(root.path, 'collection.media')).createSync();
    File(p.join(root.path, 'collection.media', 'a.png')).writeAsBytesSync([9]);
    Directory(p.join(root.path, 'checkpoints')).createSync();
    File(p.join(root.path, 'checkpoints', 'c.bin')).writeAsBytesSync([8]);
    final staging = Directory(
      p.join(bundle.path, 'official_anki', 'staging', 'orphan-1'),
    )..createSync(recursive: true);
    File(p.join(staging.path, 'x')).writeAsBytesSync([7]);

    final result = await const OfficialAnkiGhostPurgeService().run(
      catalog: catalog,
      paths: paths,
    );
    expect(result.ok, isTrue);
    expect(result.deletedEntries, greaterThan(0));
    expect(File(p.join(root.path, 'collection.anki2')).existsSync(), isFalse);
    expect(staging.existsSync(), isFalse);
    expect(Directory(p.join(root.path, 'collection.media')).existsSync(), isTrue,
        reason: 'ensureLayout recreates the empty media folder');
  });

  test('fails closed without paths', () async {
    final result = await const OfficialAnkiGhostPurgeService().run();
    expect(result.ok, isFalse);
    expect(result.errorCode, 'capability_missing');
  });
}
