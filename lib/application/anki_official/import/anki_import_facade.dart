import 'package:turna/application/anki/anki_importer.dart';
import 'package:turna/application/anki_official/contract/official_anki_errors.dart';
import 'package:turna/application/anki_official/import/official_anki_import_orchestrator.dart';
import 'package:turna/application/anki_official/import/official_anki_import_state.dart';
import 'package:turna/application/anki_official/official_anki_feature_flags.dart';

abstract class AnkiImportFacade {
  bool get isOfficial;

  Future<OfficialAnkiImportResult?> importOfficialOrNull({
    required String packagePath,
    required String displayName,
  });

  static AnkiImportFacade resolve({
    OfficialAnkiFeatureFlags? flags,
    OfficialAnkiImportOrchestrator? official,
    AnkiImporter? legacyImporter,
  }) {
    final resolved = flags ?? OfficialAnkiFeatureFlags.current;
    if (resolved.import && !resolved.allowsOfficialImport) {
      throw const OfficialAnkiException(
        code: OfficialAnkiErrorCode.capabilityMissing,
        messageKey: 'official_anki.flag_fail_closed',
      );
    }
    if (resolved.allowsOfficialImport) {
      if (official == null) {
        throw const OfficialAnkiException(
          code: OfficialAnkiErrorCode.capabilityMissing,
          messageKey: 'official_anki.flag_fail_closed',
        );
      }
      return OfficialAnkiImportFacade(official);
    }
    return LegacyAnkiImportFacade(legacyImporter ?? AnkiImporter());
  }
}

class OfficialAnkiImportFacade implements AnkiImportFacade {
  OfficialAnkiImportFacade(this._orchestrator);

  final OfficialAnkiImportOrchestrator _orchestrator;

  @override
  bool get isOfficial => true;

  @override
  Future<OfficialAnkiImportResult?> importOfficialOrNull({
    required String packagePath,
    required String displayName,
  }) {
    return _orchestrator.importFile(
      packagePath: packagePath,
      displayName: displayName,
    );
  }
}

class LegacyAnkiImportFacade implements AnkiImportFacade {
  LegacyAnkiImportFacade(this.importer);

  final AnkiImporter importer;

  @override
  bool get isOfficial => false;

  @override
  Future<OfficialAnkiImportResult?> importOfficialOrNull({
    required String packagePath,
    required String displayName,
  }) async {
    return null;
  }
}
