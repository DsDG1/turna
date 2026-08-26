import 'package:turna/application/anki_official/engine/official_formal_due_repository.dart';
import 'package:turna/domain/anki/canonical_card_key.dart';
import 'package:turna/domain/anki/study_models.dart';
import 'package:turna/domain/review/official_anki_review_ledger.dart';
import 'package:turna/domain/review/recall_outcome.dart';
import 'package:turna/domain/review/review_item.dart';
import 'package:turna/domain/review/review_ledger.dart';
import 'package:turna/domain/review/review_source.dart';
import 'package:turna/domain/review/turna_review_ledger.dart';

/// Maps a canonical Anki card onto the Turna FSRS ledger.
class TurnaStudyLedger implements StudyLedger {
  TurnaStudyLedger(this._inner);

  final TurnaReviewLedger _inner;
  final Map<String, StudyEventReceipt> _byIdempotency = {};

  static String wordIdFor(CanonicalCardKey key) {
    return 'anki-${key.sourceId}-c${key.cardId}';
  }

  ReviewSchedulingKey _key(CanonicalCardKey key) {
    return ReviewSchedulingKey(
      rawId: wordIdFor(key),
      source: LegacyAnkiSource(importId: key.sourceId),
    );
  }

  @override
  Future<DueSnapshot> dueSnapshot(StudyScope scope) async {
    return const DueSnapshot(dueCardKeys: {});
  }

  @override
  Future<SchedulePreview> preview(
    CanonicalCardKey key,
    RecallOutcome outcome,
  ) async {
    final preview = await _inner.preview(_key(key), outcome);
    return SchedulePreview(
      intervalLabel: preview.intervalLabel,
      nextDueAt: preview.nextDueAt,
    );
  }

  @override
  Future<StudyEventReceipt> commit(
    CanonicalCardKey key,
    RecallOutcome outcome, {
    required String idempotencyKey,
  }) async {
    final existing = _byIdempotency[idempotencyKey];
    if (existing != null) return existing;
    _inner.ensureWord(wordIdFor(key), LegacyAnkiSource(importId: key.sourceId));
    final inner = await _inner.answer(_key(key), outcome);
    final receipt = StudyEventReceipt(
      eventId: inner.eventId,
      idempotencyKey: idempotencyKey,
      cardKey: key,
      ledgerOwner: StudyLedgerOwner.turnaFsrs,
      outcome: outcome,
      reviewedAt: inner.reviewedAt,
      nextDueAt: inner.preview.nextDueAt,
      nativeUndoToken: inner,
      previousSnapshot: inner.opaqueUndoState,
    );
    _byIdempotency[idempotencyKey] = receipt;
    return receipt;
  }

  @override
  Future<bool> undo(StudyEventReceipt receipt) async {
    final token = receipt.nativeUndoToken;
    if (token is! ReviewEventReceipt) return false;
    final ok = await _inner.undo(token);
    if (ok) _byIdempotency.remove(receipt.idempotencyKey);
    return ok;
  }

  @override
  Future<bool> redo(StudyEventReceipt receipt) async => false;

  @override
  Future<bool> bury(CanonicalCardKey key) async => false;

  @override
  Future<bool> suspend(CanonicalCardKey key) async => false;
}

/// Maps a canonical Official card onto the Official scheduler ledger.
class OfficialStudyLedger implements StudyLedger {
  OfficialStudyLedger(this._inner);

  final OfficialAnkiReviewLedger _inner;
  final Map<String, StudyEventReceipt> _byIdempotency = {};

  ReviewSchedulingKey _key(CanonicalCardKey key) {
    return ReviewSchedulingKey(
      rawId: 'official-anki-${key.sourceId}-c${key.cardId}',
      source: OfficialAnkiSource(
        sourceId: key.sourceId,
        deckId: 0,
        cardId: key.cardId,
      ),
    );
  }

  @override
  Future<DueSnapshot> dueSnapshot(StudyScope scope) async {
    return const DueSnapshot(dueCardKeys: {});
  }

