import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:turna/application/anki_official/contract/official_anki_contract.dart';
import 'package:turna/application/anki_official/engine/official_anki_engine_ffi.dart';
import 'package:turna/application/anki_official/engine/official_anki_native_transport.dart';
import 'package:turna/application/anki_official/engine/official_anki_session.dart';
import 'package:turna/application/anki_official/official_anki_paths.dart';
import 'package:turna/application/anki_official/storage/official_anki_database.dart';
import 'package:turna/application/anki_official/storage/official_anki_import_attempt_dao.dart';
import 'package:turna/application/anki_official/storage/official_anki_source_dao.dart';
import 'package:turna/application/anki_official/import/official_anki_import_orchestrator.dart';
import 'package:turna/application/anki_official/import/official_anki_import_state.dart';

bool get _requireNative =>
    Platform.environment['TURNA_ANKI_REQUIRE_NATIVE'] == '1';

void main() {
  final libraryPath = resolveOfficialAnkiLibraryPath();

  test('production transport loads Host .so and reports runtime metadata', () async {
    if (libraryPath == null) {
      if (_requireNative) {
        fail('libturna_anki.so missing; TURNA_ANKI_REQUIRE_NATIVE=1');
      }
      return;
    }
    final transport = OfficialAnkiNativeTransport.open(libraryPath: libraryPath);
    expect(transport.abiVersion(), 1);
    final engine = FfiOfficialAnkiEngine.connect(transport);
    addTearDown(engine.dispose);
    final info = await engine.engineInfo();
    expect(info.abiVersion, 1);
    expect(info.contractMajor, 1);
    expect(info.backendCommit, isNotEmpty);
    expect(info.backendCommit, isNot('unknown'));
    expect(info.has(OfficialAnkiOperation.importPackage), isTrue);
  });

  test('Dart allocator → C ABI → rslib → catalog for unicode fixture', () async {
    if (libraryPath == null) {
      if (_requireNative) {
        fail('libturna_anki.so missing; TURNA_ANKI_REQUIRE_NATIVE=1');
      }
      return;
    }
    final root = Directory.systemTemp.createTempSync('turna-host-ffi-');
    addTearDown(() => root.deleteSync(recursive: true));
    final paths = OfficialAnkiPaths(
      profileId: 'profile-host-ffi01',
      profileRoot: Directory('${root.path}/profile'),
    );
    final transport = OfficialAnkiNativeTransport.open(libraryPath: libraryPath);
    final engine = FfiOfficialAnkiEngine.connect(transport);
    addTearDown(engine.dispose);
    final db = OfficialAnkiDatabase.file('${root.path}/catalog.sqlite');
    addTearDown(db.close);
    final pkg = File(
      p.absolute('test/fixtures/anki_official/packages/01-basic-unicode.apkg'),
    );
    final imported = await OfficialAnkiImportOrchestrator(
      engine: engine,
      sources: OfficialAnkiSourceDao(db),
      attempts: OfficialAnkiImportAttemptDao(db),
      paths: paths,
    ).importFile(packagePath: pkg.path, displayName: 'unicode');
    expect(imported.state, OfficialAnkiSourceState.active);
    expect(imported.cardCount, greaterThan(0));
    expect(imported.noteCount, greaterThan(0));
    await engine.closeCollection();
    await engine.openProfile(paths);
    await engine.checkCollection();
    final listed = OfficialAnkiSourceDao(db).findById(imported.sourceId);
    expect(listed?.state, 'active');
  });

  test('worker isolate heartbeat continues during fake import', () async {
    final root = Directory.systemTemp.createTempSync('turna-isolate-');
    addTearDown(() => root.deleteSync(recursive: true));
    final paths = OfficialAnkiPaths(
      profileId: 'profile-isolate01',
      profileRoot: Directory('${root.path}/profile'),
    );
    final session = await OfficialAnkiSession.spawn(
      paths: paths,
      catalogPath: '${root.path}/catalog.sqlite',
      useFake: true,
    );
    addTearDown(session.dispose);
    var ticks = 0;
    final ticker = Stream<int>.periodic(const Duration(milliseconds: 20), (i) => i)
        .listen((_) => ticks++);
    addTearDown(ticker.cancel);
    final pkg = File(
      p.join('test/fixtures/anki_official/packages/01-basic-unicode.apkg'),
    );
    final imported = await session.importFile(
      packagePath: pkg.path,
      displayName: 'isolate-unicode',
    );
    expect(imported.state, OfficialAnkiSourceState.active);
    expect(ticks, greaterThan(0));
  });
}
