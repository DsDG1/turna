import 'package:turna/application/anki_official/migration/official_anki_dry_run_matcher.dart';
import 'package:turna/application/anki_official/migration/official_anki_migration_dao.dart';

/// Saga orchestrator for legacy Anki dry-run migration matching.
///
/// Supports cursor-based chunking, crash resumption, and ensures strict
/// idempotency across multiple runs with identical input sets.
class LegacyAnkiDryRunSaga {
  const LegacyAnkiDryRunSaga({
    this.matcher = const LegacyAnkiDryRunMatcher(),
    this.pageSize = 50,
  });

  final LegacyAnkiDryRunMatcher matcher;
  final int pageSize;

  /// Runs or resumes dry-run matching using the cursor in [OfficialAnkiMigrationDao].
  Future<LegacyAnkiDryRunResult> run({
    required OfficialAnkiMigrationDao dao,
    required String migrationId,
    required List<LegacyAnkiCardIdentity> legacyCards,
    required List<OfficialAnkiCardIdentity> officialCards,
    bool sameTrustedPackage = false,
    int? nowMillis,
  }) async {
    final now = nowMillis ?? DateTime.now().millisecondsSinceEpoch;
    final cursor = dao.getCursor(migrationId) ?? 0;

    final sortedLegacy = [...legacyCards]
      ..sort((a, b) => a.legacyCardId.compareTo(b.legacyCardId));
    final remaining =
        sortedLegacy.where((card) => card.legacyCardId > cursor).toList();

    for (var i = 0; i < remaining.length; i += pageSize) {
      final end =
          (i + pageSize < remaining.length) ? i + pageSize : remaining.length;
      final chunk = remaining.sublist(i, end);
      if (chunk.isEmpty) continue;

      final chunkResult = matcher.match(
        legacy: chunk,
        official: officialCards,
        sameTrustedPackage: sameTrustedPackage,
      );

      dao.upsertCardMapRows(
        migrationId: migrationId,
        rows: chunkResult.rows,
      );

      final nextCursor = chunk.last.legacyCardId;
      dao.setCursor(
        migrationId: migrationId,
        cursorLegacyCardId: nextCursor,
        nowMillis: now,
      );
    }

    final allStored = dao.listCardMap(migrationId);
    final finalResult = LegacyAnkiDryRunResult(rows: allStored);

    dao.setCursor(
      migrationId: migrationId,
      cursorLegacyCardId: allStored.isEmpty ? 0 : allStored.last.legacyCardId,
      nowMillis: now,
      matchedCardCount: finalResult.matchedCount,
      unresolvedCardCount: finalResult.unresolvedCount,
    );

    return finalResult;
  }
}
