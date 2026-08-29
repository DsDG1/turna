import 'package:flutter/foundation.dart';
import 'package:turna/domain/anki/card_introduction_state.dart';
import 'package:turna/domain/anki/objective_outcome.dart';
import 'package:turna/domain/anki/presentation_receipt.dart';
import 'package:turna/domain/anki/study_models.dart';
import 'package:turna/domain/review/recall_outcome.dart';

/// Shared card lifecycle for learn / review / practice / preview.
///
/// Renderer, navigation, and DAO access stay outside this controller.
class StudySessionController extends ChangeNotifier {
  StudySessionController({
    required this.items,
    required this.ledgerResolver,
    this.introductionRepository,
    this.onEffects,
    this.onEffectsUndone,
  });

  final List<StudyItem> items;
  final StudyLedgerResolver ledgerResolver;
  final CardIntroductionRepository? introductionRepository;
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
        if (item.capabilities.marksIntroduced &&
            introductionRepository != null) {
          try {
            await introductionRepository!.markIntroduced(
              item.courseId,
              item.cardKey,
              by: CardIntroducedBy.course,
              lessonId: item.placementId,
            );
          } catch (error) {
            pendingEffectError = error;
          }
        }
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

      if (item.capabilities.marksIntroduced &&
          introductionRepository != null) {
        try {
          await introductionRepository!.markIntroduced(
            item.courseId,
            item.cardKey,
            by: CardIntroducedBy.course,
            lessonId: item.placementId,
          );
        } catch (error) {
          pendingEffectError = error;
        }
      }

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
  /// For live-queue hosts whose items list is rebuilt in place after every
  /// commit: the next card is the scheduler's current (resolved by the host
  /// AFTER the rebuild), never index+1 over a list that just shrank or
  /// reordered.
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
        items.indexWhere((item) => item.sessionItemId == sessionItemId);
    if (target < 0) {
      // Unreachable while the scheduler's current is always inside the
      // assembled batch — fail loudly instead of silently desyncing.
      lastError = StateError('advance target missing: $sessionItemId');
      phase = StudyCardPhase.recoverableError;
      notifyListeners();
      return;
    }
    _index = target;
    _beginCurrent();
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
  /// With [onMutated], live-queue hosts rebuild the shared items list inside
  /// the lock (the scheduler's current is already refreshed by the ledger
  /// call); the controller then stays on [StudyCardPhase.readyForNext] and
  /// the host advances via [advanceTo] — index arithmetic over a rebuilt
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
