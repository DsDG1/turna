import 'package:turna/domain/anki/card_introduction_state.dart';
import 'package:turna/domain/anki/study_models.dart';

class UnificationCensusRow {
  const UnificationCensusRow({
    required this.importId,
    required this.legacyCardCount,
    required this.legacySrsCount,
    required this.officialSourceLinked,
    required this.officialCollectionAvailable,
    required this.mappingConsistent,
    this.projectionKindsByCardId = const {},
    this.officialRepsByCardId = const {},
    this.turnaRepsByCardId = const {},
    this.lessonCompletedByCardId = const {},
  });

  final String importId;
  final int legacyCardCount;
  final int legacySrsCount;
  final bool officialSourceLinked;
  final bool officialCollectionAvailable;
  final bool mappingConsistent;
  final Map<int, List<String>> projectionKindsByCardId;
  final Map<int, int> officialRepsByCardId;
  final Map<int, int> turnaRepsByCardId;
  final Map<int, bool> lessonCompletedByCardId;
}

class UnificationMigrationReport {
  const UnificationMigrationReport({
    required this.owner,
    required this.blockedForRepair,
    required this.introducedCardIds,
    required this.activePresentationByCardId,
    required this.replayedTurnaIntoOfficial,
  });

  final StudyLedgerOwner owner;
  final bool blockedForRepair;
  final Set<int> introducedCardIds;
  final Map<int, String> activePresentationByCardId;
  final bool replayedTurnaIntoOfficial;
}

/// Additive census / owner / introduction backfill / duplicate collapse.
/// Never replays Turna history into the Official scheduler.
class AnkiUnificationMigration {
  const AnkiUnificationMigration();

  StudyLedgerOwner decideOwner(UnificationCensusRow row) {
    if (row.officialSourceLinked &&
        row.officialCollectionAvailable &&
        row.mappingConsistent) {
      return StudyLedgerOwner.officialAnki;
    }
    if (!row.officialSourceLinked || !row.officialCollectionAvailable) {
      return StudyLedgerOwner.turnaFsrs;
    }
    return StudyLedgerOwner.none;
  }

  bool isBlockedForRepair(UnificationCensusRow row) {
    return row.officialSourceLinked &&
        row.officialCollectionAvailable &&
        !row.mappingConsistent;
  }

  CardIntroductionStatus backfillIntroduction({
    required int officialReps,
    required int turnaReps,
    required bool lessonCompleted,
  }) {
    if (officialReps > 0 || turnaReps > 0 || lessonCompleted) {
      return CardIntroductionStatus.introduced;
    }
    return CardIntroductionStatus.unintroduced;
  }

  String collapseActivePresentation({
    required List<String> kinds,
    String? userConfirmed,
  }) {
    if (userConfirmed != null && kinds.contains(userConfirmed)) {
      return userConfirmed;
    }
    const priority = [
      'multipleChoice',
      'multiSelect',
      'fillBlank',
      'listenPick',
      'typeAnswer',
      'flip',
      'fidelity',
      'canonicalLink',
    ];
    for (final kind in priority) {
      if (kinds.contains(kind)) return kind;
    }
    return kinds.isEmpty ? 'flip' : kinds.first;
  }

  UnificationMigrationReport dryRun(UnificationCensusRow row) => apply(row);

  UnificationMigrationReport apply(UnificationCensusRow row) {
    final blocked = isBlockedForRepair(row);
    final owner = blocked ? StudyLedgerOwner.none : decideOwner(row);
    final introduced = <int>{};
    for (final cardId in {
      ...row.officialRepsByCardId.keys,
      ...row.turnaRepsByCardId.keys,
      ...row.lessonCompletedByCardId.keys,
      ...row.projectionKindsByCardId.keys,
    }) {
      final status = backfillIntroduction(
        officialReps: row.officialRepsByCardId[cardId] ?? 0,
        turnaReps: row.turnaRepsByCardId[cardId] ?? 0,
        lessonCompleted: row.lessonCompletedByCardId[cardId] ?? false,
      );
      if (status == CardIntroductionStatus.introduced) {
        introduced.add(cardId);
      }
    }
    final presentations = <int, String>{};
    for (final entry in row.projectionKindsByCardId.entries) {
      presentations[entry.key] = collapseActivePresentation(kinds: entry.value);
    }
    return UnificationMigrationReport(
      owner: owner,
      blockedForRepair: blocked,
      introducedCardIds: introduced,
      activePresentationByCardId: presentations,
      replayedTurnaIntoOfficial: false,
    );
  }
}
