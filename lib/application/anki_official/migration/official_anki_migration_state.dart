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

/// User-visible scheduling choice when Legacy Turna FSRS cannot be mapped
/// losslessly onto Official Anki scheduler (doc 34 §12.3).
///
/// Never silently default to [resetAsNew]. Call sites must present
/// [userVisibleLabel] / [userVisibleDescription] and persist the choice.
enum LegacyAnkiSchedulingPolicy {
  /// Keep scheduling embedded in the original .apkg; ignore later Turna-only reviews.
  preservePackageScheduling,

  /// Explicitly reset every card to New in Official (requires user confirmation).
  resetAsNew,

  /// Do not cut over; leave Legacy read-only and ask the user to re-import.
  keepLegacyReadOnly,
}

extension LegacyAnkiSchedulingPolicyUx on LegacyAnkiSchedulingPolicy {
  /// Short label for dropdowns / chooser sheets.
  String get userVisibleLabel {
    switch (this) {
      case LegacyAnkiSchedulingPolicy.preservePackageScheduling:
        return 'Keep package scheduling';
      case LegacyAnkiSchedulingPolicy.resetAsNew:
        return 'Reset cards to New';
      case LegacyAnkiSchedulingPolicy.keepLegacyReadOnly:
        return 'Keep Legacy read-only';
    }
  }

  /// Longer explanation shown before the user confirms a non-lossless cutover.
  String get userVisibleDescription {
    switch (this) {
      case LegacyAnkiSchedulingPolicy.preservePackageScheduling:
        return 'Use the review progress stored in the original Anki package. '
            'Reviews done only in Turna FSRS after import are not transferred.';
      case LegacyAnkiSchedulingPolicy.resetAsNew:
        return 'Import card text and media, but schedule every card as New in '
            'Official Anki. Turna and package review history are not applied.';
      case LegacyAnkiSchedulingPolicy.keepLegacyReadOnly:
        return 'Do not switch this source to Official. Keep Legacy data '
            'read-only/exportable and re-import a current package later.';
    }
  }

  /// True when this policy abandons cutover and leaves Legacy as the shadow.
  bool get abandonsOfficialCutover =>
      this == LegacyAnkiSchedulingPolicy.keepLegacyReadOnly;
}

/// Returns whether a lossless FSRS→Official schedule map is available.
///
/// When false, [LegacyAnkiSchedulingPolicy] must be an explicit user choice;
/// [resetAsNew] must never be applied implicitly.
bool legacyAnkiLosslessScheduleMapAvailable({
  required bool nativeMigrationApiAvailable,
  required bool turnaOnlyReviewsPresent,
}) {
  return nativeMigrationApiAvailable && !turnaOnlyReviewsPresent;
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
    LegacyAnkiMigrationState.needsUserAction,
    LegacyAnkiMigrationState.failedRecoverable,
    LegacyAnkiMigrationState.rollbackRequired,
    LegacyAnkiMigrationState.rolledBackLegacy,
  },
  LegacyAnkiMigrationState.importingOfficial: {
    LegacyAnkiMigrationState.indexingOfficial,
    LegacyAnkiMigrationState.needsUserAction,
    LegacyAnkiMigrationState.failedRecoverable,
    LegacyAnkiMigrationState.rollbackRequired,
    LegacyAnkiMigrationState.rolledBackLegacy,
  },
  LegacyAnkiMigrationState.indexingOfficial: {
    LegacyAnkiMigrationState.mappingCards,
    LegacyAnkiMigrationState.needsUserAction,
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
    LegacyAnkiMigrationState.needsUserAction,
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
    LegacyAnkiMigrationState.failedRecoverable,
    LegacyAnkiMigrationState.needsUserAction,
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
