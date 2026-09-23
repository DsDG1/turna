// Project imports:
import 'package:turna/domain/anki/anki_import_record.dart';

/// Persistence API for the `anki_imports` table — per-import metadata for
/// Anki package imports.
///
/// Concrete: `AnkiImportDao` in `lib/data`.
abstract class IAnkiImportStore {
  /// Every import row, newest first.
  Future<List<AnkiImportRecord>> getAll();

  /// One import row by id, or null.
  Future<AnkiImportRecord?> getById(String importId);

  /// First import row whose source-file hash matches, or null.
  Future<AnkiImportRecord?> findByHash(String sourceHash);

  /// Remove one import row.
  Future<void> delete(String importId);

  /// Update the daily new/review limits for one import.
  Future<void> setDailyLimits(
    String importId, {
    int? newLimit,
    int? reviewLimit,
  });

  /// Per-import daily new-card limit (null = unset).
  Future<int?> dailyNewLimitFor(String importId);

  /// Per-import daily review limit (null = unset).
  Future<int?> dailyReviewLimitFor(String importId);
}
