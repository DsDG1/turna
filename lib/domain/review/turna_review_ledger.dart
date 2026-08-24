import 'package:turna/application/anki_official/migration/official_anki_write_owner.dart';
import 'package:turna/application/srs_provider.dart';
import 'package:turna/core/sm2.dart';
import 'package:turna/domain/course/srs_word.dart';
import 'package:turna/domain/review/recall_outcome.dart';
import 'package:turna/domain/review/review_item.dart';
import 'package:turna/domain/review/review_ledger.dart';
import 'package:turna/domain/review/review_source.dart';

/// Ledger implementation for Turna course cards and legacy Anki imports.
///
/// Dispatches answers to [SrsProvider] (backed by Turna FSRS), computes authoritative
/// interval previews from the FSRS engine, and provides exact snapshot undo.
class TurnaReviewLedger implements ReviewLedger {
  final SrsProvider _srsProvider;

  TurnaReviewLedger(this._srsProvider);

  /// Registers a Turna-owned Anki word the first time the study session
  /// commits it. Official-owned cards never reach this ledger.
  void ensureWord(String rawId, ReviewSource source) {
    if (source is LegacyAnkiSource) {
      assertLegacySrsAnswerAllowed(importId: source.importId);
    }
    if (!_srsProvider.state.containsKey(rawId)) {
      switch (source) {
        case LegacyAnkiSource(:final importId):
          _srsProvider.registerWord(
            rawId,
            sourceKind: SrsSourceKind.ankiLegacy,
            sourceId: importId,
          );
        case OfficialAnkiSource(:final sourceId):
          _srsProvider.registerWord(
            rawId,
            sourceKind: SrsSourceKind.ankiOfficial,
            sourceId: sourceId,
          );
        case TurnaCourseSource():
          _srsProvider.registerWord(rawId);
      }
    }
  }

  @override
  Future<ReviewDueSummary> dueSummary({String? scope}) async {
    if (scope != null && scope.startsWith('anki:')) {
      final importId = scope.substring(5);
      final cards = _srsProvider.getDueAnkiWords();
      final count = cards
          .where((c) =>
              c.sourceKind == SrsSourceKind.ankiLegacy &&
              c.sourceId == importId)
          .length;
      return ReviewDueSummary(dueCount: count);
    }
    return ReviewDueSummary(
      dueCount: _srsProvider.dueCount + _srsProvider.expressionDueCount,
    );
  }

  @override
  Future<ReviewPreview> preview(
    ReviewSchedulingKey key,
    RecallOutcome outcome,
  ) async {
    final word = _srsProvider.state[key.rawId];
    if (word == null) {
      throw StateError('Review item is not registered: ${key.rawId}');
    }

    if (outcome == RecallOutcome.forgotten) {
      final mins = await _srsProvider.previewFailMinutesFor(word);
      if (mins != null) {
        if (mins <= 0) {
          return const ReviewPreview(intervalLabel: '明天');
        } else if (mins < 60) {
          return ReviewPreview(
            intervalLabel: '$mins分钟',
            estimatedInterval: Duration(minutes: mins),
          );
        } else {
          final hours = (mins / 60).round();
          return ReviewPreview(
            intervalLabel: '$hours小时',
            estimatedInterval: Duration(hours: hours),
          );
        }
      }
      return const ReviewPreview(intervalLabel: '—');
    } else {
      final days = _srsProvider.previewOutcomeDays(
        word,
        ReviewOutcome.pass,
      );
      final label = days <= 0 ? '1天' : '$days天';
      return ReviewPreview(
        intervalLabel: label,
        estimatedInterval: Duration(days: days <= 0 ? 1 : days),
      );
    }
  }

  @override
  Future<ReviewEventReceipt> answer(
    ReviewSchedulingKey key,
    RecallOutcome outcome, {
    int durationMs = 0,
  }) async {
    if (key.source is LegacyAnkiSource) {
      assertLegacySrsAnswerAllowed(
        importId: (key.source as LegacyAnkiSource).importId,
      );
    }
    final now = DateTime.now();
    final word = _srsProvider.state[key.rawId];
    if (word == null) {
      throw StateError('Review item is not registered: ${key.rawId}');
    }
    final previous = word.copyWith();
    final eventId = 'turna_${now.microsecondsSinceEpoch}_${key.rawId}';

    final prev = await preview(key, outcome);
    final isExpression = word.type == SrsItemType.expression;
    final reviewOutcome = outcome == RecallOutcome.remembered
        ? ReviewOutcome.pass
        : ReviewOutcome.fail;

    final SrsWord? updated;
    if (isExpression) {
      updated = await _srsProvider.reviewExpressionOutcome(
        key.rawId,
        reviewOutcome,
        eventSourceKey: eventId,
      );
    } else {
      updated = await _srsProvider.reviewWordOutcome(
        key.rawId,
        reviewOutcome,
        eventSourceKey: eventId,
      );
    }
    if (updated == null) {
      throw StateError('Review was not committed: ${key.rawId}');
    }

    return ReviewEventReceipt(
      eventId: eventId,
      source: key.source,
      schedulingKey: key,
      outcome: outcome,
      reviewedAt: now,
      preview: prev,
      opaqueUndoState: previous,
    );
  }

  @override
  Future<bool> undo(ReviewEventReceipt receipt) async {
    final prev = receipt.opaqueUndoState;
    if (prev is SrsWord) {
      return prev.type == SrsItemType.expression
          ? _srsProvider.rollbackExpression(
              receipt.schedulingKey.rawId,
              prev,
              eventSourceKey: receipt.eventId,
            )
          : _srsProvider.rollbackWord(
              receipt.schedulingKey.rawId,
              prev,
              eventSourceKey: receipt.eventId,
            );
    }
    return false;
  }
}
