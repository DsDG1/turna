import 'package:turna/application/anki_official/contract/official_anki_dto.dart';
import 'package:turna/application/anki_official/contract/official_anki_errors.dart';
import 'package:turna/application/anki_official/engine/official_anki_audit_log.dart';
import 'package:turna/application/anki_official/engine/official_anki_engine.dart';
import 'package:turna/application/anki_official/engine/official_anki_mutation_receipt.dart';
import 'package:turna/application/anki_official/engine/official_anki_operation_coordinator.dart';
import 'package:turna/application/anki_official/migration/official_anki_write_owner.dart';
import 'package:turna/application/anki_official/official_anki_feature_flags.dart';

enum OfficialReviewPhase {
  idle,
  opening,
  loadingQueue,
  showingQuestion,
  showingAnswer,
  committingAnswer,
  reconciling,
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
    this.receipts,
    this.coordinator,
    this.audit,
    this.profileId = 'profile-default-01',
  }) : flags = flags ?? OfficialAnkiFeatureFlags.current;

  final OfficialAnkiEngine engine;
  final OfficialAnkiFeatureFlags flags;
  final OfficialAnkiMutationReceiptStore? receipts;
  final OfficialAnkiOperationCoordinator? coordinator;
  final OfficialAnkiAuditLog? audit;
  final String profileId;

  OfficialReviewPhase phase = OfficialReviewPhase.idle;
  OfficialReviewQueue? queue;
  OfficialReviewQueueCard? current;
  OfficialAnkiException? lastError;
  var inFlight = false;
  var disposed = false;
  var questionShownAt = 0;
  final Stopwatch answerVisibleElapsed = Stopwatch();
  OfficialCongratsInfo? congrats;
  OfficialUndoStatus? undoStatus;
  var isFilteredDeck = false;
  String? lastClientMutationId;
  String? blockedMutationId;

  bool get canUndo => undoStatus?.canUndo == true;
  bool get canRedo => undoStatus?.canRedo == true;

  bool get isCompleted =>
      phase == OfficialReviewPhase.completed &&
      congrats != null &&
      current == null;

  Future<void> openDeck(int deckId) async {
    if (disposed) return;
    _requireFlag();
    coordinator?.acquire(OfficialAnkiOperationPhase.reviewing);
    phase = OfficialReviewPhase.opening;
    try {
      await engine.setCurrentDeck(deckId);
      await refreshQueue();
      await _refreshStatus();
    } catch (error) {
      if (phase == OfficialReviewPhase.recoverableError ||
          phase == OfficialReviewPhase.staleContext ||
          phase == OfficialReviewPhase.completed) {
        return;
      }
      applyFailure(error);
    }
  }

  /// Pick a real due deck instead of assuming Anki Default (`deckId == 1`).
  Future<void> openDueDeck({int? preferredDeckId}) async {
    if (disposed) return;
    _requireFlag();
    coordinator?.acquire(OfficialAnkiOperationPhase.reviewing);
    phase = OfficialReviewPhase.opening;
    try {
      final decks = await engine.listDeckTree();
      OfficialAnkiDeckNode? best;
      var bestDue = -1;
      for (final deck in orderDecksForReview(
        decks,
        preferredDeckId: preferredDeckId,
      )) {
        await engine.setCurrentDeck(deck.deckId);
        try {
          final probed = await engine.getReviewQueue(fetchLimit: 1);
          final due = probed.newCount + probed.learningCount + probed.reviewCount;
          if (probed.cards.isEmpty) continue;
          if (due > bestDue) {
            best = deck;
            bestDue = due;
          }
        } on OfficialAnkiException catch (error) {
          if (error.code == OfficialAnkiErrorCode.queueEmpty) continue;
          applyFailure(error);
          return;
        }
      }
      if (best == null) {
        current = null;
        queue = null;
        congrats = await engine.congratsInfo();
        phase = OfficialReviewPhase.completed;
        lastError = null;
        await _refreshStatus();
        return;
      }
      await engine.setCurrentDeck(best.deckId);
      await refreshQueue();
      await _refreshStatus();
    } catch (error) {
      if (phase == OfficialReviewPhase.recoverableError ||
          phase == OfficialReviewPhase.staleContext ||
          phase == OfficialReviewPhase.completed) {
        return;
      }
      applyFailure(error);
    }
  }

  static List<OfficialAnkiDeckNode> orderDecksForReview(
    List<OfficialAnkiDeckNode> decks, {
    int? preferredDeckId,
  }) {
    final usable = decks.where((deck) => deck.deckId > 0).toList();
    usable.sort((a, b) {
      if (preferredDeckId != null) {
        if (a.deckId == preferredDeckId && b.deckId != preferredDeckId) {
          return -1;
        }
        if (b.deckId == preferredDeckId && a.deckId != preferredDeckId) {
          return 1;
        }
      }
      final dueCmp = b.dueCount.compareTo(a.dueCount);
      if (dueCmp != 0) return dueCmp;
      final aDefault = a.name == 'Default';
      final bDefault = b.name == 'Default';
      if (aDefault != bDefault) return aDefault ? 1 : -1;
      return a.deckId.compareTo(b.deckId);
    });
    return usable;
  }

  Future<void> refreshQueue() async {
    if (disposed) return;
    _requireFlag();
    phase = OfficialReviewPhase.loadingQueue;
    try {
      queue = await engine.getReviewQueue(fetchLimit: 1);
      current = queue!.cards.isEmpty ? null : queue!.cards.first;
      if (current == null) {
        congrats = await engine.congratsInfo();
        phase = OfficialReviewPhase.completed;
        lastError = null;
      } else {
        phase = OfficialReviewPhase.showingQuestion;
        questionShownAt = DateTime.now().millisecondsSinceEpoch;
        if (receipts?.hasBlocking(current!.cardId) == true) {
          phase = OfficialReviewPhase.reconciling;
          lastError = const OfficialAnkiException(
            code: OfficialAnkiErrorCode.needsReconciliation,
            messageKey: 'official_anki.answer_commit_unknown',
            recoverable: true,
          );
        } else {
          lastError = null;
        }
      }
    } on OfficialAnkiException catch (error) {
      if (error.code == OfficialAnkiErrorCode.queueEmpty) {
        current = null;
        queue = null;
        congrats = await engine.congratsInfo();
        phase = OfficialReviewPhase.completed;
        lastError = null;
        return;
      }
      lastError = error;
      phase = error.code == OfficialAnkiErrorCode.schedulingContextStale
          ? OfficialReviewPhase.staleContext
          : OfficialReviewPhase.recoverableError;
    }
  }

  void showAnswer() {
    if (disposed) return;
    if (phase != OfficialReviewPhase.showingQuestion || current == null) {
      return;
    }
    phase = OfficialReviewPhase.showingAnswer;
    answerVisibleElapsed
      ..reset()
      ..start();
  }

  Future<void> answer(String rating) async {
    if (disposed || inFlight || phase != OfficialReviewPhase.showingAnswer) {
      return;
    }
    final card = current;
    final q = queue;
    if (card == null || q == null) return;
    if (receipts?.hasBlocking(card.cardId) == true) {
      phase = OfficialReviewPhase.reconciling;
      lastError = const OfficialAnkiException(
        code: OfficialAnkiErrorCode.needsReconciliation,
        messageKey: 'official_anki.answer_commit_unknown',
        recoverable: true,
      );
      return;
    }
    coordinator?.guardSchedulerWrite();
    inFlight = true;
    phase = OfficialReviewPhase.committingAnswer;
    answerVisibleElapsed.stop();
    lastClientMutationId =
        'mut-${q.queueEpoch}-${card.cardId}-${DateTime.now().microsecondsSinceEpoch}';
    final now = DateTime.now().millisecondsSinceEpoch;
    receipts?.prepare(
      mutationId: lastClientMutationId!,
      cardId: card.cardId,
      queueEpoch: q.queueEpoch,
      rating: rating,
      nowMillis: now,
    );
    try {
      final elapsed = answerVisibleElapsed.elapsedMilliseconds;
      await engine.answerCard(
        sessionId: q.sessionId,
        queueEpoch: q.queueEpoch,
        answerToken: card.answerToken,
        cardId: card.cardId,
        rating: rating,
        millisecondsTaken: elapsed < 0 ? 0 : elapsed,
        clientMutationId: lastClientMutationId,
      );
      receipts?.markCommitted(lastClientMutationId!, now);
      _audit('answer', card.cardId);
      phase = OfficialReviewPhase.refreshingQueue;
      await refreshQueue();
      await _refreshStatus();
    } on OfficialAnkiException catch (error) {
      lastError = error;
      if (error.code == OfficialAnkiErrorCode.schedulingContextStale) {
        phase = OfficialReviewPhase.staleContext;
      } else if (error.code == OfficialAnkiErrorCode.answerCommitUnknown) {
        receipts?.markUnknown(lastClientMutationId!, now);
        blockedMutationId = lastClientMutationId;
        phase = OfficialReviewPhase.reconciling;
        lastError = error;
      } else {
        phase = error.recoverable
            ? OfficialReviewPhase.recoverableError
            : OfficialReviewPhase.fatalError;
      }
    } finally {
      inFlight = false;
    }
  }

  Future<void> undo() async {
    if (disposed || inFlight || !canUndo) return;
    coordinator?.guardSchedulerWrite();
    inFlight = true;
    try {
      await engine.undo();
      _audit('undo', current?.cardId);
      await refreshQueue();
      await _refreshStatus();
    } catch (error) {
      applyFailure(error);
    } finally {
      inFlight = false;
    }
  }

  Future<void> redo() async {
    if (disposed || inFlight || !canRedo) return;
    coordinator?.guardSchedulerWrite();
    inFlight = true;
    try {
      await engine.redo();
      _audit('redo', current?.cardId);
      await refreshQueue();
      await _refreshStatus();
    } catch (error) {
      applyFailure(error);
    } finally {
      inFlight = false;
    }
  }

  Future<void> buryOrSuspend(OfficialBuryOrSuspendAction action) async {
    if (disposed || inFlight || current == null) return;
    if (isFilteredDeck) {
      lastError = const OfficialAnkiException(
        code: OfficialAnkiErrorCode.invalidState,
        messageKey: 'official_anki.filtered_deck_unsupported',
        recoverable: true,
      );
      phase = OfficialReviewPhase.recoverableError;
      return;
    }
    coordinator?.guardSchedulerWrite();
    inFlight = true;
    try {
      await engine.buryOrSuspendCards(
        action: action,
        cardIds: [current!.cardId],
      );
      _audit(action.wireName, current?.cardId);
      await refreshQueue();
      await _refreshStatus();
    } catch (error) {
      applyFailure(error);
    } finally {
      inFlight = false;
    }
  }

  Future<void> _refreshStatus() async {
    try {
      undoStatus = await engine.getUndoStatus();
      congrats = await engine.congratsInfo();
      isFilteredDeck = congrats?.isFilteredDeck ?? false;
    } catch (_) {}
  }

  void _audit(String operation, int? cardId) {
    audit?.record(
      owner: AnkiWriteOwner.officialScheduler,
      operation: operation,
      requestId: lastClientMutationId ?? operation,
      cardId: cardId,
    );
  }

  void applyFailure(Object error) {
    if (disposed) return;
    if (error is OfficialAnkiException) {
      lastError = error;
      if (error.code == OfficialAnkiErrorCode.schedulingContextStale) {
        phase = OfficialReviewPhase.staleContext;
      } else if (error.code == OfficialAnkiErrorCode.answerCommitUnknown) {
        phase = OfficialReviewPhase.reconciling;
      } else if (error.recoverable) {
        phase = OfficialReviewPhase.recoverableError;
      } else {
        phase = OfficialReviewPhase.fatalError;
      }
      return;
    }
    lastError = OfficialAnkiException(
      code: OfficialAnkiErrorCode.internalError,
      messageKey: 'official_anki.internal_error',
      debugDetails: error.toString(),
    );
    phase = OfficialReviewPhase.fatalError;
  }

  void dispose() {
    disposed = true;
    answerVisibleElapsed.stop();
    coordinator?.release(OfficialAnkiOperationPhase.reviewing);
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
