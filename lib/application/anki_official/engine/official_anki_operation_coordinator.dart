import 'package:turna/application/anki_official/contract/official_anki_errors.dart';

enum OfficialAnkiOperationPhase {
  idle,
  importing,
  projecting,
  reviewing,
  backupRestore,
  maintenance,
  migrating,
}

/// Single-profile lifecycle lock. Preview is read-only and does not acquire.
class OfficialAnkiOperationCoordinator {
  OfficialAnkiOperationPhase phase = OfficialAnkiOperationPhase.idle;

  static const conflict = OfficialAnkiException(
    code: OfficialAnkiErrorCode.schedulerBusy,
    messageKey: 'official_anki.operation_conflict',
    recoverable: true,
  );

  void acquire(OfficialAnkiOperationPhase next) {
    if (next == OfficialAnkiOperationPhase.idle) {
      phase = OfficialAnkiOperationPhase.idle;
      return;
    }
    if (phase == next) return;
    if (phase != OfficialAnkiOperationPhase.idle && !_compatible(phase, next)) {
      throw conflict;
    }
    phase = next;
  }

  void release(OfficialAnkiOperationPhase expected) {
    if (phase == expected) {
      phase = OfficialAnkiOperationPhase.idle;
    }
  }

  void requireNotReviewing() {
    if (phase == OfficialAnkiOperationPhase.reviewing) {
      throw conflict;
    }
  }

  void guardCollectionMutation() => requireNotReviewing();

  void guardSchedulerWrite() {
    if (phase == OfficialAnkiOperationPhase.importing ||
        phase == OfficialAnkiOperationPhase.backupRestore ||
        phase == OfficialAnkiOperationPhase.maintenance ||
        phase == OfficialAnkiOperationPhase.migrating) {
      throw conflict;
    }
  }

  bool get isReviewing => phase == OfficialAnkiOperationPhase.reviewing;

  bool _compatible(
    OfficialAnkiOperationPhase current,
    OfficialAnkiOperationPhase next,
  ) {
    if (current == OfficialAnkiOperationPhase.reviewing &&
        next == OfficialAnkiOperationPhase.projecting) {
      return false;
    }
    return false;
  }
}
