// Project imports:
import 'package:turna/domain/course/mistake_entry.dart';

/// SQLite-backed mistake log persistence, scoped by language code.
///
/// Concrete: `MistakeRepository` in `lib/data`.
abstract class IMistakeRepository {
  /// Cap on retained entries (FIFO eviction beyond this).
  static const int defaultMaxEntries = 200;

  /// All entries for [languageCode], newest first.
  Future<List<MistakeEntry>> load(String languageCode);

  /// Per-day mistake counts map (`yyyy-MM-dd` → count) for [languageCode].
  Future<Map<String, int>> loadDailyCounts(String languageCode);

  /// Total mastered mistakes for [languageCode].
  Future<int> loadMasteredTotal(String languageCode);

  /// Replace the whole entry list + aggregates atomically.
  Future<void> replaceAll({
    required String languageCode,
    required List<MistakeEntry> entries,
    required Map<String, int> dailyCounts,
    required int masteredTotal,
    int maxEntries = defaultMaxEntries,
  });

  /// Insert one entry and update aggregates in one transaction.
  Future<void> insertEntry({
    required String languageCode,
    required MistakeEntry entry,
    required Map<String, int> dailyCounts,
    required int masteredTotal,
    bool evictOldest = false,
  });

  /// Update one entry; optionally persist refreshed aggregates.
  Future<void> updateEntry({
    required String languageCode,
    required MistakeEntry entry,
    Map<String, int>? dailyCounts,
    int? masteredTotal,
  });

  /// Delete entries by id; optionally persist refreshed aggregates.
  Future<void> deleteEntriesByIds({
    required String languageCode,
    required Iterable<String> ids,
    Map<String, int>? dailyCounts,
    int? masteredTotal,
  });

  /// Remove every mistake row + aggregate for [languageCode] (language
  /// uninstall path).
  Future<void> deleteLanguage(String languageCode);

  /// One-time migration of the legacy prefs JSON blobs. Returns false when
  /// rows already exist (nothing to migrate) or the JSON was unusable.
  Future<bool> migrateFromPrefsJson({
    required String languageCode,
    required String logJson,
    required String dailyCountsJson,
    required int masteredTotal,
  });
}
