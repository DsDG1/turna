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
}
