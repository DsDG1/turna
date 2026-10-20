import 'package:turna/application/anki_official/contract/official_anki_contract.dart';
import 'package:turna/application/anki_official/contract/official_anki_dto.dart';
import 'package:turna/application/anki_official/contract/official_anki_errors.dart';
import 'package:turna/application/anki_official/engine/official_anki_review_session.dart';
import 'package:turna/domain/anki/canonical_card_key.dart';
import 'package:turna/domain/review/recall_outcome.dart';
import 'package:turna/domain/review/review_item.dart';
import 'package:turna/domain/review/review_ledger.dart';
import 'package:turna/domain/review/review_source.dart';

/// Scheduling ledger backed by the official Anki Rust/C++ scheduler.
class OfficialAnkiReviewLedger implements ReviewLedger {
  final OfficialReviewSession _session;

  OfficialAnkiReviewLedger(this._session);

  bool get canUndo => _session.canUndo;
  bool get canRedo => _session.canRedo;

  /// Whether the scheduler still owes [cardId] right after the last mutation.
  ///
  /// [answer] leaves a fresh queue behind (`answerAndConfirm` refreshes it),
  /// so "absent from the queue" means this card is now scheduled beyond
  /// today. The due snapshot fold uses THIS instead of guessing from the
  /// outcome: a learning card answered `good` can still be owed in the same
  /// session, and a lapsed card answered `again` certainly is.
  ///
  /// Conservative where it cannot judge: a session that ended in an error
  /// (empty queue + not `completed`), and a queue the engine truncated at
  /// `maxReviewQueueFetchLimit`, both report "still owed" — a stale extra card
  /// in the count is preferable to hiding one the learner will be shown next.
  bool isCardStillOwed(int cardId) {
    final queue = _session.queue;
    if (queue == null) {
      // No queue: either the session just answered its last card
      // (`refreshQueue` clears it and flips to `completed`) or the engine
      // failed. Only the completed case means "nothing is owed any more".
      return _session.phase != OfficialReviewPhase.completed;
    }
    final allowed = _session.allowedCardIds;
    if (allowed != null &&
        allowed.length > OfficialAnkiOperation.maxReviewQueueFetchLimit) {
      return true;
    }
    return queue.cards.any((card) => card.cardId == cardId);
  }

  @override
  Future<ReviewDueSummary> dueSummary({String? scope}) async {
    final queue = _session.queue;
    if (queue == null) {
      final unavailable = switch (_session.phase) {
        OfficialReviewPhase.recoverableError ||
        OfficialReviewPhase.staleContext ||
        OfficialReviewPhase.fatalError ||
        OfficialReviewPhase.reconciling =>
          true,
        _ => false,
      };
      return ReviewDueSummary(dueCount: 0, isUnavailable: unavailable);
    }
    return ReviewDueSummary(
      dueCount: queue.newCount + queue.learningCount + queue.reviewCount,
      newCount: queue.newCount,
      learningCount: queue.learningCount,
      reviewCount: queue.reviewCount,
    );
  }

  @override
  Future<ReviewPreview> preview(
    ReviewSchedulingKey key,
    RecallOutcome outcome,
  ) async {
    final source = key.source;
    if (source is! OfficialAnkiSource) {
      throw StateError(
          'Official ledger received a non-official source: $source');
    }
    final card = _session.current;
    if (card == null || card.cardId != source.cardId) {
      throw OfficialAnkiException(
        code: OfficialAnkiErrorCode.schedulingContextStale,
        messageKey: 'official_anki.scheduling_context_stale',
        recoverable: true,
        debugDetails:
            'expectedCardId=${source.cardId} currentCardId=${card?.cardId}',
      );
    }
    final label = outcome == RecallOutcome.forgotten
        ? card.labels.again
        : card.labels.good;
    if (label.isEmpty) {
      throw const OfficialAnkiException(
        code: OfficialAnkiErrorCode.invalidState,
        messageKey: 'official_anki.interval_preview_unavailable',
      );
    }
    return ReviewPreview(intervalLabel: label);
  }

  @override
  Future<ReviewEventReceipt> answer(
    ReviewSchedulingKey key,
    RecallOutcome outcome, {
    int durationMs = 0,
    ReviewPreview? cachedPreview,
  }) async {
    final source = key.source;
    if (source is! OfficialAnkiSource) {
      throw StateError(
          'Official ledger received a non-official source: $source');
    }
    final now = DateTime.now();
    final prev = cachedPreview ?? await preview(key, outcome);
    final rating = outcome == RecallOutcome.forgotten ? 'again' : 'good';
    final result = await _session.answerAndConfirm(
      rating,
      expectedCardId: source.cardId,
    );
    final mutationId = result.clientMutationId ?? _session.lastClientMutationId;
    if (mutationId == null || mutationId.isEmpty) {
      throw const OfficialAnkiException(
        code: OfficialAnkiErrorCode.answerCommitUnknown,
        messageKey: 'official_anki.answer_commit_unknown',
        recoverable: true,
      );
    }

    return ReviewEventReceipt(
      eventId: mutationId,
      source: key.source,
      schedulingKey: key,
      outcome: outcome,
      reviewedAt: now,
      preview: prev,
      opaqueUndoState: null,
    );
  }

  @override
  Future<bool> undo(ReviewEventReceipt receipt) async {
    if (receipt.source is! OfficialAnkiSource ||
        receipt.eventId != _session.lastClientMutationId ||
        !_session.canUndo) {
      return false;
    }
    await _session.undo();
    return _session.lastError == null;
  }

  Future<bool> redo() async {
    if (!_session.canRedo) return false;
    await _session.redo();
    return _session.lastError == null;
  }

  Future<bool> bury(CanonicalCardKey key) async {
    if (_session.current == null || _session.current!.cardId != key.cardId) {
      return false;
    }
    await _session.buryOrSuspend(OfficialBuryOrSuspendAction.buryUser);
    return _session.lastError == null;
  }

  Future<bool> suspend(CanonicalCardKey key) async {
    if (_session.current == null || _session.current!.cardId != key.cardId) {
      return false;
    }
    await _session.buryOrSuspend(OfficialBuryOrSuspendAction.suspend);
    return _session.lastError == null;
  }
}
