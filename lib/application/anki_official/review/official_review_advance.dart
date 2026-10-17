import 'package:turna/application/anki_official/engine/official_anki_review_session.dart';
import 'package:turna/application/anki_official/review/official_formal_review_coordinator.dart';
import 'package:turna/application/study_session/study_session_controller.dart';
import 'package:turna/core/logger.dart';
import 'package:turna/domain/anki/study_models.dart';
import 'package:turna/domain/review/recall_outcome.dart';

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

/// Advance after the native OHOS page committed a rating through the grades
/// bridge (the bridge answers the scheduler directly; the session controller
/// only learns about it here).
///
/// Returns whether another card is on screen (`true`) or the queue finished
/// (`false`) — the OHOS page's receipt contract. Throws when the scheduler
/// committed but left no client mutation id: the rating is in the engine and
/// the controller has no receipt to advance with, so the caller must answer
/// the page with a retryable failure code instead of claiming progress.
///
/// The mutation id is set unconditionally before `engine.answerCard` inside
/// `answerAndConfirm` and never cleared, so the empty branch only fires on a
/// disposed-session race — where a retry that re-reads the id is exactly the
/// right recovery.
Future<bool> advanceFromNativeRating({
  required StudySessionController controller,
  required OfficialReviewSession officialSession,
  required OfficialFormalReviewLiveQueue? liveQueue,
  required String rating,
}) async {
  final eventId = officialSession.lastClientMutationId;
  if (eventId == null || eventId.isEmpty) {
    logger.w('[OfficialAnki] native rating committed without a mutation id; '
        'refusing to advance the session blindly');
    throw StateError('official native rating lost its mutation id');
  }
  final outcome = rating == 'again' || rating == 'hard'
      ? RecallOutcome.forgotten
      : RecallOutcome.remembered;
  controller.acceptExternalOfficialCommit(outcome: outcome, eventId: eventId);
  await advanceFromScheduler(
    controller: controller,
    officialSession: officialSession,
    liveQueue: liveQueue,
  );
  return !controller.isComplete &&
      controller.phase != StudyCardPhase.readyForNext;
}

/// Advance after a scheduler mutation the native OHOS page asked for (redo /
/// bury / suspend, D8).
///
/// Same return contract as [advanceFromNativeRating] — `true` when another card
/// is on screen, `false` when the queue finished — but with no commit of its
/// own: the mutation already happened in the engine, and unlike a rating there
/// is no client mutation id to feed back into the controller.
///
/// Deliberately not folded into [advanceFromScheduler]: the two callers above
/// only want the move, while the native page also needs to know whether the
/// session is over, and the difference decides whether the receipt is `ok` or
/// `ok_complete`.
Future<bool> advanceAfterNativeMutation({
  required StudySessionController controller,
  required OfficialReviewSession officialSession,
  required OfficialFormalReviewLiveQueue? liveQueue,
}) async {
  await advanceFromScheduler(
    controller: controller,
    officialSession: officialSession,
    liveQueue: liveQueue,
  );
  return !controller.isComplete &&
      controller.phase != StudyCardPhase.readyForNext;
}
