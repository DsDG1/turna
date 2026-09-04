import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:turna/application/anki_official/contract/official_anki_errors.dart';
import 'package:turna/application/anki_official/engine/official_anki_engine_fake.dart';
import 'package:turna/application/anki_official/engine/official_anki_worker.dart';
import 'package:turna/application/anki_official/import/anki_import_facade.dart';
import 'package:turna/application/anki_official/import/official_anki_import_saga.dart';
import 'package:turna/application/anki_official/import/official_anki_import_state.dart';
import 'package:turna/application/anki_official/official_anki_composition.dart';
import 'package:turna/application/anki_official/official_anki_feature_flags.dart';
import 'package:turna/application/anki_official/official_anki_paths.dart';
import 'package:turna/application/anki_official/storage/official_anki_database.dart';
import 'package:turna/application/anki_official/storage/official_anki_import_attempt_dao.dart';
import 'package:turna/application/anki_official/storage/official_anki_source_dao.dart';

class _Harness {
  _Harness() {
    db = OfficialAnkiDatabase.memory();
    sources = OfficialAnkiSourceDao(db);
    attempts = OfficialAnkiImportAttemptDao(db);
    engine = FakeOfficialAnkiEngine();
    final root = Directory.systemTemp.createTempSync('turna-official-profile-');
    paths = OfficialAnkiPaths(profileId: 'profile-test-01', profileRoot: root);
    OfficialAnkiCompositionRoot.debugStagingEngineOverride = engine;
    OfficialAnkiCompositionRoot.stagingDiscardRequested = false;
  }

  late final OfficialAnkiDatabase db;
  late final OfficialAnkiSourceDao sources;
  late final OfficialAnkiImportAttemptDao attempts;
  late final FakeOfficialAnkiEngine engine;
  late final OfficialAnkiPaths paths;

  OfficialAnkiImportSaga saga() => OfficialAnkiImportSaga(
        sources: sources,
        attempts: attempts,
        paths: paths,
      );

  void dispose() {
    OfficialAnkiCompositionRoot.debugStagingEngineOverride = null;
    OfficialAnkiCompositionRoot.stagingEngine = null;
    OfficialAnkiCompositionRoot.stagingSession = null;
    OfficialAnkiCompositionRoot.stagingDiscardRequested = false;
    db.close();
    paths.profileRoot.deleteSync(recursive: true);
  }
}

