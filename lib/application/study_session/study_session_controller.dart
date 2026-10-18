import 'package:flutter/foundation.dart';
import 'package:turna/domain/anki/card_presentation.dart';
import 'package:turna/domain/anki/objective_outcome.dart';
import 'package:turna/domain/anki/presentation_receipt.dart';
import 'package:turna/domain/anki/study_models.dart';
import 'package:turna/domain/review/recall_outcome.dart';
import 'package:turna/domain/review/review_item.dart';
import 'package:turna/domain/review/review_ledger.dart';
import 'package:turna/domain/review/review_source.dart';

/// Shared card lifecycle for learn / review / practice / preview.
///
/// Renderer, navigation, and DAO access stay outside this controller.
class StudySessionController extends ChangeNotifier {
  StudySessionController({
    required List<StudyItem> items,
    required this.ledgerResolver,
    this.onEffects,
    this.onEffectsUndone,
  }) : _items = List.unmodifiable(items);

  /// The session's items. P3: replaced wholesale by live-queue hosts via
  /// [replaceItems] — never mutated in place by anyone else, and the list
  /// handed to the constructor is copied so callers cannot mutate the
  /// session behind it.
  List<StudyItem> get items => _items;
  List<StudyItem> _items;
  final StudyLedgerResolver ledgerResolver;
  final Future<void> Function(StudyItem item, StudyEventReceipt receipt)?
      onEffects;
  final Future<void> Function(StudyEventReceipt receipt)? onEffectsUndone;

  int _index = 0;
  int _generation = 0;
  StudyCardPhase phase = StudyCardPhase.idle;
  PresentationReceipt? questionReceipt;
  PresentationReceipt? answerReceipt;
  StudyEventReceipt? lastReceipt;
  StudyEventReceipt? _undoneReceipt;
  Object? lastError;
  Object? pendingEffectError;
  bool _locked = false;
  String? _currentIdempotencyKey;
  final Map<String, StudyEventReceipt> _commitsByIdempotency = {};
  int rememberedCount = 0;
  int forgottenCount = 0;
  final DateTime startedAt = DateTime.now();

  StudyItem? get currentItem =>
      _index >= 0 && _index < items.length ? items[_index] : null;

  int get currentIndex => _index;
  int get totalCount => items.length;

  /// Cards with a committed recall outcome this session (undo/redo aware).
  ///
  /// Live-queue hosts replace [items] after every answer (plan 34 D4), so at
  /// completion [totalCount] is the residual scheduler queue — never the
  /// session size. Completion summaries must count with this instead.
  int get answeredCount => rememberedCount + forgottenCount;

  int get generation => _generation;
  bool get isComplete => phase == StudyCardPhase.completed;
  bool get isLocked => _locked;
  bool get canRedo => _undoneReceipt != null && !_locked;

  bool get canReveal {
    final item = currentItem;
    return item != null &&
        !_locked &&
        phase == StudyCardPhase.showingQuestion &&
        questionReceipt != null &&
        questionReceipt!.matches(
          cardKey: item.cardKey,
          generation: _generation,
          side: PresentationSide.question,
        );
  }

  bool get canSubmitRecall {
    final item = currentItem;
    return item != null &&
        !_locked &&
        (phase == StudyCardPhase.showingAnswer ||
            phase == StudyCardPhase.showingFeedback) &&
        answerReceipt != null &&
        answerReceipt!.matches(
          cardKey: item.cardKey,
          generation: _generation,
          side: PresentationSide.answer,
        );
  }

  Future<void> start() async {
    if (items.isEmpty) {
      phase = StudyCardPhase.completed;
      notifyListeners();
      return;
    }
    _index = 0;
    _beginCurrent();
  }

