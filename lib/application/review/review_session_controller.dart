import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:turna/domain/review/recall_outcome.dart';
import 'package:turna/domain/review/review_item.dart';
import 'package:turna/domain/review/review_ledger.dart';
import 'package:turna/domain/review/review_ledger_resolver.dart';

/// State and business logic controller for a unified review session.
///
/// Ensures:
/// - One card, one answer, one unique ledger write.
/// - Item is locked during submission to prevent double taps.
/// - Authoritative interval previews fetched from the active ledger.
/// - Idempotent, receipt-based single undo.
class ReviewSessionController extends ChangeNotifier {
  final List<ReviewItem> items;
  final ReviewLedgerResolver ledgerResolver;
  final Future<void> Function(ReviewItem item, RecallOutcome outcome)? onOutcomeRecorded;
  final Future<void> Function(ReviewEventReceipt receipt)? onOutcomeUndone;
  final Future<void> Function(int remembered, int forgotten)? onSessionCompleted;

  ReviewSessionController({
    required this.items,
    required this.ledgerResolver,
    this.onOutcomeRecorded,
    this.onOutcomeUndone,
    this.onSessionCompleted,
  }) {
    if (items.isNotEmpty) {
      _loadPreviews();
    }
  }

  int _currentIndex = 0;
  bool _isRevealed = false;
  bool _isSubmitting = false;
  bool _isComplete = false;
  ReviewEventReceipt? _lastReceipt;
  Object? _lastError;
  Object? _sideEffectWarning;
  int _previewGeneration = 0;

  ReviewPreview? _forgottenPreview;
  ReviewPreview? _rememberedPreview;

  int _rememberedCount = 0;
  int _forgottenCount = 0;
  final DateTime _startedAt = DateTime.now();

  int get currentIndex => _currentIndex;
  bool get isRevealed => _isRevealed;
  bool get isSubmitting => _isSubmitting;
  bool get isComplete => _isComplete;
  ReviewEventReceipt? get lastReceipt => _lastReceipt;
  Object? get lastError => _lastError;
  Object? get sideEffectWarning => _sideEffectWarning;

  ReviewPreview? get forgottenPreview => _forgottenPreview;
  ReviewPreview? get rememberedPreview => _rememberedPreview;

  int get rememberedCount => _rememberedCount;
  int get forgottenCount => _forgottenCount;
  int get totalCount => items.length;
  Duration get elapsed => DateTime.now().difference(_startedAt);

  double get progress {
    if (items.isEmpty) return 1.0;
    return (_currentIndex / items.length).clamp(0.0, 1.0);
  }

  ReviewItem? get currentItem {
    if (_currentIndex < items.length) {
      return items[_currentIndex];
    }
    return null;
  }

  void reveal() {
    if (_isRevealed || _isSubmitting || _isComplete) return;
    _isRevealed = true;
    notifyListeners();
  }

  Future<void> _loadPreviews() async {
    final item = currentItem;
    if (item == null) return;
    final generation = ++_previewGeneration;
    try {
      final ledger = ledgerResolver.resolve(item.source);
      final forgotten = await ledger.preview(
        item.schedulingKey,
        RecallOutcome.forgotten,
      );
      final remembered = await ledger.preview(
        item.schedulingKey,
        RecallOutcome.remembered,
      );
      if (generation != _previewGeneration ||
          currentItem?.sessionItemId != item.sessionItemId) {
        return;
      }
      _forgottenPreview = forgotten;
      _rememberedPreview = remembered;
      _lastError = null;
      notifyListeners();
    } catch (error) {
      if (generation != _previewGeneration) return;
      _lastError = error;
      notifyListeners();
    }
  }

  Future<bool> answer(RecallOutcome outcome) async {
    final item = currentItem;
    if (item == null || _isSubmitting || _isComplete) return false;
    _isSubmitting = true;
    _lastError = null;
    notifyListeners();

    try {
      final ledger = ledgerResolver.resolve(item.source);
      final receipt = await ledger.answer(
        item.schedulingKey,
        outcome,
      );

      _lastReceipt = receipt;
      if (outcome == RecallOutcome.remembered) {
        _rememberedCount++;
      } else {
        _forgottenCount++;
      }

      if (onOutcomeRecorded != null) {
        try {
          await onOutcomeRecorded!(item, outcome);
        } catch (error) {
          _sideEffectWarning = error;
        }
      }

      _previewGeneration++;
      _currentIndex++;
      _isRevealed = false;
      _forgottenPreview = null;
      _rememberedPreview = null;

      if (_currentIndex >= items.length) {
        _isComplete = true;
        if (onSessionCompleted != null) {
          try {
            await onSessionCompleted!(_rememberedCount, _forgottenCount);
          } catch (error) {
            _sideEffectWarning = error;
          }
        }
      } else {
        unawaited(_loadPreviews());
      }
      return true;
    } catch (e) {
      _lastError = e;
      return false;
    } finally {
      _isSubmitting = false;
      notifyListeners();
    }
  }

  Future<bool> undoLast() async {
    final receipt = _lastReceipt;
    if (receipt == null || _currentIndex == 0 || _isSubmitting) return false;
    _isSubmitting = true;
    notifyListeners();

    try {
      final ledger = ledgerResolver.resolve(receipt.source);
      final ok = await ledger.undo(receipt);
      if (!ok) return false;

      if (onOutcomeUndone != null) {
        try {
          await onOutcomeUndone!(receipt);
        } catch (error) {
          _sideEffectWarning = error;
        }
      }

      _previewGeneration++;
      _currentIndex--;
      if (receipt.outcome == RecallOutcome.remembered) {
        if (_rememberedCount > 0) _rememberedCount--;
      } else {
        if (_forgottenCount > 0) _forgottenCount--;
      }

      _lastReceipt = null;
      _isRevealed = false;
      _isComplete = false;
      await _loadPreviews();
      return true;
    } catch (error) {
      _lastError = error;
      return false;
    } finally {
      _isSubmitting = false;
      notifyListeners();
    }
  }
}