void main() {
  final fixtureRoot = Directory('test/fixtures/anki_official');
  final manifest = jsonDecode(
    File(p.join(fixtureRoot.path, 'manifest.json')).readAsStringSync(),
  ) as Map<String, dynamic>;
  final packages =
      (manifest['packages'] as List).cast<Map<String, dynamic>>();

  test('startStaging indexes the nine frozen fixtures', () async {
    final harness = _Harness();
    addTearDown(harness.dispose);
    for (final pkg in packages) {
      final file = File(p.join(fixtureRoot.path, 'packages', pkg['file'] as String));
      harness.engine.seedPackage(
        packagePath: file.path,
        notes: pkg['expectedNotes'] as int,
        cards: pkg['expectedCards'] as int,
      );
      final imported = await harness.saga().startStaging(
        packagePath: file.path,
        displayName: pkg['file'] as String,
      );
      expect(imported.state, OfficialAnkiSourceState.previewReady);
      expect(imported.cardCount, pkg['expectedCards']);
      expect(imported.noteCount, pkg['expectedNotes']);
      expect(harness.sources.findById(imported.sourceId)!.state, 'staging');
    }
    expect(harness.sources.listSources(harness.paths.profileId), hasLength(9));
  });

  test('close/reopen catalog still lists the staged source', () async {
    final root = Directory.systemTemp.createTempSync('turna-catalog-reopen-');
    addTearDown(() => root.deleteSync(recursive: true));
    final catalogPath = '${root.path}/catalog.sqlite';
    final file = File(
      p.join(fixtureRoot.path, 'packages', '01-basic-unicode.apkg'),
    );
    final engine = FakeOfficialAnkiEngine();
    engine.seedPackage(packagePath: file.path, notes: 1, cards: 1);
    OfficialAnkiCompositionRoot.debugStagingEngineOverride = engine;
    OfficialAnkiCompositionRoot.stagingDiscardRequested = false;
    addTearDown(() {
      OfficialAnkiCompositionRoot.debugStagingEngineOverride = null;
      OfficialAnkiCompositionRoot.stagingEngine = null;
      OfficialAnkiCompositionRoot.stagingDiscardRequested = false;
    });
    final paths = OfficialAnkiPaths(
      profileId: 'profile-reopen-01',
      profileRoot: Directory('${root.path}/profile'),
    );
    final firstDb = OfficialAnkiDatabase.file(catalogPath);
    final first = await OfficialAnkiImportSaga(
      sources: OfficialAnkiSourceDao(firstDb),
      attempts: OfficialAnkiImportAttemptDao(firstDb),
      paths: paths,
    ).startStaging(packagePath: file.path, displayName: 'unicode');
    expect(first.state, OfficialAnkiSourceState.previewReady);
    firstDb.close();
    final again = OfficialAnkiDatabase.file(catalogPath);
    addTearDown(again.close);
    final listed = OfficialAnkiSourceDao(again).findById(first.sourceId);
    expect(listed?.state, 'staging');
  });

  test('startStaging does not write live Collection', () async {
    final harness = _Harness();
    addTearDown(harness.dispose);
    final file = File(
      p.join(fixtureRoot.path, 'packages', '02-basic-reversed.apkg'),
    );
    harness.engine.seedPackage(packagePath: file.path, notes: 1, cards: 2);
    final live = FakeOfficialAnkiEngine();
    OfficialAnkiCompositionRoot.debugEngineOverride = live;
    addTearDown(() => OfficialAnkiCompositionRoot.debugEngineOverride = null);
    await harness.saga().startStaging(
      packagePath: file.path,
      displayName: 'reversed',
    );
    expect(harness.sources.listSources(harness.paths.profileId), hasLength(1));
    expect(live.importCount, 0);
  });

  test('cancelActive leaves source not active', () async {
    final harness = _Harness();
    addTearDown(harness.dispose);
    final file = File(
      p.join(fixtureRoot.path, 'packages', '01-basic-unicode.apkg'),
    );
    harness.engine.seedPackage(packagePath: file.path, notes: 1, cards: 1);
    final result = await harness.saga().startStaging(
      packagePath: file.path,
      displayName: 'cancel-me',
    );
    await harness.saga().cancelActive();
    expect(harness.sources.findById(result.sourceId), isNull);
  });

  test('5k generated package stages with expected counts', () async {
    final harness = _Harness();
    addTearDown(harness.dispose);
    final large = File(
      p.join(fixtureRoot.path, 'generated', '10-large-generated-5000.apkg'),
    );
    expect(large.existsSync(), isTrue);
    harness.engine.seedPackage(packagePath: large.path, notes: 5000, cards: 5000);
    final result = await harness.saga().startStaging(
      packagePath: large.path,
      displayName: '5k',
    );
    expect(result.state, OfficialAnkiSourceState.previewReady);
    expect(result.cardCount, 5000);
    expect(result.noteCount, 5000);
  });

  test('catalog has no field/html/template/css/schedule columns', () {
    final db = OfficialAnkiDatabase.memory();
    addTearDown(db.close);
    final names = db.handle
        .select('PRAGMA table_info(anki_source_cards)')
        .map((row) => row['name'] as String)
        .toSet();
    expect(names, containsAll(['card_id', 'note_id', 'deck_id', 'template_ord']));
    expect(names, isNot(contains('fields')));
    expect(names, isNot(contains('qfmt')));
    expect(names, isNot(contains('css')));
    expect(names, isNot(contains('html')));
    expect(names, isNot(contains('queue')));
  });

  test('future schema version fails closed', () {
    final root = Directory.systemTemp.createTempSync('turna-catalog-future-');
    addTearDown(() => root.deleteSync(recursive: true));
    final path = '${root.path}/catalog.sqlite';
    final created = OfficialAnkiDatabase.file(path);
    created.handle.execute('PRAGMA user_version = 99');
    created.close();
    expect(
      () => OfficialAnkiDatabase.file(path),
      throwsA(isA<Object>()),
    );
  });

  test('empty constructor stays off; production fromEnvironment import is on', () {
    expect(const OfficialAnkiFeatureFlags().import, isFalse);
    expect(const OfficialAnkiFeatureFlags().allowsOfficialImport, isFalse);
    expect(OfficialAnkiFeatureFlags.current.import, isTrue);
    expect(OfficialAnkiFeatureFlags.current.allowsOfficialImport, isTrue);
    expect(
      () => AnkiImportFacade.resolve(
        flags: const OfficialAnkiFeatureFlags(),
      ),
      throwsA(isA<OfficialAnkiException>()),
    );
    expect(
      () => AnkiImportFacade.resolve(
        flags: const OfficialAnkiFeatureFlags(import: true, engine: false),
        cutoverEnabled: true,
        platform: 'android',
      ),
      throwsA(isA<OfficialAnkiException>()),
    );
  });

  test('worker serializes overlapping open/import/close', () async {
    final harness = _Harness();
    addTearDown(harness.dispose);
    final worker = OfficialAnkiWorker(harness.engine);
    final file = File(
      p.join(fixtureRoot.path, 'packages', '01-basic-unicode.apkg'),
    );
    harness.engine.seedPackage(packagePath: file.path, notes: 1, cards: 1);
    await Future.wait([
      worker.openProfile(harness.paths),
      worker.checkCollection(),
      worker.closeCollection(),
    ]);
    expect(harness.engine.openCount, 1);
  });
}