  void acceptPresentation(PresentationReceipt receipt) {
    final item = currentItem;
    if (item == null) return;
    if (receipt.cardKey != item.cardKey) return;
    if (receipt.generation != _generation) return;
    if (receipt.ok &&
        item.presentation is FidelityCardPresentation &&
        receipt.renderer != PresentationRendererKind.officialTemplate) {
      phase = StudyCardPhase.recoverableError;
      lastError = 'UNRENDERABLE_TEMPLATE';
      notifyListeners();
      return;
    }
    if (!receipt.ok) {
      phase = StudyCardPhase.recoverableError;
      lastError = receipt.code ?? 'RENDER_ERROR';
      notifyListeners();
      return;
    }
    if (receipt.side == PresentationSide.question) {
      if (phase == StudyCardPhase.loadingQuestion ||
          phase == StudyCardPhase.showingQuestion) {
        questionReceipt = receipt;
        phase = StudyCardPhase.showingQuestion;
        notifyListeners();
      }
      return;
    }
    if (receipt.side == PresentationSide.answer) {
      if (phase == StudyCardPhase.revealingAnswer ||
          phase == StudyCardPhase.showingAnswer ||
          phase == StudyCardPhase.showingFeedback ||
          phase == StudyCardPhase.collectingAnswer) {
        answerReceipt = receipt;
        if (phase == StudyCardPhase.revealingAnswer) {
          phase = StudyCardPhase.showingAnswer;
        }
        final pending = _pendingObjective;
        notifyListeners();
        if (pending != null) {
          submitRecall(objectiveRecallOutcome(correct: pending));
        }
      }
    }
  }

  Future<void> revealAnswer() async {
    if (!canReveal) return;
    _locked = true;
    phase = StudyCardPhase.revealingAnswer;
    notifyListeners();
    _locked = false;
    notifyListeners();
  }

  Future<void> submitObjectiveAnswer({
    required bool correct,
    Object? answer,
  }) async {
    final item = currentItem;
    if (item == null || _locked) return;
    if (phase != StudyCardPhase.showingQuestion &&
        phase != StudyCardPhase.collectingAnswer) {
      return;
    }
    _locked = true;
    phase = StudyCardPhase.showingFeedback;
    notifyListeners();
    _locked = false;
    notifyListeners();
    if (answerReceipt != null &&
        answerReceipt!.matches(
          cardKey: item.cardKey,
          generation: _generation,
          side: PresentationSide.answer,
        )) {
      await submitRecall(objectiveRecallOutcome(correct: correct));
    } else {
      _pendingObjective = correct;
    }
  }

  bool? _pendingObjective;

  Future<void> submitRecall(RecallOutcome outcome) async {
    final item = currentItem;
    if (item == null || _locked || isComplete) return;
    if (!canSubmitRecall && _pendingObjective == null) return;
    if (answerReceipt == null ||
        !answerReceipt!.matches(
          cardKey: item.cardKey,
          generation: _generation,
          side: PresentationSide.answer,
        )) {
      return;
    }

    _locked = true;
    phase = StudyCardPhase.committingOutcome;
    lastError = null;
    notifyListeners();

    try {
      if (!item.capabilities.writesLedger ||
          item.ledgerOwner == StudyLedgerOwner.none ||
          item.mode == StudyMode.practice ||
          item.mode == StudyMode.preview) {
        lastReceipt = StudyEventReceipt(
          eventId: 'practice-${item.sessionItemId}-$_generation',
          idempotencyKey: _idempotencyKeyFor(item),
          cardKey: item.cardKey,
          ledgerOwner: StudyLedgerOwner.none,
          outcome: outcome,
          reviewedAt: DateTime.now(),
        );
        _recordCounts(outcome);
        if (onEffects != null) {
          try {
            await onEffects!(item, lastReceipt!);
          } catch (error) {
            pendingEffectError = error;
          }
        }
        phase = StudyCardPhase.readyForNext;
        return;
      }

      final key = _idempotencyKeyFor(item);
      _currentIdempotencyKey = key;
      final existing = _commitsByIdempotency[key];
      final StudyEventReceipt receipt;
      if (existing != null) {
        receipt = existing;
      } else {
        final ledger = ledgerResolver.resolve(item.ledgerOwner);
        receipt = await ledger.commit(
          item.cardKey,
          outcome,
          idempotencyKey: key,
        );
        _commitsByIdempotency[key] = receipt;
      }
      lastReceipt = receipt;
      _undoneReceipt = null;
      _recordCounts(outcome);

      if (onEffects != null) {
        try {
          await onEffects!(item, receipt);
        } catch (error) {
          pendingEffectError = error;
        }
      }
      phase = StudyCardPhase.readyForNext;
    } catch (error) {
      lastError = error;
      phase = StudyCardPhase.recoverableError;
    } finally {
      _pendingObjective = null;
      _locked = false;
      notifyListeners();
    }
  }

