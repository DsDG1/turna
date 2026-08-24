import 'package:turna/application/anki/anki_importer.dart';
import 'package:turna/application/anki_official/contract/official_anki_errors.dart';
import 'package:turna/application/anki_official/engine/official_anki_native_availability.dart';
import 'package:turna/application/anki_official/import/official_anki_import_orchestrator.dart';
import 'package:turna/application/anki_official/import/official_anki_import_state.dart';
import 'package:turna/application/anki_official/migration/official_anki_engine_kind.dart';
import 'package:turna/application/anki_official/migration/official_anki_gray_config.dart';
import 'package:turna/application/anki_official/official_anki_feature_flags.dart';

enum AnkiImportDecision { official, legacy, failClosed }

abstract class AnkiImportFacade {
  bool get isOfficial;

  Future<OfficialAnkiImportResult?> importOfficialOrNull({
    required String packagePath,
    required String displayName,
  });

  static AnkiImportDecision decisionFor(
    OfficialAnkiFeatureFlags flags, {
    bool? cutoverEnabled,
    String? platform,
    OfficialAnkiGrayConfig? gray,
    bool? libraryAvailable,
  }) {
    final cutover =
        cutoverEnabled ?? LegacyAnkiMigrationFlags.cutoverEnabled;
    final plat = platform ?? OfficialAnkiCapabilityMatrix.current().platform;
    if (!cutover) return AnkiImportDecision.legacy;
    if (plat != 'android') return AnkiImportDecision.legacy;
    if (!flags.allowsOfficialImport) return AnkiImportDecision.failClosed;
    final g = gray ?? OfficialAnkiGrayConfig.fromEnvironment();
    if (!g.allowsNewOfficialImport(
      platform: plat,
      cutoverEnabled: cutover,
    )) {
      return AnkiImportDecision.legacy;
    }
    // Flags say official but the native library is physically absent
    // (unpackaged .so / wrong ABI): degrade to the legacy importer instead
    // of fail-closing — this mirrors what non-Android platforms do, and the
    // availability probe reports the defect loudly.
    final libraryOk =
        libraryAvailable ?? OfficialAnkiNativeAvailability.current;
    if (!libraryOk) return AnkiImportDecision.legacy;
    return AnkiImportDecision.official;
  }

  static AnkiImportFacade resolve({
    OfficialAnkiFeatureFlags? flags,
    OfficialAnkiImportOrchestrator? official,
    OfficialAnkiImporter? officialImporter,
    AnkiImporter? legacyImporter,
    bool? cutoverEnabled,
    String? platform,
  }) {
    final resolved = flags ?? OfficialAnkiFeatureFlags.current;
    final decision = decisionFor(
      resolved,
      cutoverEnabled: cutoverEnabled,
      platform: platform,
    );
    if (decision == AnkiImportDecision.failClosed) {
      throw const OfficialAnkiException(
        code: OfficialAnkiErrorCode.capabilityMissing,
        messageKey: 'official_anki.flag_fail_closed',
      );
    }
    if (decision == AnkiImportDecision.official) {
      final importer = officialImporter ?? official;
      if (importer == null) {
        throw const OfficialAnkiException(
          code: OfficialAnkiErrorCode.invalidState,
          messageKey: 'official_anki.importer_not_ready',
          debugDetails:
              'OfficialAnkiImporter must be initialized before resolving facade',
        );
      }
      return OfficialAnkiImportFacade(importer);
    }
    return LegacyAnkiImportFacade(legacyImporter ?? AnkiImporter());
  }
}

class OfficialAnkiImportFacade implements AnkiImportFacade {
  OfficialAnkiImportFacade(this._importer);

  final OfficialAnkiImporter _importer;

  @override
  bool get isOfficial => true;

  @override
  Future<OfficialAnkiImportResult?> importOfficialOrNull({
    required String packagePath,
    required String displayName,
  }) {
    return _importer.importFile(
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
