import 'package:turna/application/anki_official/contract/official_anki_dto.dart';
import 'package:turna/application/anki_official/engine/official_anki_lesson_redo_flush.dart';
import 'package:turna/application/anki_official/engine/official_anki_lesson_unlock_quota.dart';
import 'package:turna/application/anki_official/engine/official_anki_lock_reconciler.dart';
import 'package:turna/application/anki_official/introduction/card_introduction_store.dart';
import 'package:turna/application/anki_official/projection/anki_lesson_card_key_resolver.dart';
import 'package:turna/application/anki_official/projection/official_anki_lesson_card_index.dart';
import 'package:turna/application/game_provider.dart';
import 'package:turna/application/mistake_review_assembler.dart';
import 'package:turna/application/weak_word_quiz_assembler.dart';
import 'package:turna/core/logger.dart';
import 'package:turna/domain/anki/canonical_card_key.dart';
import 'package:turna/domain/course/interaction.dart';
import 'package:turna/domain/course/stage.dart';
import 'package:turna/di/injection.dart';

/// One submitted interaction, as seen by the completion side effects:
/// where the item lives in the lesson tree and whether the learner got it
/// right on any attempt.
typedef SubmittedInteractionRecord = ({
  int stageIndex,
  int interactionIndex,
  bool correct,
});

/// Official-Anki side effects of finishing a lesson (extracted from
/// [LessonViewModel] — behavior is locked by lesson_viewmodel_flow_test):
///
/// 1. unlock every Official card of the lesson (ADR 0037; mid-lesson exit
///    leaves cards unintroduced),
/// 2. redo → flush the pass's ahead-answers (`again` for any wrong attempt),
///    first pass → reserve introduction quota for the lesson's cards.
class OfficialAnkiLessonCompletionService {
  OfficialAnkiLessonCompletionService({AnkiLessonCardKeyResolver? keyResolver})
    : _keyResolver = keyResolver ?? AnkiLessonCardKeyResolver();

  final AnkiLessonCardKeyResolver _keyResolver;

  /// Runs the completion side effects for [lessonId].
  ///
  /// Returns whether the redo flush failed in a way the user should be told
  /// about (first-pass completions always return `false`).
  Future<bool> onLessonComplete({
    required String lessonId,
    required List<Stage> stages,
    required List<SubmittedInteractionRecord> submitted,
  }) async {
    final index = await _keyResolver.ensureOfficialCardIndex(lessonId);
    final isRedo = _isAnkiLessonRedo(lessonId);
    await _unlockAnkiCardsOnComplete(
      lessonId: lessonId,
      stages: stages,
      index: index,
    );
    if (isRedo) {
      final result = await OfficialAnkiLessonRedoFlush.resolve().flush(
        _officialRatingsForCompletedPass(
          stages: stages,
          submitted: submitted,
          index: index,
        ),
      );
      return result.userShouldBeNotified;
    }
    await OfficialAnkiLessonUnlockQuota.resolve().ensureForCardIds(
          _ankiCardIdsInLesson(stages: stages, index: index, lessonId: lessonId),
        );
    return false;
  }

  bool _isAnkiLessonRedo(String lessonId) {
    if (!getIt.isRegistered<GameProvider>()) return false;
    return getIt<GameProvider>().isLessonCompleted(lessonId);
  }

  List<OfficialAheadAnswer> _officialRatingsForCompletedPass({
    required List<Stage> stages,
    required List<SubmittedInteractionRecord> submitted,
    required OfficialAnkiLessonCardIndex? index,
  }) {
    // The redo flush answers on the Official engine, so it is an
    // Official-projection-lesson feature: without an index there is nothing
    // to rate, and legacy card ids must never reach `answerAheadCards`.
    if (index == null) return const [];
    final anyWrong = <int, bool>{};
    for (final entry in submitted) {
      if (entry.stageIndex < 0 || entry.stageIndex >= stages.length) {
        continue;
      }
      final items = stages[entry.stageIndex].items;
      if (entry.interactionIndex < 0 || entry.interactionIndex >= items.length) {
        continue;
      }
      final cardId = index.cardIdForInteraction(items[entry.interactionIndex]);
      if (cardId == null) continue;
      anyWrong[cardId] = (anyWrong[cardId] ?? false) || !entry.correct;
    }
    return [
      for (final entry in anyWrong.entries)
        OfficialAheadAnswer(
          cardId: entry.key,
          rating: entry.value ? 'again' : 'good',
        ),
    ];
  }

  /// ADR 0037: unlock every Official card in this Lesson after the lesson
  /// completes. Mid-lesson exit leaves cards unintroduced.
  Future<void> _unlockAnkiCardsOnComplete({
    required String lessonId,
    required List<Stage> stages,
    required OfficialAnkiLessonCardIndex? index,
  }) async {
    if (lessonId == MistakeReviewAssembler.lessonId ||
        lessonId == WeakWordQuizAssembler.lessonId) {
      return;
    }
    final store = CardIntroductionStore.resolve();
    if (index != null) {
      // Official projection lesson: the index is the single source of the
      // lesson's cards — mark each one by its structured identity.
      // Ledger-direct: a cold process must still see which cards an
      // earlier session already taught, or a redo would lift the lock off
      // cards the user suspended afterwards.
      final alreadyIntroduced = await store.introducedCardIdsFromLedger(
        index.sourceId,
      );
      final newlyIntroduced = [
        for (final cardId in index.cardIds)
          if (!alreadyIntroduced.contains(cardId)) cardId,
      ];
      if (newlyIntroduced.isNotEmpty) {
        // P1: the completion gate is a scheduler suspension, so lift it
        // BEFORE the ledger records the cards as introduced. A failure or
        // crash mid-way leaves every card unintroduced-and-suspended (the
        // reconciler keeps that state consistent) instead of introduced
        // but invisible; only never-introduced cards are restored, so a
        // user suspension of an already-taught card survives a redo.
        try {
          await OfficialAnkiLockReconciler.resolve().unlockCards(
            sourceId: index.sourceId,
            cardIds: newlyIntroduced,
          );
        } catch (error) {
          logger.w(
            'Official unlock failed; keeping cards unintroduced: $error',
          );
          return;
        }
      }
      for (final entry in index.entries) {
        await store.markIntroducedCard(
          sourceId: index.sourceId,
          cardId: entry.cardId,
          wordId: entry.wordId,
          lessonId: lessonId,
        );
      }
      return;
    }
    // Legacy imported courses: unlock through the stored-wordId convention.
    final unlocked = <int>{};
    for (final stage in stages) {
      for (final item in stage.items) {
        final candidates = <String>[
          if (item is ShowWord && item.wordId.isNotEmpty) item.wordId,
          ankiWordIdFromInteractionId(item.id),
          item.id,
        ];
        for (final candidate in candidates) {
          final key = CanonicalCardKeyAdapter.tryParseStoredWordId(
            profileId: AnkiLessonCardKeyResolver.profileId,
            rawId: candidate,
          );
          if (key == null || !unlocked.add(key.cardId)) continue;
          await store.markFromLesson(wordId: candidate, lessonId: lessonId);
          break;
        }
      }
    }
  }

  Iterable<int> _ankiCardIdsInLesson({
    required List<Stage> stages,
    required OfficialAnkiLessonCardIndex? index,
    required String lessonId,
  }) sync* {
    if (index != null) {
      yield* index.cardIds;
      return;
    }
    for (final stage in stages) {
      for (final item in stage.items) {
        final key = _keyResolver.canonicalKeyForAnkiInteraction(
          item,
          lessonId: lessonId,
        );
        if (key != null) yield key.cardId;
      }
    }
  }
}