  /// Records a grade the official scheduler already committed.
  ///
  /// The HarmonyOS reviewer writes through the grades bridge, which sits
  /// outside [submitRecall]. A second [submitRecall] would answer the same
  /// card again. This only stores the mutation the scheduler just produced,
  /// so undo still addresses it and the session may advance.
  void acceptExternalOfficialCommit({
    required RecallOutcome outcome,
    required String eventId,
  }) {
    final item = currentItem;
    if (item == null || _locked || isComplete || eventId.isEmpty) return;
    if (lastReceipt != null && lastReceipt!.eventId == eventId) {
      // The native page retries the advance when the first attempt failed
      // after the commit (B1): re-recording the same mutation would
      // double-count the answer, so the replay only re-advances.
      //
      // That advance needs `readyForNext`, and a failed one — scheduler
      // desync, locked session — leaves the phase in `recoverableError`.
      // Without this reset the retry is a permanent no-op: `advanceTo`
      // returns silently at its guard, the card stays on screen, and even a
      // reconciled batch cannot move the session.
      //
      // Resetting **only** `recoverableError` was too narrow. An advance that
      // resolved to the card already on screen — which is what a learning card
      // re-queued by the scheduler looks like — leaves `loadingQuestion`
      // (`_beginCurrent`), not `recoverableError`. On device (2026-10-18) that
      // made every retry answer `advance_failed` for a rating that had in fact
      // committed. Any phase that is not already `readyForNext` must re-arm;
      // the receipt is recorded, so this only re-opens the move.
      if (phase != StudyCardPhase.readyForNext && !_locked && !isComplete) {
        lastError = null;
        phase = StudyCardPhase.readyForNext;
        notifyListeners();
      }
      return;
    }
    final source = OfficialAnkiSource(
      sourceId: item.cardKey.sourceId,
      deckId: 0,
      cardId: item.cardKey.cardId,
    );
    final schedulingKey = ReviewSchedulingKey(
      rawId: 'official-anki-${item.cardKey.sourceId}-c${item.cardKey.cardId}',
      source: source,
    );
    final reviewedAt = DateTime.now();
    lastReceipt = StudyEventReceipt(
      eventId: eventId,
      idempotencyKey: _idempotencyKeyFor(item),
      cardKey: item.cardKey,
      ledgerOwner: item.ledgerOwner,
      outcome: outcome,
      reviewedAt: reviewedAt,
      nativeUndoToken: ReviewEventReceipt(
        eventId: eventId,
        source: source,
        schedulingKey: schedulingKey,
        outcome: outcome,
        reviewedAt: reviewedAt,
        preview: const ReviewPreview(intervalLabel: ''),
      ),
    );
    _undoneReceipt = null;
    _recordCounts(outcome);
    phase = StudyCardPhase.readyForNext;
    notifyListeners();
  }

  Future<void> continueNext() async {
    if (phase != StudyCardPhase.readyForNext || _locked) return;
    _index += 1;
    if (_index >= items.length) {
      phase = StudyCardPhase.completed;
      questionReceipt = null;
      answerReceipt = null;
      notifyListeners();
      return;
    }
    _beginCurrent();
  }

