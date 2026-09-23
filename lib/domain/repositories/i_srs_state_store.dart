// Project imports:
import 'package:turna/domain/course/language_codes.dart';
import 'package:turna/domain/course/srs_word.dart';

/// Persistence API for `srs_states` — the durable store for [SrsWord]
/// scheduling state (migrated from a prefs JSON blob in schema v7).
///
/// Concrete: `SrsStateDao` (lib/data). `queue` scopes rows to an owning
/// provider (`'srs'` words/expressions vs `'grammar'`); providers hold
/// state in memory for synchronous reads and write through this store.
abstract interface class ISrsStateStore {
  /// Load every [SrsWord] in [queue] into an id-keyed map. Used at startup
  /// to hydrate the in-memory cache.
  Future<Map<String, SrsWord>> loadQueue(
    String queue, {
    String? languageCode,
  });

  /// Insert or update a single [SrsWord] in [queue].
  Future<void> upsert(
    String queue,
    SrsWord word, {
    String languageCode = LanguageCodes.turkish,
  });

  /// Insert or update many [SrsWord]s in one transaction (bulk import /
  /// migration backfill).
  Future<void> upsertBatch(
    String queue,
    Iterable<SrsWord> words, {
    String languageCode = LanguageCodes.turkish,
  });

  /// Delete many state rows in one statement (import rollback). Pass [queue]
  /// so a same-wordId row in another queue's pool is never dropped; pass
  /// [languageCode] to spare other languages' copies.
  Future<void> deleteMany(
    Iterable<String> wordIds, {
    String? queue,
    String? languageCode,
  });

  /// Delete every row whose `wordId` starts with [prefix] (e.g. uninstalling
  /// an imported Anki deck removes its `anki-<importId>-` entries). Pass
  /// [queue] to keep the sweep inside the calling provider's pool. Wildcards
  /// inside [prefix] are escaped, so the match is strictly literal.
  Future<void> deleteByPrefix(String prefix, {String? queue});

  /// Delete every row in [queue] (content-update reset). Pass [languageCode]
  /// to spare the other languages' rows; null clears every language.
  Future<void> clearQueue(String queue, {String? languageCode});

  /// Count every active schedule that can be moved by the Fun Lab time
  /// machine. Both currently-due and future rows are included.
  Future<int> countPostponable();

  /// Move all active schedules by [duration] atomically, without touching
  /// any other FSRS field or the review history table.
  Future<int> postponeActiveBy(Duration duration);

  /// Most recent [limit] reviewed rows in [queue] (newest first), filtered
  /// to those that have been reviewed at least once. Optional [since]
  /// narrows to rows reviewed on/after the given instant; optional
  /// [languageCode] keeps other languages out of the tutor context.
  Future<List<SrsWord>> recentReviews({
    String queue = 'srs',
    int limit = 20,
    DateTime? since,
    String? languageCode,
  });
}
