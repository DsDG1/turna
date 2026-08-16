import 'package:turna/application/anki_official/engine/official_anki_engine_ffi.dart';
import 'package:turna/application/anki_official/engine/official_anki_native_transport.dart';
import 'package:turna/application/anki_official/engine/official_anki_worker.dart';
import 'package:turna/application/anki_official/import/official_anki_import_orchestrator.dart';
import 'package:turna/application/anki_official/import/official_anki_import_state.dart';
import 'package:turna/application/anki_official/official_anki_paths.dart';
import 'package:turna/application/anki_official/storage/official_anki_database.dart';
import 'package:turna/application/anki_official/storage/official_anki_import_attempt_dao.dart';
import 'package:turna/application/anki_official/storage/official_anki_source_dao.dart';

/// Same-isolate official import when the worker isolate cannot start.
class OfficialAnkiInProcessHost implements OfficialAnkiImporter {
  OfficialAnkiInProcessHost._(this._orchestrator, this._db, this.engine);

  final OfficialAnkiImportOrchestrator _orchestrator;
  final OfficialAnkiDatabase _db;
  final OfficialAnkiWorker engine;

  factory OfficialAnkiInProcessHost.open({
    required OfficialAnkiPaths paths,
    String? libraryPath,
  }) {
    final transport = OfficialAnkiNativeTransport.open(libraryPath: libraryPath);
    final engine = OfficialAnkiWorker(FfiOfficialAnkiEngine.connect(transport));
    final db = OfficialAnkiDatabase.file(paths.catalogFile.path);
    return OfficialAnkiInProcessHost._(
      OfficialAnkiImportOrchestrator(
        engine: engine,
        sources: OfficialAnkiSourceDao(db),
        attempts: OfficialAnkiImportAttemptDao(db),
        paths: paths,
      ),
      db,
      engine,
    );
  }

  @override
  Future<OfficialAnkiImportResult> importFile({
    required String packagePath,
    required String displayName,
    String? requestId,
    bool cancel = false,
  }) {
    return _orchestrator.importFile(
      packagePath: packagePath,
      displayName: displayName,
      requestId: requestId,
      cancel: cancel,
    );
  }

  Future<void> dispose() async {
    await engine.dispose();
    _db.close();
  }
}
