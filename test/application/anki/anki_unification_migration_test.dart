import 'package:flutter_test/flutter_test.dart';
import 'package:turna/application/anki/anki_unification_migration.dart';
import 'package:turna/domain/anki/card_introduction_state.dart';
import 'package:turna/domain/anki/study_models.dart';

void main() {
  const migration = AnkiUnificationMigration();

  group('AnkiUnificationMigration', () {
    test('Official link present, available, consistent → official owner', () {
      const row = UnificationCensusRow(
        importId: 'imp-ok',
        legacyCardCount: 3,
        legacySrsCount: 3,
        officialSourceLinked: true,
        officialCollectionAvailable: true,
        mappingConsistent: true,
        projectionKindsByCardId: {
          1: ['flip', 'multipleChoice'],
          2: ['fidelity', 'flip'],
        },
        officialRepsByCardId: {1: 4},
        turnaRepsByCardId: {2: 2},
        lessonCompletedByCardId: {3: true},
      );
      final dry = migration.dryRun(row);
      final applied = migration.apply(row);
      expect(applied.owner, StudyLedgerOwner.officialAnki);
      expect(applied.blockedForRepair, isFalse);
      expect(applied.replayedTurnaIntoOfficial, isFalse);
      expect(applied.introducedCardIds, {1, 2, 3});
      expect(applied.activePresentationByCardId[1], 'multipleChoice');
      expect(applied.activePresentationByCardId[2], 'flip');
      expect(dry.replayedTurnaIntoOfficial, isFalse);
    });

    test('Official collection missing → Turna owner, no replay', () {
      const row = UnificationCensusRow(
        importId: 'imp-missing',
        legacyCardCount: 1,
        legacySrsCount: 1,
        officialSourceLinked: false,
        officialCollectionAvailable: false,
        mappingConsistent: true,
        turnaRepsByCardId: {9: 1},
      );
      final report = migration.apply(row);
      expect(report.owner, StudyLedgerOwner.turnaFsrs);
      expect(report.blockedForRepair, isFalse);
      expect(report.replayedTurnaIntoOfficial, isFalse);
      expect(report.introducedCardIds, {9});
    });

    test('conflicting mapping is blocked for repair', () {
      const row = UnificationCensusRow(
        importId: 'imp-conflict',
        legacyCardCount: 2,
        legacySrsCount: 2,
        officialSourceLinked: true,
        officialCollectionAvailable: true,
        mappingConsistent: false,
        projectionKindsByCardId: {
          5: ['canonicalLink', 'flip'],
        },
      );
      final report = migration.apply(row);
      expect(report.blockedForRepair, isTrue);
      expect(report.owner, StudyLedgerOwner.none);
      expect(report.replayedTurnaIntoOfficial, isFalse);
      expect(report.activePresentationByCardId[5], 'flip');
    });

    test('history with reps backfills introduced; zero reps stay unintroduced',
        () {
      expect(
        migration.backfillIntroduction(
          officialReps: 0,
          turnaReps: 0,
          lessonCompleted: false,
        ),
        CardIntroductionStatus.unintroduced,
      );
      expect(
        migration.backfillIntroduction(
          officialReps: 1,
          turnaReps: 0,
          lessonCompleted: false,
        ),
        CardIntroductionStatus.introduced,
      );
      expect(
        migration.backfillIntroduction(
          officialReps: 0,
          turnaReps: 3,
          lessonCompleted: false,
        ),
        CardIntroductionStatus.introduced,
      );
    });

    test('duplicate projections collapse to one active presentation', () {
      expect(
        migration.collapseActivePresentation(
          kinds: ['canonicalLink', 'fidelity', 'flip', 'multipleChoice'],
        ),
        'multipleChoice',
      );
      expect(
        migration.collapseActivePresentation(
          kinds: ['flip', 'fidelity'],
          userConfirmed: 'fidelity',
        ),
        'fidelity',
      );
    });
  });
}
