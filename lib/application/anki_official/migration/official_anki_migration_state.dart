import 'package:turna/application/anki_official/contract/official_anki_errors.dart';

enum LegacyAnkiMigrationState {
  detected,
  awaitingPackage,
  validatingSource,
  backingUp,
  importingOfficial,
  indexingOfficial,
  mappingCards,
  projectingCourse,
  verifying,
  cutoverReady,
  cutover,
  observing,
  completed,
  failedRecoverable,
  needsUserAction,
  rollbackRequired,
  rolledBackLegacy,
  rollbackEligible,
  noLegacyScheduleRollback,
}

enum LegacyAnkiSchedulingPolicy {
  preservePackageScheduling,
  resetAsNew,
  keepLegacyReadOnly,
}

enum LegacyAnkiMatchMethod {
  noteGuidAndOrdinal,
  originalCardId,
  fieldFingerprintAndOrdinal,
}

enum LegacyAnkiMatchState {
  matched,
  unresolved,
  collision,
  needsUserAction,
  excluded,
}

LegacyAnkiMigrationState parseLegacyAnkiMigrationState(String? raw) {
  for (final state in LegacyAnkiMigrationState.values) {
    if (state.name == raw) return state;
  }
  throw OfficialAnkiException(
    code: OfficialAnkiErrorCode.invalidState,
    messageKey: 'official_anki.unknown_migration_state',
    debugDetails: raw,
  );
}

LegacyAnkiSchedulingPolicy parseLegacyAnkiSchedulingPolicy(String? raw) {
  for (final policy in LegacyAnkiSchedulingPolicy.values) {
    if (policy.name == raw) return policy;
  }
  throw OfficialAnkiException(
    code: OfficialAnkiErrorCode.invalidArgument,
    messageKey: 'official_anki.unknown_scheduling_policy',
    debugDetails: raw,
  );
}

LegacyAnkiMatchMethod parseLegacyAnkiMatchMethod(String? raw) {
  for (final method in LegacyAnkiMatchMethod.values) {
    if (method.name == raw) return method;
  }
  throw OfficialAnkiException(
    code: OfficialAnkiErrorCode.invalidArgument,
    messageKey: 'official_anki.unknown_match_method',
    debugDetails: raw,
  );
}

LegacyAnkiMatchState parseLegacyAnkiMatchState(String? raw) {
  for (final state in LegacyAnkiMatchState.values) {
    if (state.name == raw) return state;
  }
  throw OfficialAnkiException(
    code: OfficialAnkiErrorCode.invalidState,
    messageKey: 'official_anki.unknown_match_state',
    debugDetails: raw,
  );
}

const _forward = <LegacyAnkiMigrationState, Set<LegacyAnkiMigrationState>>{
  LegacyAnkiMigrationState.detected: {
    LegacyAnkiMigrationState.awaitingPackage,
    LegacyAnkiMigrationState.failedRecoverable,
    LegacyAnkiMigrationState.needsUserAction,
    LegacyAnkiMigrationState.rolledBackLegacy,
  },
  LegacyAnkiMigrationState.awaitingPackage: {
    LegacyAnkiMigrationState.validatingSource,
    LegacyAnkiMigrationState.failedRecoverable,
    LegacyAnkiMigrationState.needsUserAction,
    LegacyAnkiMigrationState.rolledBackLegacy,
  },
  LegacyAnkiMigrationState.validatingSource: {
    LegacyAnkiMigrationState.backingUp,
    LegacyAnkiMigrationState.failedRecoverable,
    LegacyAnkiMigrationState.needsUserAction,
    LegacyAnkiMigrationState.rolledBackLegacy,
  },
  LegacyAnkiMigrationState.backingUp: {
    LegacyAnkiMigrationState.importingOfficial,
    LegacyAnkiMigrationState.failedRecoverable,
    LegacyAnkiMigrationState.rollbackRequired,
    LegacyAnkiMigrationState.rolledBackLegacy,
  },
  LegacyAnkiMigrationState.importingOfficial: {
    LegacyAnkiMigrationState.indexingOfficial,
    LegacyAnkiMigrationState.failedRecoverable,
    LegacyAnkiMigrationState.rollbackRequired,
    LegacyAnkiMigrationState.rolledBackLegacy,
  },
  LegacyAnkiMigrationState.indexingOfficial: {
    LegacyAnkiMigrationState.mappingCards,
    LegacyAnkiMigrationState.failedRecoverable,
    LegacyAnkiMigrationState.rollbackRequired,
    LegacyAnkiMigrationState.rolledBackLegacy,
  },
  LegacyAnkiMigrationState.mappingCards: {
    LegacyAnkiMigrationState.projectingCourse,
    LegacyAnkiMigrationState.needsUserAction,
    LegacyAnkiMigrationState.failedRecoverable,
    LegacyAnkiMigrationState.rolledBackLegacy,
  },
  LegacyAnkiMigrationState.projectingCourse: {
    LegacyAnkiMigrationState.verifying,
    LegacyAnkiMigrationState.failedRecoverable,
    LegacyAnkiMigrationState.rollbackRequired,
    LegacyAnkiMigrationState.rolledBackLegacy,
  },
  LegacyAnkiMigrationState.verifying: {
    LegacyAnkiMigrationState.cutoverReady,
    LegacyAnkiMigrationState.failedRecoverable,
    LegacyAnkiMigrationState.needsUserAction,
    LegacyAnkiMigrationState.rolledBackLegacy,
  },
  LegacyAnkiMigrationState.cutoverReady: {
    LegacyAnkiMigrationState.cutover,
    LegacyAnkiMigrationState.rolledBackLegacy,
  },
  LegacyAnkiMigrationState.cutover: {
    LegacyAnkiMigrationState.observing,
    LegacyAnkiMigrationState.rollbackEligible,
    LegacyAnkiMigrationState.noLegacyScheduleRollback,
  },
  LegacyAnkiMigrationState.observing: {
    LegacyAnkiMigrationState.completed,
    LegacyAnkiMigrationState.rollbackEligible,
    LegacyAnkiMigrationState.noLegacyScheduleRollback,
  },
  LegacyAnkiMigrationState.failedRecoverable: {
    LegacyAnkiMigrationState.awaitingPackage,
    LegacyAnkiMigrationState.validatingSource,
    LegacyAnkiMigrationState.backingUp,
    LegacyAnkiMigrationState.rolledBackLegacy,
  },
  LegacyAnkiMigrationState.needsUserAction: {
    LegacyAnkiMigrationState.mappingCards,
    LegacyAnkiMigrationState.awaitingPackage,
    LegacyAnkiMigrationState.validatingSource,
    LegacyAnkiMigrationState.rolledBackLegacy,
  },
  LegacyAnkiMigrationState.rollbackRequired: {
    LegacyAnkiMigrationState.rolledBackLegacy,
  },
};

bool legacyAnkiMigrationAllowsTransition({
  required LegacyAnkiMigrationState from,
  required LegacyAnkiMigrationState to,
}) {
  if (from == to) return true;
  return _forward[from]?.contains(to) ?? false;
}
