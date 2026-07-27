// Project imports:
import 'package:varnamala/application/anki/anki_models.dart';
import 'package:varnamala/application/srs_provider.dart';
import 'package:varnamala/domain/course/srs_word.dart';

/// Migrates Anki card scheduling state into Varnamala's [SrsWord] format
/// and registers them into [SrsProvider].
///
/// Anki field → SrsWord mapping:
/// - cards.due (queue=2, review): dueAt = now + Duration(days: due)
/// - cards.due (queue=1, learning): dueAt = now + Duration(minutes: due)
/// - cards.due (queue=0, new): dueAt = now (immediately due)
/// - cards.ivl → intervalDays
/// - cards.factor / 1000.0 → ease (clamped >= 1.3)
/// - cards.reps → reps
/// - cards.lapses → lapses
/// - cards.queue ∈ {-2, -1} → isLeech = true
class AnkiSrsMigrator {
  /// Migrate all Anki cards' scheduling state into the SRS provider.
  ///
  /// [cards] is the list of Anki cards from the parsed collection.
  /// [importId] is used to generate stable word ids.
  /// [srsProvider] is the target SRS queue.
  Future<void> migrate({
    required List<AnkiCardData> cards,
    required String importId,
    required SrsProvider srsProvider,
  }) async {
    final now = DateTime.now();
    final srsWords = <String, SrsWord>{};

    for (final card in cards) {
      final wordId = 'anki-$importId-n${card.nid}';

      // Skip if already registered (idempotent re-import)
      if (srsProvider.state.containsKey(wordId)) continue;

      final srsWord = _convertCard(card, wordId, now);
      srsWords[wordId] = srsWord;
    }

    if (srsWords.isEmpty) return;

    // Batch register into SRS provider via public API
    await srsProvider.bulkImportStates(srsWords);
  }

  /// Convert a single Anki card's scheduling state to [SrsWord].
  SrsWord _convertCard(AnkiCardData card, String wordId, DateTime now) {
    // Determine due date based on queue semantics
    final dueAt = _computeDueAt(card, now);

    // Ease factor: Anki stores as int × 1000, clamp to minimum 1.3
    var ease = card.factor / 1000.0;
    if (ease < 1.3) ease = 1.3;

    // Suspended (-1) or buried (-2) cards are treated as leeches
    final isLeech = card.queue == -1 || card.queue == -2;

    // New cards with no review history get fresh state
    if (card.queue == 0 && card.reps == 0) {
      return SrsWord(
        wordId: wordId,
        dueAt: now,
        intervalDays: 0,
        ease: 2.5,
        reps: 0,
        lapses: 0,
        isLeech: false,
      );
    }

    return SrsWord(
      wordId: wordId,
      dueAt: dueAt,
      intervalDays: card.ivl > 0 ? card.ivl : 1,
      ease: ease,
      reps: card.reps,
      lapses: card.lapses,
      isLeech: isLeech,
    );
  }

  /// Compute the due DateTime from Anki's queue-dependent `due` field.
  ///
  /// Anki `due` semantics:
  /// - queue=0 (new): position among new cards (not a date) → due now
  /// - queue=1 or 3 (learning/day-learn): minutes offset → now + minutes
  /// - queue=2 (review): day offset from collection creation → now + days
  /// - queue=-1/-2 (suspended/buried): original due preserved → due now
  DateTime _computeDueAt(AnkiCardData card, DateTime now) {
    switch (card.queue) {
      case 0: // New card
        return now;
      case 1: // Learning (minutes)
      case 3: // Day-learning relearning (minutes)
        // Anki learning due is minutes since collection creation, but for
        // migration purposes we treat small values as "due soon".
        // If due <= 0, it's already past due.
        if (card.due <= 0) return now;
        // Cap at reasonable learning window (avoid huge offsets)
        final minutes = card.due > 1440 ? 0 : card.due;
        return now.add(Duration(minutes: minutes));
      case 2: // Review (days)
        // due is days since collection creation; negative means overdue
        if (card.due <= 0) return now;
        return now.add(Duration(days: card.due));
      default: // Suspended (-1), buried (-2)
        return now;
    }
  }
}