  @override
  Future<SchedulePreview> preview(
    CanonicalCardKey key,
    RecallOutcome outcome,
  ) async {
    final preview = await _inner.preview(_key(key), outcome);
    return SchedulePreview(
      intervalLabel: preview.intervalLabel,
      nextDueAt: preview.nextDueAt,
    );
  }

  @override
  Future<StudyEventReceipt> commit(
    CanonicalCardKey key,
    RecallOutcome outcome, {
    required String idempotencyKey,
  }) async {
    final existing = _byIdempotency[idempotencyKey];
    if (existing != null) return existing;
    final inner = await _inner.answer(_key(key), outcome);
    final receipt = StudyEventReceipt(
      eventId: inner.eventId,
      idempotencyKey: idempotencyKey,
      cardKey: key,
      ledgerOwner: StudyLedgerOwner.officialAnki,
      outcome: outcome,
      reviewedAt: inner.reviewedAt,
      nextDueAt: inner.preview.nextDueAt,
      nativeUndoToken: inner,
    );
    _byIdempotency[idempotencyKey] = receipt;
    return receipt;
  }

  @override
  Future<bool> undo(StudyEventReceipt receipt) async {
    final token = receipt.nativeUndoToken;
    if (token is! ReviewEventReceipt) return false;
    final ok = await _inner.undo(token);
    if (ok) _byIdempotency.remove(receipt.idempotencyKey);
    return ok;
  }

  @override
  Future<bool> redo(StudyEventReceipt receipt) async {
    final ok = await _inner.redo();
    if (ok) _byIdempotency[receipt.idempotencyKey] = receipt;
    return ok;
  }

  @override
  Future<bool> bury(CanonicalCardKey key) async {
    final repo = OfficialFormalDueRepository.instance;
    final expectedGeneration = repo.generation;
    final ok = await _inner.bury(key);
    if (ok) {
      _mutateDueSnapshot(
        repo,
        expectedGeneration: expectedGeneration,
        key: key,
        addBuried: true,
      );
    }
    return ok;
  }

  @override
  Future<bool> suspend(CanonicalCardKey key) async {
    final repo = OfficialFormalDueRepository.instance;
    final expectedGeneration = repo.generation;
    final ok = await _inner.suspend(key);
    if (ok) {
      _mutateDueSnapshot(
        repo,
        expectedGeneration: expectedGeneration,
        key: key,
        addSuspended: true,
      );
    }
    return ok;
  }
}

/// Folds a successful engine bury/suspend into the due snapshot via a
/// full-snapshot CAS mutation (maintainability plan §7.4). On a generation
/// race the transform re-applies against the fresh snapshot once — the
/// union semantics cannot clobber newer refresh data, and the write is
/// never silently dropped.
void _mutateDueSnapshot(
  OfficialFormalDueRepository repo, {
  required int expectedGeneration,
  required CanonicalCardKey key,
  bool addBuried = false,
  bool addSuspended = false,
}) {
  OfficialFormalDuePerSource transform(OfficialFormalDuePerSource current) {
    return OfficialFormalDuePerSource(
      importId: current.importId,
      knowledge: current.knowledge,
      schedulerDueCardIds: current.schedulerDueCardIds,
      activePlacementCardIds: current.activePlacementCardIds,
      introducedCardIds: current.introducedCardIds,
      suspendedCardIds: addSuspended
          ? {...current.suspendedCardIds, key.cardId}
          : current.suspendedCardIds,
      buriedCardIds: addBuried
          ? {...current.buriedCardIds, key.cardId}
          : current.buriedCardIds,
      retiredCardIds: current.retiredCardIds,
    );
  }

  var result = repo.mutateSource(
    key.sourceId,
    expectedGeneration: expectedGeneration,
    transform: transform,
  );
  if (result == OfficialFormalDueCommitResult.stale) {
    result = repo.mutateSource(key.sourceId, transform: transform);
  }
  // missingSource: the sync has not registered this source yet; the next
  // full refresh collects the engine truth, so the write is not lost.
}
