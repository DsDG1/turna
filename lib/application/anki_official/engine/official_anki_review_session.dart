import 'package:turna/application/anki_official/contract/official_anki_dto.dart';
import 'package:turna/application/anki_official/contract/official_anki_errors.dart';
import 'package:turna/application/anki_official/engine/official_anki_engine.dart';
import 'package:turna/application/anki_official/official_anki_feature_flags.dart';

enum OfficialReviewPhase {
  idle,
  opening,
  loadingQueue,
  showingQuestion,
  showingAnswer,
  committingAnswer,
  refreshingQueue,
  completed,
  recoverableError,
  staleContext,
  fatalError,
}

/// Single-flight official review session. Holds opaque tokens only.
class OfficialReviewSession {
  OfficialReviewSession({
    required this.engine,
    OfficialAnkiFeatureFlags? flags,
  }) : flags = flags ?? OfficialAnkiFeatureFlags.current;

  final OfficialAnkiEngine engine;
  final OfficialAnkiFeatureFlags flags;

  OfficialReviewPhase phase = OfficialReviewPhase.idle;
  OfficialReviewQueue? queue;
  OfficialReviewQueueCard? current;
  OfficialAnkiException? lastError;
  var inFlight = false;
  var questionShownAt = 0;
  OfficialCongratsInfo? congrats;

  Future<void> openDeck(int deckId) async {
    _requireFlag();
    phase = OfficialReviewPhase.opening;
    await engine.setCurrentDeck(deckId);
    await refreshQueue();
  }

  Future<void> refreshQueue() async {
    _requireFlag();
    phase = OfficialReviewPhase.loadingQueue;
    try {
      queue = await engine.getReviewQueue(fetchLimit: 1);
      current = queue!.cards.isEmpty ? null : queue!.cards.first;
      if (current == null) {
        congrats = await engine.congratsInfo();
        phase = OfficialReviewPhase.completed;
      } else {
        phase = OfficialReviewPhase.showingQuestion;
        questionShownAt = DateTime.now().millisecondsSinceEpoch;
      }
      lastError = null;
    } on OfficialAnkiException catch (error) {
      if (error.code == OfficialAnkiErrorCode.queueEmpty) {
        congrats = await engine.congratsInfo();
        phase = OfficialReviewPhase.completed;
        return;
      }
      lastError = error;
      phase = error.code == OfficialAnkiErrorCode.schedulingContextStale
          ? OfficialReviewPhase.staleContext
          : OfficialReviewPhase.recoverableError;
    }
  }

  void showAnswer() {
    if (phase != OfficialReviewPhase.showingQuestion || current == null) {
      return;
    }
    phase = OfficialReviewPhase.showingAnswer;
  }

  Future<void> answer(String rating) async {
    if (inFlight || phase != OfficialReviewPhase.showingAnswer) return;
    final card = current;
    final q = queue;
    if (card == null || q == null) return;
    inFlight = true;
    phase = OfficialReviewPhase.committingAnswer;
    try {
      final elapsed =
          DateTime.now().millisecondsSinceEpoch - questionShownAt;
      await engine.answerCard(
        sessionId: q.sessionId,
        queueEpoch: q.queueEpoch,
        answerToken: card.answerToken,
        cardId: card.cardId,
        rating: rating,
        millisecondsTaken: elapsed < 0 ? 0 : elapsed,
      );
      phase = OfficialReviewPhase.refreshingQueue;
      await refreshQueue();
    } on OfficialAnkiException catch (error) {
      lastError = error;
      if (error.code == OfficialAnkiErrorCode.schedulingContextStale) {
        phase = OfficialReviewPhase.staleContext;
        current = null;
        await refreshQueue();
      } else {
        phase = OfficialReviewPhase.recoverableError;
      }
    } finally {
      inFlight = false;
    }
  }

  Future<void> undo() async {
    if (inFlight) return;
    inFlight = true;
    try {
      await engine.undo();
      await refreshQueue();
    } finally {
      inFlight = false;
    }
  }

  Future<void> redo() async {
    if (inFlight) return;
    inFlight = true;
    try {
      await engine.redo();
      await refreshQueue();
    } finally {
      inFlight = false;
    }
  }

  Future<void> buryOrSuspend(OfficialBuryOrSuspendAction action) async {
    if (inFlight || current == null) return;
    inFlight = true;
    try {
      await engine.buryOrSuspendCards(
        action: action,
        cardIds: [current!.cardId],
      );
      await refreshQueue();
    } finally {
      inFlight = false;
    }
  }

  void _requireFlag() {
    if (!flags.allowsOfficialScheduler) {
      throw const OfficialAnkiException(
        code: OfficialAnkiErrorCode.schedulerCapabilityMissing,
        messageKey: 'official_anki.scheduler_flag_fail_closed',
      );
    }
  }
}
