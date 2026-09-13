import 'package:turna/application/anki_official/engine/official_anki_review_session.dart';
import 'package:turna/application/anki_official/review/official_formal_review_coordinator.dart';
import 'package:turna/application/study_session/study_session_controller.dart';

/// Live scheduler contract (plan 34 D4): after every committed mutation
/// the next card is the scheduler's refreshed [OfficialReviewSession.current]
/// — never index+1 over a batch list that just shrank or reordered.
///
/// Extracted from the review page's view widget so the advance decision
/// (scheduler-current → controller position, live-queue reconcile, desync
/// report) lives beside the session types it composes.
Future<void> advanceFromScheduler({
  required StudySessionController controller,
  OfficialReviewSession? officialSession,
  OfficialFormalReviewLiveQueue? liveQueue,
}) async {
  final session = officialSession;
  if (session == null) {
    await controller.continueNext();
    return;
  }
  final currentCardId = session.current?.cardId;
  if (currentCardId == null) {
    await controller.advanceTo(null);
    return;
  }
  for (final item in controller.items) {
    if (item.cardKey.cardId == currentCardId) {
      await controller.advanceTo(item.sessionItemId);
      return;
    }
  }
  // Give liveQueue one chance to reconcile if rebuild is in flight or pending
  if (liveQueue != null) {
    await liveQueue.rebuildFromLiveQueue();
    for (final item in controller.items) {
      if (item.cardKey.cardId == currentCardId) {
        await controller.advanceTo(item.sessionItemId);
        return;
      }
    }
  }
  // Unreachable while the scheduler's current always sits inside the
  // assembled batch; surface a structured desync (retryable) instead of
  // silently completing a session the scheduler still owes.
  controller.reportSchedulerDesync(currentCardId);
}
