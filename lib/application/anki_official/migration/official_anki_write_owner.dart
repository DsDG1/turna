import 'package:turna/application/anki_official/contract/official_anki_errors.dart';
import 'package:turna/application/anki_official/migration/official_anki_engine_kind.dart';
import 'package:turna/application/anki_official/migration/official_anki_migration_dao.dart';
import 'package:turna/application/anki_official/migration/official_anki_migration_state.dart';
import 'package:turna/application/anki_official/official_anki_composition.dart';
import 'package:turna/application/anki_official/storage/official_anki_database.dart';

enum AnkiWriteOwner {
  officialScheduler,
  turnaSrs,
  legacyAnkiDao,
  projection,
}

class AnkiWriteDenied implements Exception {
  const AnkiWriteDenied({
    required this.sourceEngine,
    required this.owner,
    required this.operation,
  });

  final AnkiEngineKind sourceEngine;
  final AnkiWriteOwner owner;
  final String operation;

  @override
  String toString() =>
      'AnkiWriteDenied(engine=${sourceEngine.name}, owner=${owner.name}, op=$operation)';
}

/// Boundary tag for scheduler/SRS/DAO/projection writers.
class AnkiWriteGuard {
  const AnkiWriteGuard();

  void assertAllowed({
    required AnkiEngineKind sourceEngine,
    required AnkiWriteOwner owner,
    required String operation,
  }) {
    final forbidden = switch (sourceEngine) {
      AnkiEngineKind.official =>
        owner == AnkiWriteOwner.turnaSrs || owner == AnkiWriteOwner.legacyAnkiDao,
      AnkiEngineKind.legacy => owner == AnkiWriteOwner.officialScheduler,
    };
    final projectionScoring = owner == AnkiWriteOwner.projection &&
        (operation == 'answer' ||
            operation == 'undo' ||
            operation == 'redo' ||
            operation == 'bury' ||
            operation == 'suspend');
    if (forbidden || projectionScoring) {
      throw AnkiWriteDenied(
        sourceEngine: sourceEngine,
        owner: owner,
        operation: operation,
      );
    }
  }

  OfficialAnkiException asOfficialException(AnkiWriteDenied denied) {
    return OfficialAnkiException(
      code: OfficialAnkiErrorCode.invalidState,
      messageKey: 'official_anki.write_owner_denied',
      debugDetails: denied.toString(),
    );
  }
}

const _legacySrsLockedStates = <LegacyAnkiMigrationState>{
  LegacyAnkiMigrationState.cutoverReady,
  LegacyAnkiMigrationState.cutover,
  LegacyAnkiMigrationState.observing,
  LegacyAnkiMigrationState.completed,
  LegacyAnkiMigrationState.noLegacyScheduleRollback,
};

/// Denies Turna SRS writes for a Legacy import that P5-C has already cut over.
void assertLegacySrsAnswerAllowed({
  required String? importId,
  OfficialAnkiMigrationDao? dao,
  String profileId = 'profile-default-01',
}) {
  if (importId == null || importId.isEmpty) return;
  if (dao != null) {
    _denyIfOfficialOwned(dao, importId, profileId);
    return;
  }
  final paths = OfficialAnkiCompositionRoot.locatorPaths;
  final catalog = paths?.catalogFile;
  if (catalog == null || !catalog.existsSync()) return;
  final db = OfficialAnkiDatabase.file(catalog.path);
  try {
    _denyIfOfficialOwned(OfficialAnkiMigrationDao(db), importId, profileId);
  } finally {
    db.close();
  }
}

void _denyIfOfficialOwned(
  OfficialAnkiMigrationDao dao,
  String importId,
  String profileId,
) {
  final row = dao.findByLegacyImport(
    profileId: profileId,
    legacyImportId: importId,
  );
  if (row == null || !_legacySrsLockedStates.contains(row.state)) return;
  const AnkiWriteGuard().assertAllowed(
    sourceEngine: AnkiEngineKind.official,
    owner: AnkiWriteOwner.turnaSrs,
    operation: 'answer',
  );
}
