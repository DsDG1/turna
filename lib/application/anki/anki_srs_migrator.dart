import 'package:turna/application/anki/anki_deck_manager.dart';
import 'package:turna/application/anki/anki_models.dart';
import 'package:turna/application/anki_official/migration/official_anki_engine_kind.dart';
import 'package:turna/application/anki_official/migration/official_anki_write_owner.dart';
import 'package:turna/application/srs_provider.dart';
import 'package:turna/core/logger.dart';
import 'package:turna/data/review_history_dao.dart';
import 'package:turna/domain/course/srs_word.dart';

/// Migrates Anki card scheduling state into Turna's [SrsWord] format
/// and registers them into [SrsProvider].
///
/// Anki field → SrsWord mapping:
/// - cards.due (queue=2, review): day offset from collection creation time
/// - cards.due (queue=1, learning): Unix seconds for modern exports
///   (`due >= 100000000`), otherwise minutes relative to import time for
///   legacy Anki 2.1 exports
/// - cards.due (queue=0, new): position in new queue → staggered across days
///   by [newCardsPerDay] so a 5k-card import is not all due on day one
/// - cards.ivl → intervalDays
/// - cards.factor / 1000.0 → ease (clamped >= 1.3)
/// - cards.reps → reps
/// - cards.lapses → lapses
/// - cards.queue=-1/-2 → explicit suspended/buried state (not a leech)
class AnkiSrsMigrator {
  /// Migrate all Anki cards' scheduling state into the SRS provider.
  ///
  /// [cards] is the list of Anki cards from the parsed collection.
  /// [importId] is used to generate stable word ids.
  /// [srsProvider] is the target SRS queue.
  /// [revlog] is the parsed review log (may be empty).
  /// [reviewHistoryDao] is the optional sink for backfilled review events.
  /// [newCardsPerDay] controls how new-queue positions map to calendar days
  /// (default matches [AnkiDeckManager.defaultDailyNewLimit]).
  /// [importScheduling] is explicit: false creates fresh cards and ignores
  /// source scheduling/revlog; true imports Anki's learning progress.
  Future<void> migrate({
    required List<AnkiCardData> cards,
    required String importId,
    required SrsProvider srsProvider,
    List<AnkiRevlogEntry> revlog = const [],
    ReviewHistoryDao? reviewHistoryDao,
    int newCardsPerDay = AnkiDeckManager.defaultDailyNewLimit,
    int collectionCreationTime = 0,
    bool importScheduling = true,
    AnkiEngineKind? sourceEngine,
    AnkiWriteGuard writeGuard = const AnkiWriteGuard(),
  }) async {
    writeGuard.assertAllowed(
      sourceEngine: sourceEngine ?? AnkiEngineKind.legacy,
      owner: AnkiWriteOwner.turnaSrs,
      operation: 'migrate',
    );
    final now = DateTime.now();
    final srsWords = <String, SrsWord>{};
    final perDay = newCardsPerDay < 1 ? 1 : newCardsPerDay;

    for (var index = 0; index < cards.length; index++) {
      final card = cards[index];
      final wordId = 'anki-$importId-c${card.id}';

      // Skip if already registered (idempotent re-import)
      if (srsProvider.state.containsKey(wordId)) continue;

      final srsWord = importScheduling
          ? _convertCard(
              card,
              wordId,
              now,
              perDay,
              collectionCreationTime,
            )
          : _freshCard(wordId, index, now, perDay);
      srsWords[wordId] = srsWord;
    }

    if (srsWords.isNotEmpty) {
      // Batch register into SRS provider via public API
      await srsProvider.bulkImportStates(srsWords);
    }

    if (importScheduling) {
      await _migrateRevlog(
        cards: cards,
        revlog: revlog,
        importId: importId,
        reviewHistoryDao: reviewHistoryDao,
      );
    }
  }

  /// Backfill Anki's review log into `review_events` (best-effort).
  Future<void> _migrateRevlog({
    required List<AnkiCardData> cards,
    required List<AnkiRevlogEntry> revlog,
    required String importId,
    ReviewHistoryDao? reviewHistoryDao,
  }) async {
    if (reviewHistoryDao == null || revlog.isEmpty) return;

    // cid -> wordId (via the card's note id).
    final cidToWordId = <int, String>{
      for (final card in cards) card.id: 'anki-$importId-c${card.id}',
    };

    final events = <ReviewEventRecord>[];
    for (final r in revlog) {
      final wordId = cidToWordId[r.cid];
      if (wordId == null) continue;
      final ease = r.factor / 1000.0;
      final clampedEase = ease < 1.3 ? 1.3 : ease;
      events.add(ReviewEventRecord(
        cardId: wordId,
        queue: 'srs',
        reviewedAt: DateTime.fromMillisecondsSinceEpoch(r.id),
        quality: _revlogEaseToQuality(r.ease),
        prevIntervalDays: _toDays(r.lastIvl),
        nextIntervalDays: _toDays(r.ivl),
        prevEase: clampedEase,
        nextEase: clampedEase,
        reps: 0,
        lapses: 0,
        sourceKey: 'anki-$importId-r${r.id}',
        type: SrsItemType.word,
      ));
    }

    if (events.isEmpty) return;
    try {
      await reviewHistoryDao.insertBatch(events);
    } catch (e, st) {
      logger.w('AnkiSrsMigrator revlog insert failed: $e', stackTrace: st);
    }
  }

