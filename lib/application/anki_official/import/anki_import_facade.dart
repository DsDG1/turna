import 'package:turna/application/anki_official/contract/official_anki_errors.dart';
import 'package:turna/application/anki_official/import/anki_import_execution_plan.dart';
import 'package:turna/application/anki_official/import/official_anki_import_state.dart';
import 'package:turna/application/anki_official/official_anki_feature_flags.dart';

/// Doc 35 L1: the `legacy` decision died with the Dart `.apkg` parser — a
/// resolved facade is either the Official importer or throws fail-closed.
enum AnkiImportDecision { official, failClosed }

abstract class AnkiImportFacade {
  bool get isOfficial;

  Future<OfficialAnkiImportResult?> importOfficialOrNull({
    required String packagePath,
    required String displayName,
  });

  /// Compatibility wrapper over [AnkiImportExecutionPlanner]. Prefer
  /// [planFor] for new call sites so writer/owner stay atomic.
  static AnkiImportDecision decisionFor(
    OfficialAnkiFeatureFlags flags, {
    bool? cutoverEnabled,
    String? platform,
    bool? libraryAvailable,
    String filePath = '',
  }) {
    return planFor(
      flags,
      cutoverEnabled: cutoverEnabled,
      platform: platform,
      libraryAvailable: libraryAvailable,
      filePath: filePath,
    ).facadeDecision;
  }

  /// Atomic import plan (doc 34 W0). Call once per pick/commit.
  static AnkiImportExecutionPlan planFor(
    OfficialAnkiFeatureFlags flags, {
    bool? cutoverEnabled,
    String? platform,
    bool? libraryAvailable,
    String filePath = '',
    String? extensionOverride,
  }) {
    return const AnkiImportExecutionPlanner().resolve(
      flags: flags,
      cutoverEnabled: cutoverEnabled,
      platform: platform,
      libraryAvailable: libraryAvailable,
      filePath: filePath,
      extensionOverride: extensionOverride,
    );
  }

  static AnkiImportFacade resolve({
    OfficialAnkiFeatureFlags? flags,
    OfficialAnkiImporter? official,
    OfficialAnkiImporter? officialImporter,
    bool? cutoverEnabled,
    String? platform,
    bool? libraryAvailable,
    AnkiImportExecutionPlan? plan,
  }) {
    final resolved = flags ?? OfficialAnkiFeatureFlags.current;
    final resolvedPlan = plan ??
        planFor(
          resolved,
          cutoverEnabled: cutoverEnabled,
          platform: platform,
          libraryAvailable: libraryAvailable,
        );
    final decision = resolvedPlan.facadeDecision;
    if (decision == AnkiImportDecision.failClosed) {
      throw OfficialAnkiException(
        code: OfficialAnkiErrorCode.capabilityMissing,
        messageKey: 'official_anki.flag_fail_closed',
        debugDetails: resolvedPlan.reason,
      );
    }
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
