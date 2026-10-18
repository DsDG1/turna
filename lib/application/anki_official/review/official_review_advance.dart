import 'package:turna/application/anki_official/engine/official_anki_review_session.dart';
import 'package:turna/application/anki_official/review/official_formal_review_coordinator.dart';
import 'package:turna/application/study_session/study_session_controller.dart';
import 'package:turna/core/logger.dart';
import 'package:turna/domain/anki/study_models.dart';
import 'package:turna/domain/review/recall_outcome.dart';

/// Moves the controller to the scheduler's current card.
///
/// Live scheduler contract (plan 34 D4): after every committed mutation the
/// next card is the scheduler's refreshed [OfficialReviewSession.current] —
/// never index+1 over a batch list that just shrank or reordered.
///
/// Returns whether the controller **actually moved to another face**. That is
/// not the same as "the call returned": [StudySessionController.advanceTo] is a
/// silent no-op unless the session is `readyForNext`, and
/// [StudySessionController.reportSchedulerDesync] leaves the phase in
/// `recoverableError` without touching the position. Both cases used to look
/// like success to a caller that only awaited this function, and on the
/// HarmonyOS page that meant a rating receipt of `ok` followed by a `present`
/// that never happened — the screen sat on "已提交，加载中…" forever, because
/// the presenter de-duplicates on (cardId, side, presentGeneration) and none of
/// the three had changed.
///
/// `generation` is the signal rather than the phase: it is bumped exactly once
/// per real move inside `_beginCurrent`, so a reinserted same card (`again`)
/// still counts as a move while a refused advance does not.
Future<bool> advanceFromScheduler({
  required StudySessionController controller,
  OfficialReviewSession? officialSession,
  OfficialFormalReviewLiveQueue? liveQueue,
}) async {
  final session = officialSession;
  if (session == null) {
    await controller.continueNext();
    return true;
  }
  final currentCardId = session.current?.cardId;
  if (currentCardId == null) {
    // The scheduler is empty: finishing the session is the move.
    await controller.advanceTo(null);
    return true;
  }
  Future<bool> moveTo(String sessionItemId) async {
    final before = controller.generation;
    await controller.advanceTo(sessionItemId);
    return controller.generation != before;
  }

  for (final item in controller.items) {
    if (item.cardKey.cardId == currentCardId) {
      return moveTo(item.sessionItemId);
    }
  }
  // Give liveQueue one chance to reconcile if rebuild is in flight or pending
  if (liveQueue != null) {
    await liveQueue.rebuildFromLiveQueue();
    for (final item in controller.items) {
      if (item.cardKey.cardId == currentCardId) {
        return moveTo(item.sessionItemId);
      }
    }
  }
  // Unreachable while the scheduler's current always sits inside the
  // assembled batch; surface a structured desync (retryable) instead of
  // silently completing a session the scheduler still owes.
  controller.reportSchedulerDesync(currentCardId);
  return false;
}

/// Advance after the native OHOS page committed a rating through the grades
/// bridge (the bridge answers the scheduler directly; the session controller
/// only learns about it here).
///
/// Returns whether another card is on screen (`true`) or the queue finished
/// (`false`) — the OHOS page's receipt contract. Throws when the advance could
/// not put a card on screen at all, in two distinct cases:
///
///  - the scheduler committed but left no client mutation id: the rating is in
///    the engine and the controller has no receipt to advance with;
///  - the scheduler's current card is not in the assembled batch.
///
/// Neither is `ok`. Returning `true` leaves the page waiting for a `present`
/// that never comes; returning `false` is worse — the page reads that as
/// `ok_complete`, shows the completion summary and hides the retry entry while
/// the scheduler still owes cards. Throwing lands on the one receipt that
/// already means exactly this: `advance_failed` (translated in
/// `OfficialAnkiOhosReviewerBinding._runAdvance`), which keeps the card and
/// re-runs only the advance on retry.
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
  final advanced = await advanceFromScheduler(
    controller: controller,
    officialSession: officialSession,
    liveQueue: liveQueue,
  );
  if (!advanced) {
    throw StateError(
      'scheduler current ${officialSession.current?.cardId} is not in the '
      'assembled batch after a committed native rating',
    );
  }
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
/// A failed advance throws for the same reason as [advanceFromNativeRating]:
/// the page's mutation receipt has no `ok_complete`-shaped lie to fall back on,
/// and `_cardAction` already translates a throw into a refusal that keeps the
/// card and re-arms the entry.
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
  final advanced = await advanceFromScheduler(
    controller: controller,
    officialSession: officialSession,
    liveQueue: liveQueue,
  );
  if (!advanced) {
    throw StateError(
      'scheduler current ${officialSession.current?.cardId} is not in the '
      'assembled batch after a native queue mutation',
    );
  }
  return !controller.isComplete &&
      controller.phase != StudyCardPhase.readyForNext;
}
