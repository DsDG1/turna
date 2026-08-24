import 'package:flutter/foundation.dart';
import 'package:turna/domain/anki/card_introduction_state.dart';
import 'package:turna/domain/anki/objective_outcome.dart';
import 'package:turna/domain/anki/presentation_receipt.dart';
import 'package:turna/domain/anki/repositories.dart';
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
      lastReceipt = null;
      // Re-show the card whose answer was rolled back. The old index math
      // only handled the `completed` phase; after the production auto-
      // `continueNext` (phase showingQuestion of the NEXT card) the undone
      // card was silently skipped, and in `readyForNext` the decrement
      // landed on the card BEFORE the undone one. Locate the item by the
      // receipt's idempotency-key prefix (its sessionItemId) instead.
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
