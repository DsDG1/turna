import 'package:turna/application/anki_official/contract/official_anki_errors.dart';
import 'package:turna/application/anki_official/migration/official_anki_engine_kind.dart';

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
