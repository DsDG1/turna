import 'package:turna/domain/anki/canonical_card_key.dart';
import 'package:turna/domain/anki/card_presentation.dart';
import 'package:turna/domain/review/recall_outcome.dart';

enum StudyMode {
  learn,
  review,
  practice,
  preview,
}

enum StudyLedgerOwner {
  officialAnki,
  turnaFsrs,
  none,
}

enum StudyCardPhase {
  idle,
  loadingQuestion,
  showingQuestion,
  collectingAnswer,
  revealingAnswer,
  showingAnswer,
  showingFeedback,
  committingOutcome,
  readyForNext,
  recoverableError,
  fatalError,
  completed,
}

class StudyCapabilities {
  const StudyCapabilities({
    this.canUndo = true,
    this.canSpeak = true,
    this.writesLedger = true,
    this.marksIntroduced = false,
  });

  final bool canUndo;
  final bool canSpeak;
  final bool writesLedger;
  final bool marksIntroduced;

  factory StudyCapabilities.forMode(StudyMode mode) {
    return switch (mode) {
      StudyMode.learn => const StudyCapabilities(
          writesLedger: true,
          marksIntroduced: true,
        ),
      StudyMode.review => const StudyCapabilities(writesLedger: true),
      StudyMode.practice => const StudyCapabilities(
          writesLedger: false,
          canUndo: false,
        ),
      StudyMode.preview => const StudyCapabilities(
          writesLedger: false,
          canUndo: false,
          canSpeak: true,
        ),
    };
  }

  /// Course practice for Official cards: no scheduler write, mark introduced.
  factory StudyCapabilities.coursePractice() {
    return const StudyCapabilities(
      writesLedger: false,
      canUndo: false,
      marksIntroduced: true,
    );
  }

  StudyCapabilities copyWith({
    bool? canUndo,
    bool? canSpeak,
    bool? writesLedger,
    bool? marksIntroduced,
  }) {
    return StudyCapabilities(
      canUndo: canUndo ?? this.canUndo,
      canSpeak: canSpeak ?? this.canSpeak,
      writesLedger: writesLedger ?? this.writesLedger,
      marksIntroduced: marksIntroduced ?? this.marksIntroduced,
    );
  }
}

class StudyItem {
  const StudyItem({
    required this.sessionItemId,
    required this.courseId,
    required this.placementId,
    required this.cardKey,
    required this.presentation,
    required this.mode,
    required this.ledgerOwner,
    required this.capabilities,
  });

  final String sessionItemId;
  final String courseId;
  final String placementId;
  final CanonicalCardKey cardKey;
  final CardPresentation presentation;
  final StudyMode mode;
  final StudyLedgerOwner ledgerOwner;
  final StudyCapabilities capabilities;
}

class StudyEventReceipt {
  const StudyEventReceipt({
    required this.eventId,
    required this.idempotencyKey,
    required this.cardKey,
    required this.ledgerOwner,
    required this.outcome,
    required this.reviewedAt,
    this.nextDueAt,
    this.nativeUndoToken,
    this.previousSnapshot,
  });

  final String eventId;
  final String idempotencyKey;
  final CanonicalCardKey cardKey;
  final StudyLedgerOwner ledgerOwner;
  final RecallOutcome outcome;
  final DateTime reviewedAt;
  final DateTime? nextDueAt;
  final Object? nativeUndoToken;
  final Object? previousSnapshot;
}

class StudyScope {
  const StudyScope({
    required this.courseId,
    this.sectionId,
    this.lessonId,
    this.limit = 20,
  });

  final String courseId;
  final String? sectionId;
  final String? lessonId;
  final int limit;
}

class DueSnapshot {
  const DueSnapshot({
    required this.dueCardKeys,
    this.refreshedAt,
  });

  final Set<CanonicalCardKey> dueCardKeys;
  final DateTime? refreshedAt;
}

class SchedulePreview {
  const SchedulePreview({
    required this.intervalLabel,
    this.nextDueAt,
  });

  final String intervalLabel;
  final DateTime? nextDueAt;
}

abstract interface class StudyLedger {
  Future<DueSnapshot> dueSnapshot(StudyScope scope);

  Future<SchedulePreview> preview(
    CanonicalCardKey key,
    RecallOutcome outcome,
  );

  Future<StudyEventReceipt> commit(
    CanonicalCardKey key,
    RecallOutcome outcome, {
    required String idempotencyKey,
  });

  Future<bool> undo(StudyEventReceipt receipt);

  Future<bool> redo(StudyEventReceipt receipt);

  Future<bool> bury(CanonicalCardKey key);

  Future<bool> suspend(CanonicalCardKey key);
}

class StudyLedgerResolver {
  const StudyLedgerResolver({
    this.official,
    this.turna,
  });

  final StudyLedger? official;
  final StudyLedger? turna;

  StudyLedger resolve(StudyLedgerOwner owner) {
    switch (owner) {
      case StudyLedgerOwner.officialAnki:
        final ledger = official;
        if (ledger == null) {
          throw StateError('Official study ledger is not available');
        }
        return ledger;
      case StudyLedgerOwner.turnaFsrs:
        final ledger = turna;
        if (ledger == null) {
          throw StateError('Turna study ledger is not available');
        }
        return ledger;
      case StudyLedgerOwner.none:
        throw StateError('Study item has no ledger owner');
    }
  }
}
