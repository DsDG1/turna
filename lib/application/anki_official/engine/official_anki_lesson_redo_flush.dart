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
  /// is success (the engine reports the skip count).
  bool get userShouldBeNotified {
    if (requested <= 0) return false;
    if (failed) return true;
    final remaining = requested - skippedRatedToday;
    return remaining > 0 && answered < remaining;
  }
}

/// Flushes one Official rating per card after a completed Anki lesson is
/// replayed (ADR 0037 提前复习). Fail-closed: a missing engine/capability
/// logs and writes nothing to Turna SRS.
///
/// P2: the idempotency lives in the `answerAheadCards` op — cards already
/// rated today are skipped inside the engine and reported back as
/// [OfficialAnkiLessonRedoFlushResult.skippedRatedToday]. This class no
/// longer pre-scans the collection with a paginated `rated:1` search.
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
      final outcome = await resolved.answerAheadCards(answers);
      return OfficialAnkiLessonRedoFlushResult(
        requested: answers.length,
        answered: outcome.answered,
        skippedRatedToday: outcome.skippedRatedToday,
        failed: outcome.answered + outcome.skippedRatedToday <
            answers.length,
      );
    } catch (error) {
      debugPrint('[OfficialAnkiLessonRedoFlush] fail-closed: $error');
      return OfficialAnkiLessonRedoFlushResult(
        requested: answers.length,
        failed: true,
      );
    }
  }
}
