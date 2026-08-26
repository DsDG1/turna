import 'package:flutter/foundation.dart';
import 'package:turna/application/anki_official/contract/official_anki_errors.dart';

/// Where in the render pipeline a card failed (maintainability plan §8.1).
enum OfficialRenderFailureStage {
  /// Initial batch render (loader pass).
  load,

  /// Live-queue rebuild render.
  rebuild,

  /// Retry of a previously failed card.
  retry,
}

/// Structured record for one card that could not be rendered. Carries
/// identity + stable code only — never card content, HTML, typed answers
/// or media paths (maintainability plan §8.5).
@immutable
class OfficialCardRenderFailure {
  const OfficialCardRenderFailure({
    required this.sourceId,
    required this.cardId,
    required this.code,
    required this.stage,
    required this.recoverable,
    this.debugDetails,
    this.renderGeneration = 0,
  });

  final String sourceId;
  final int cardId;

  /// Stable machine code: `OfficialAnkiErrorCode.name` when the engine
  /// threw a typed exception, `render_internal_error` otherwise.
  final String code;
  final OfficialRenderFailureStage stage;
  final bool recoverable;

  /// Debug-only detail. Never shown in release UI, never logged with card
  /// content.
  final String? debugDetails;

  /// Queue epoch / render generation the failure belongs to.
  final int renderGeneration;

  static OfficialCardRenderFailure fromError(
    Object error, {
    required String sourceId,
    required int cardId,
    required OfficialRenderFailureStage stage,
    int renderGeneration = 0,
  }) {
    if (error is OfficialAnkiException) {
      return OfficialCardRenderFailure(
        sourceId: sourceId,
        cardId: cardId,
        code: error.code.name,
        stage: stage,
        recoverable: error.recoverable,
        debugDetails: error.debugDetails,
        renderGeneration: renderGeneration,
      );
    }
    return OfficialCardRenderFailure(
      sourceId: sourceId,
      cardId: cardId,
      code: 'render_internal_error',
      stage: stage,
      recoverable: false,
      debugDetails: error.toString(),
      renderGeneration: renderGeneration,
    );
  }
}

/// Typed live-queue rebuild outcome (maintainability plan §8.3).
sealed class OfficialLiveQueueRebuildResult {
  const OfficialLiveQueueRebuildResult();
}

final class OfficialLiveQueueRebuilt extends OfficialLiveQueueRebuildResult {
  const OfficialLiveQueueRebuilt();
}

/// The scheduler's current card cannot be rendered: the previous UI
/// snapshot stays, scoring is locked, and the failure is exposed for the
/// page to show (retry / continue-later). Never silently swallowed.
final class OfficialLiveQueueBlockedOnCurrentCard
    extends OfficialLiveQueueRebuildResult {
  const OfficialLiveQueueBlockedOnCurrentCard(this.failure);

  final OfficialCardRenderFailure failure;
}

/// The queue moved under us — a newer rebuild already landed.
final class OfficialLiveQueueRebuildStale
    extends OfficialLiveQueueRebuildResult {
  const OfficialLiveQueueRebuildStale();
}

/// The rebuild itself failed (non-render error). The last good items stay.
final class OfficialLiveQueueRebuildFailed
    extends OfficialLiveQueueRebuildResult {
  const OfficialLiveQueueRebuildFailed(this.error);

  final Object error;
}
