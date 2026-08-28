import 'package:flutter/foundation.dart';
import 'package:turna/application/anki_official/contract/official_anki_dto.dart';
import 'package:turna/application/anki_official/engine/official_anki_engine.dart';
import 'package:turna/application/anki_official/official_anki_composition.dart';

/// Outcome of a lesson-redo Official flush (ADR 0037 提前复习).
class OfficialAnkiLessonRedoFlushResult {
  const OfficialAnkiLessonRedoFlushResult({
    this.requested = 0,
    this.answered = 0,
    this.skippedRatedToday = 0,
    this.failed = false,
  });

  final int requested;
  final int answered;
  final int skippedRatedToday;
  final bool failed;

  /// True when the user should see a completion-summary line: the engine
  /// was missing, search/answer threw, or fewer cards were written than
  /// the not-yet-rated remainder. Skipping cards already `rated:1` today
  /// is success.
  bool get userShouldBeNotified {
    if (requested <= 0) return false;
    if (failed) return true;
    final remaining = requested - skippedRatedToday;
    return remaining > 0 && answered < remaining;
  }
}

/// Flushes one Official rating per card after a completed Anki lesson is
/// replayed (ADR 0037 提前复习). Fail-closed: missing engine/capability logs
/// and writes nothing to Turna SRS. Cards already rated today are skipped.
class OfficialAnkiLessonRedoFlush {
  const OfficialAnkiLessonRedoFlush({this.engine});

  final OfficialAnkiEngine? engine;

  static OfficialAnkiLessonRedoFlush? debugOverride;

  static OfficialAnkiLessonRedoFlush resolve() =>
      debugOverride ?? const OfficialAnkiLessonRedoFlush();

  Future<OfficialAnkiLessonRedoFlushResult> flush(
    List<OfficialAheadAnswer> answers,
  ) async {
    if (answers.isEmpty) return const OfficialAnkiLessonRedoFlushResult();
    try {
      final resolved = engine ?? OfficialAnkiCompositionRoot.engine;
      if (resolved == null) {
        debugPrint(
          '[OfficialAnkiLessonRedoFlush] official engine unavailable',
        );
        return OfficialAnkiLessonRedoFlushResult(
          requested: answers.length,
          failed: true,
        );
      }
      final ratedToday = await _ratedTodayIds(
        resolved,
        {for (final answer in answers) answer.cardId},
      );
      final pending = [
        for (final answer in answers)
          if (!ratedToday.contains(answer.cardId)) answer,
      ];
      final skipped = answers.length - pending.length;
      if (pending.isEmpty) {
        return OfficialAnkiLessonRedoFlushResult(
          requested: answers.length,
          skippedRatedToday: skipped,
        );
      }
      final answered = await resolved.answerAheadCards(pending);
      return OfficialAnkiLessonRedoFlushResult(
        requested: answers.length,
        answered: answered,
        skippedRatedToday: skipped,
        failed: answered < pending.length,
      );
    } catch (error) {
      debugPrint('[OfficialAnkiLessonRedoFlush] fail-closed: $error');
      return OfficialAnkiLessonRedoFlushResult(
        requested: answers.length,
        failed: true,
      );
    }
  }

  Future<Set<int>> _ratedTodayIds(
    OfficialAnkiEngine engine,
    Set<int> cardIds,
  ) async {
    final found = <int>{};
    String? pageToken;
    while (true) {
      final page = await engine.searchCardsPage(
        search: 'rated:1',
        pageSize: 500,
        pageToken: pageToken,
      );
      for (final id in page.cardIds) {
        if (cardIds.contains(id)) found.add(id);
      }
      if (found.length >= cardIds.length) break;
      if (page.nextPageToken == null ||
          page.nextPageToken!.isEmpty ||
          page.cardIds.isEmpty) {
        break;
      }
      pageToken = page.nextPageToken;
    }
    return found;
  }
}
