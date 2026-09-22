import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:turna/application/review/review_ledger_resolver.dart';
import 'package:turna/core/logger.dart';
import 'package:turna/domain/review/recall_outcome.dart';
import 'package:turna/domain/review/review_item.dart';
import 'package:turna/domain/review/review_ledger.dart';

class _PendingWrite {
  _PendingWrite(this.item, this.outcome, this.cachedPreview);
  final ReviewItem item;
  final RecallOutcome outcome;
  final ReviewPreview? cachedPreview;
}

/// State and business logic controller for a unified review session.
///
/// Ensures:
/// - One card, one answer, one unique ledger write.
/// - Item is locked during submission to prevent double taps.
/// - Authoritative interval previews fetched from the active ledger.
/// - Idempotent, receipt-based single undo.
/// - Non-last cards advance before the ledger write settles; undo is gated
///   until persist completes ([isPersisting]). The last card stays on screen
///   until persist succeeds so a write failure can be retried.
class ReviewSessionController extends ChangeNotifier {
  final List<ReviewItem> items;
  final ReviewLedgerResolver ledgerResolver;
  final Future<void> Function(ReviewItem item, RecallOutcome outcome)?
      onOutcomeRecorded;
  final Future<void> Function(ReviewEventReceipt receipt)? onOutcomeUndone;
  final Future<void> Function(int remembered, int forgotten)?
      onSessionCompleted;

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
  bool _isPersisting = false;
  bool _isComplete = false;
  ReviewEventReceipt? _lastReceipt;
  Object? _previewError;
  Object? _writeError;
  Object? _sideEffectWarning;
  int _previewGeneration = 0;
  _PendingWrite? _pendingWrite;

  ReviewPreview? _forgottenPreview;
  ReviewPreview? _rememberedPreview;

  int _rememberedCount = 0;
  int _forgottenCount = 0;
  final DateTime _startedAt = DateTime.now();

  int get currentIndex => _currentIndex;
  bool get isRevealed => _isRevealed;
  bool get isSubmitting => _isSubmitting;
  bool get isPersisting => _isPersisting;
  bool get isComplete => _isComplete;
  ReviewEventReceipt? get lastReceipt => _lastReceipt;
  Object? get previewError => _previewError;
  Object? get writeError => _writeError;

  /// Combined error for older callers. Preview failures no longer block
  /// grading; prefer [previewError] / [writeError].
  Object? get lastError => _writeError ?? _previewError;
  Object? get sideEffectWarning => _sideEffectWarning;

  ReviewPreview? get forgottenPreview =>
      _previewError == null ? _forgottenPreview : null;
  ReviewPreview? get rememberedPreview =>
      _previewError == null ? _rememberedPreview : null;

  int get rememberedCount => _rememberedCount;
  int get forgottenCount => _forgottenCount;
  int get answeredCount => _rememberedCount + _forgottenCount;
  int get remainingCount =>
      (_currentIndex >= items.length) ? 0 : items.length - _currentIndex;
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
      _previewError = null;
      notifyListeners();
    } catch (error) {
      if (generation != _previewGeneration) return;
      _previewError = error;
      notifyListeners();
    }
  }

  /// Retry the current card's preview load after a failure.
  Future<void> retryPreviews() async {
    _previewError = null;
    notifyListeners();
    await _loadPreviews();
  }

  /// Retry the last optimistic write if it failed.
  Future<bool> retryWrite() => _persistPending();

  Future<bool> answer(RecallOutcome outcome) async {
    final item = currentItem;
    if (item == null ||
        _isSubmitting ||
        _isComplete ||
        _isPersisting ||
        _pendingWrite != null) {
      return false;
    }
    _isSubmitting = true;
    _writeError = null;
    final cachedPreview = outcome == RecallOutcome.remembered
        ? _rememberedPreview
        : _forgottenPreview;
    _pendingWrite = _PendingWrite(item, outcome, cachedPreview);
    if (outcome == RecallOutcome.remembered) {
      _rememberedCount++;
    } else {
      _forgottenCount++;
    }
    final finishing = _currentIndex >= items.length - 1;
    _previewGeneration++;
    if (!finishing) {
      _currentIndex++;
      _isRevealed = false;
      _forgottenPreview = null;
      _rememberedPreview = null;
    }
    _isSubmitting = false;
    notifyListeners();
    if (!finishing) {
      unawaited(_loadPreviews());
    }
    return _persistPending();
  }

  Future<bool> _persistPending() async {
    final pending = _pendingWrite;
    if (pending == null) return true;
    _isPersisting = true;
    notifyListeners();
    try {
      final ledger = ledgerResolver.resolve(pending.item.source);
      final receipt = await ledger.answer(
        pending.item.schedulingKey,
        pending.outcome,
        cachedPreview: pending.cachedPreview,
      );
      _lastReceipt = receipt;
      _pendingWrite = null;
      _writeError = null;
      if (onOutcomeRecorded != null) {
        try {
          await onOutcomeRecorded!(pending.item, pending.outcome);
        } catch (error) {
          _sideEffectWarning = error;
        }
      }
      final finishing = items.isNotEmpty &&
          pending.item.sessionItemId == items.last.sessionItemId;
      if (finishing && !_isComplete) {
        _currentIndex = items.length;
        _isComplete = true;
      }
      if (_isComplete && onSessionCompleted != null) {
        try {
          await onSessionCompleted!(_rememberedCount, _forgottenCount);
        } catch (error) {
          _sideEffectWarning = error;
        }
      }
      return true;
    } catch (e, st) {
      logger.w('Review session persist failed', error: e, stackTrace: st);
      _writeError = e;
      return false;
    } finally {
      _isPersisting = false;
      notifyListeners();
    }
  }

  Future<bool> undoLast() async {
    final receipt = _lastReceipt;
    if (receipt == null ||
        _currentIndex == 0 ||
        _isSubmitting ||
        _isPersisting ||
        _pendingWrite != null) {
      return false;
    }
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
      _writeError = error;
      return false;
    } finally {
      _isSubmitting = false;
      notifyListeners();
    }
  }
}
