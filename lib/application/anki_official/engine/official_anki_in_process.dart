import 'package:turna/application/anki_official/engine/official_anki_engine_ffi.dart';
import 'package:turna/application/anki_official/engine/official_anki_native_transport.dart';
import 'package:turna/application/anki_official/engine/official_anki_worker.dart';
import 'package:turna/application/anki_official/import/official_anki_import_state.dart';
import 'package:turna/application/anki_official/official_anki_paths.dart';
import 'package:turna/application/anki_official/projection/official_anki_course_entry.dart';
import 'package:turna/application/anki_official/storage/official_anki_database.dart';

/// Same-isolate official import when the worker isolate cannot start.
class OfficialAnkiInProcessHost implements OfficialAnkiImporter {
  OfficialAnkiInProcessHost._(this._db, this.engine);

  final OfficialAnkiDatabase _db;
  final OfficialAnkiWorker engine;

  factory OfficialAnkiInProcessHost.open({
    required OfficialAnkiPaths paths,
    String? libraryPath,
  }) {
    final transport = OfficialAnkiNativeTransport.open(libraryPath: libraryPath);
    final engine = OfficialAnkiWorker(FfiOfficialAnkiEngine.connect(transport));
    final db = OfficialAnkiDatabase.file(paths.catalogFile.path);
    OfficialAnkiCourseEntry.catalogOf = () => db;
    return OfficialAnkiInProcessHost._(db, engine);
  }

  @override
  Future<OfficialAnkiImportResult> importFile({
    required String packagePath,
    required String displayName,
    String? requestId,
    bool cancel = false,
  }) async {
    if (cancel) {
      await engine.cancel();
      return OfficialAnkiImportResult(
        sourceId: '',
        attemptId: requestId ?? '',
        state: OfficialAnkiSourceState.cancelled,
        cardCount: 0,
        noteCount: 0,
      );
    }
    final log = await engine.importPackage(packagePath: packagePath);
    return OfficialAnkiImportResult(
      sourceId: '',
      attemptId: requestId ?? '',
      state: OfficialAnkiSourceState.previewReady,
      cardCount: log.cardCount,
      noteCount: log.noteCount,
    );
  }

  Future<void> dispose() async {
    await engine.dispose();
    _db.close();
  }
}