  /// Advance to the item identified by [sessionItemId], completing the
  /// session when null.
  ///
  /// For live-queue hosts whose items list is REPLACED after every commit:
  /// the next card is the scheduler's current (resolved by the host AFTER
  /// the rebuild), never index+1 over a list that just shrank or reordered.
  Future<void> advanceTo(String? sessionItemId) async {
    if (phase != StudyCardPhase.readyForNext || _locked) return;
    if (sessionItemId == null) {
      phase = StudyCardPhase.completed;
      questionReceipt = null;
      answerReceipt = null;
      notifyListeners();
      return;
    }
    final target =
        _items.indexWhere((item) => item.sessionItemId == sessionItemId);
    if (target < 0) {
      // Unreachable while the host resolves the id from [items]; a miss is
      // a precondition violation, so fail loudly instead of silently
      // desyncing.
      lastError = StateError('advance target missing: $sessionItemId');
      phase = StudyCardPhase.recoverableError;
      notifyListeners();
      return;
    }
    _index = target;
    _beginCurrent();
  }

  /// Reports a scheduler/controller desync: the scheduler owes a current
  /// card that is NOT among the assembled items. P3 replacement for the
  /// fake `missing-c$id` sessionItemId the host used to mint to force
  /// [advanceTo] to fail loudly. Recoverable — the surface shows
  /// [lastError] and offers retry; the session is never silently completed
  /// while the scheduler still owes cards.
  void reportSchedulerDesync(int schedulerCardId) {
    lastError = StateError(
      'scheduler current card $schedulerCardId is not in the assembled batch',
    );
    phase = StudyCardPhase.recoverableError;
    notifyListeners();
  }

  /// P3: swaps the session's items for a freshly rebuilt batch. Live-queue
  /// hosts call this after every scheduler refresh (through the live
  /// queue's [OfficialFormalReviewLiveQueue.itemsSink]); the visible
  /// position is deliberately NOT rescheduled here — the host advances by
  /// the scheduler's current through [advanceTo] or completes via
  /// `advanceTo(null)`.
  void replaceItems(List<StudyItem> next) {
    _items = List.unmodifiable(next);
    notifyListeners();
  }

  Future<bool> undoLast() async {
    final receipt = lastReceipt;
    if (receipt == null || _locked) return false;
    if (receipt.ledgerOwner == StudyLedgerOwner.none) return false;
    _locked = true;
    notifyListeners();
    try {
      final ledger = ledgerResolver.resolve(receipt.ledgerOwner);
      final ok = await ledger.undo(receipt);
      if (!ok) return false;
      if (onEffectsUndone != null) {
        try {
          await onEffectsUndone!(receipt);
        } catch (error) {
          pendingEffectError = error;
        }
      }
      _commitsByIdempotency.remove(receipt.idempotencyKey);
      if (receipt.outcome == RecallOutcome.remembered) {
        if (rememberedCount > 0) rememberedCount--;
      } else if (forgottenCount > 0) {
        forgottenCount--;
      }
      _undoneReceipt = receipt;
      lastReceipt = null;
      // Re-show the card whose answer was rolled back.
      final itemId = _sessionItemIdOf(receipt);
      final target = itemId == null
          ? -1
          : items.lastIndexWhere((item) => item.sessionItemId == itemId);
      if (target >= 0) {
        _index = target;
      } else if (_index > 0) {
        _index -= 1;
      }
      _beginCurrent();
      return true;
    } catch (error) {
      lastError = error;
      phase = StudyCardPhase.recoverableError;
      return false;
    } finally {
      _locked = false;
      notifyListeners();
    }
  }

  Future<bool> redoLast() async {
    final receipt = _undoneReceipt;
    if (receipt == null || _locked) return false;
    if (receipt.ledgerOwner == StudyLedgerOwner.none) return false;
    _locked = true;
    notifyListeners();
    try {
      final ledger = ledgerResolver.resolve(receipt.ledgerOwner);
      final ok = await ledger.redo(receipt);
      if (!ok) return false;
      _commitsByIdempotency[receipt.idempotencyKey] = receipt;
      _recordCounts(receipt.outcome);
      lastReceipt = receipt;
      _undoneReceipt = null;
      phase = StudyCardPhase.readyForNext;
      return true;
    } catch (error) {
      lastError = error;
      phase = StudyCardPhase.recoverableError;
      return false;
    } finally {
      _locked = false;
      notifyListeners();
    }
  }