  /// Map Anki's revlog button (1=again..4=easy) to the same four qualities
  /// used by imported-card reviews in this app.
  static int _revlogEaseToQuality(int ease) {
    switch (ease) {
      case 1:
        return 1;
      case 2:
        return 3;
      case 3:
        return 4;
      case 4:
        return 5;
      default:
        return 1;
    }
  }

  /// Convert an Anki revlog interval to whole days. Positive values are days;
  /// negative values (learning steps in seconds) and zero collapse to 0 (which
  /// buckets to the 1-day bucket in the memory-curve model).
  static int _toDays(int ivl) => ivl > 0 ? ivl : 0;

  SrsWord _freshCard(
    String wordId,
    int position,
    DateTime now,
    int newCardsPerDay,
  ) {
    final dayOffset = position ~/ newCardsPerDay;
    return SrsWord(
      wordId: wordId,
      dueAt: DateTime(now.year, now.month, now.day).add(
        Duration(days: dayOffset),
      ),
      intervalDays: 0,
      ease: 2.5,
      reps: 0,
      lapses: 0,
      isLeech: false,
      isSuspended: false,
      isBuried: false,
    );
  }

  /// Convert a single Anki card's scheduling state to [SrsWord].
  SrsWord _convertCard(
    AnkiCardData card,
    String wordId,
    DateTime now,
    int newCardsPerDay,
    int collectionCreationTime,
  ) {
    // Ease factor: Anki stores as int × 1000, clamp to minimum 1.3
    var ease = card.factor / 1000.0;
    if (ease < 1.3) ease = 1.3;

    final isSuspended = card.queue == -1;
    final isBuried = card.queue == -2;

    // New cards with no review history: fresh ease/reps, due staggered by
    // Anki new-queue position so multi-thousand decks do not dump every card
    // into today's due set (hub scan + review still respect daily caps).
    if (card.queue == 0 && card.reps == 0) {
      return SrsWord(
        wordId: wordId,
        dueAt: _newCardDueAt(card.due, now, newCardsPerDay),
        intervalDays: 0,
        ease: 2.5,
        reps: 0,
        lapses: 0,
        isLeech: false,
        isSuspended: false,
        isBuried: false,
      );
    }

    return SrsWord(
      wordId: wordId,
      dueAt: _computeDueAt(card, now, collectionCreationTime),
      intervalDays: card.ivl > 0 ? card.ivl : 0,
      ease: ease,
      reps: card.reps,
      lapses: card.lapses,
      isLeech: false,
      isSuspended: isSuspended,
      isBuried: isBuried,
    );
  }

  /// Map Anki new-queue position (`cards.due` when queue=0) onto calendar days.
  ///
  /// Positions `0..newCardsPerDay-1` are due today, the next band tomorrow, etc.
  /// Negative positions collapse to 0 (immediately due).
  static DateTime _newCardDueAt(
      int position, DateTime now, int newCardsPerDay) {
    final pos = position < 0 ? 0 : position;
    final dayOffset = pos ~/ newCardsPerDay;
    if (dayOffset == 0) return now;
    // Normalize to local midnight + dayOffset so "day N" cards share one due
    // bucket and sort stably after today's new/review work.
    final today = DateTime(now.year, now.month, now.day);
    return today.add(Duration(days: dayOffset));
  }

  /// Compute the due DateTime from Anki's queue-dependent `due` field.
  ///
  /// Anki `due` semantics:
  /// - queue=0 (new): position among new cards — handled by [_newCardDueAt]
  /// - queue=1: Unix seconds (modern exports) or minutes relative to import
  ///   time (legacy Anki 2.1) — see [_learningDueAt]
  /// - queue=3: Unix seconds or day offset from collection creation
  /// - queue=2: day offset from collection creation
  /// - queue=-1/-2 (suspended/buried): hidden from due queues
  DateTime _computeDueAt(
    AnkiCardData card,
    DateTime now,
    int collectionCreationTime,
  ) {
    switch (card.queue) {
      case 0: // New card (fallback if called outside the fresh-state branch)
        return _newCardDueAt(
          card.due,
          now,
          AnkiDeckManager.defaultDailyNewLimit,
        );
      case 1: // Learning: Unix seconds in current Anki exports.
        return _learningDueAt(card.due, now, collectionCreationTime);
      case 3: // Day-learning: day number from collection creation.
        if (card.due >= 100000000) {
          return DateTime.fromMillisecondsSinceEpoch(card.due * 1000);
        }
        return _reviewDueAt(card.due, now, collectionCreationTime);
      case 2: // Review (days)
        return _reviewDueAt(card.due, now, collectionCreationTime);
      default: // Suspended (-1), buried (-2)
        return now;
    }
  }

  DateTime _learningDueAt(int due, DateTime now, int collectionCreationTime) {
    if (due <= 0) return now;
    // A Unix timestamp is unmistakable. Do not interpret it as minutes or
    // seconds relative to the import time.
    if (due >= 100000000) {
      return DateTime.fromMillisecondsSinceEpoch(due * 1000);
    }
    // Legacy Anki 2.1 stored learning `due` as MINUTES relative to "now"
    // (the moment the card left the learning queue), not seconds. Treating
    // it as seconds would put a 10-minute-step card back in the user's
    // queue 10 seconds after import instead of 10 minutes later.
    return now.add(Duration(minutes: due));
  }

  DateTime _reviewDueAt(int due, DateTime now, int collectionCreationTime) {
    final base = collectionCreationTime > 0
        ? DateTime.fromMillisecondsSinceEpoch(collectionCreationTime * 1000)
        : DateTime(now.year, now.month, now.day);
    final day = DateTime(base.year, base.month, base.day);
    return day.add(Duration(days: due));
  }
}