  /// Buries the current card.
  ///
  /// With [onMutated], live-queue hosts REPLACE the items list inside the
  /// lock (the scheduler's current is already refreshed by the ledger
  /// call); the controller then stays on [StudyCardPhase.readyForNext] and
  /// the host advances via [advanceTo] — index arithmetic over a replaced
  /// list would skip the queue head. Without it, static-list callers keep
  /// the index+1 skip.
  Future<bool> buryCurrent({Future<void> Function()? onMutated}) async {
    final item = currentItem;
    if (item == null || _locked) return false;
    _locked = true;
    notifyListeners();
    try {
      if (item.ledgerOwner != StudyLedgerOwner.none) {
        final ledger = ledgerResolver.resolve(item.ledgerOwner);
        final ok = await ledger.bury(item.cardKey);
        if (!ok) return false;
      }
      if (onMutated != null) {
        await onMutated();
        phase = StudyCardPhase.readyForNext;
        return true;
      }
      _index += 1;
      if (_index >= items.length) {
        phase = StudyCardPhase.completed;
        questionReceipt = null;
        answerReceipt = null;
      } else {
        _beginCurrent();
      }
      return true;
    } catch (error) {
      lastError = error;
      phase = StudyCardPhase.recoverableError;
      return false;
    } finally {
      _locked = false;
      notifyListeners();
    }
  }

  /// Suspends the current card. See [buryCurrent] for the [onMutated]
  /// live-queue contract.
  Future<bool> suspendCurrent({Future<void> Function()? onMutated}) async {
    final item = currentItem;
    if (item == null || _locked) return false;
    _locked = true;
    notifyListeners();
    try {
      if (item.ledgerOwner != StudyLedgerOwner.none) {
        final ledger = ledgerResolver.resolve(item.ledgerOwner);
        final ok = await ledger.suspend(item.cardKey);
        if (!ok) return false;
      }
      if (onMutated != null) {
        await onMutated();
        phase = StudyCardPhase.readyForNext;
        return true;
      }
      _index += 1;
      if (_index >= items.length) {
        phase = StudyCardPhase.completed;
        questionReceipt = null;
        answerReceipt = null;
      } else {
        _beginCurrent();
      }
      return true;
    } catch (error) {
      lastError = error;
      phase = StudyCardPhase.recoverableError;
      return false;
    } finally {
      _locked = false;
      notifyListeners();
    }
  }

  Future<void> retryCurrent() async {
    if (phase != StudyCardPhase.recoverableError) return;
    lastError = null;
    _beginCurrent(reuseGeneration: true);
  }

  void _beginCurrent({bool reuseGeneration = false}) {
    questionReceipt = null;
    answerReceipt = null;
    _pendingObjective = null;
    if (!reuseGeneration) {
      _generation += 1;
    }
    _currentIdempotencyKey = null;
    phase = StudyCardPhase.loadingQuestion;
    notifyListeners();
  }

  String _idempotencyKeyFor(StudyItem item) {
    return _currentIdempotencyKey ??
        '${item.sessionItemId}:${item.cardKey.cardId}:$_generation';
  }

  /// `[sessionItemId]:[cardId]:[generation]` → the sessionItemId part.
  String? _sessionItemIdOf(StudyEventReceipt receipt) {
    final key = receipt.idempotencyKey;
    final colon = key.indexOf(':');
    return colon > 0 ? key.substring(0, colon) : null;
  }

  void _recordCounts(RecallOutcome outcome) {
    if (outcome == RecallOutcome.remembered) {
      rememberedCount++;
    } else {
      forgottenCount++;
    }
  }
}
