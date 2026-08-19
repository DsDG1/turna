import 'dart:io';

import 'package:turna/application/anki/anki_review_assembler.dart';
import 'package:turna/application/anki_official/contract/official_anki_dto.dart';
import 'package:turna/application/anki_official/engine/official_anki_home_due.dart';
import 'package:turna/application/anki_official/migration/official_anki_engine_kind.dart';
import 'package:turna/application/anki_official/migration/official_anki_migration_dao.dart';
import 'package:turna/application/anki_official/official_anki_feature_flags.dart';
import 'package:turna/application/anki_official/official_anki_paths.dart';
import 'package:turna/application/anki_official/storage/official_anki_database.dart';
import 'package:turna/application/anki_official/storage/official_anki_source_dao.dart';

class OfficialAnkiRoutedSource {
  const OfficialAnkiRoutedSource({
    required this.importId,
    required this.sourceId,
    required this.deckId,
    required this.cardIds,
  });

  final String importId;
  final String sourceId;
  final int deckId;
  final Set<int> cardIds;
}

/// Production review/import ownership lookup. Read-only.
class OfficialAnkiProductionRouter {
  const OfficialAnkiProductionRouter();

  static const defaultProfileId = 'profile-default-01';

  AnkiEngineKind engineForImport({
    required String importId,
    OfficialAnkiMigrationDao? dao,
    OfficialAnkiSourceDao? sources,
    String profileId = defaultProfileId,
    bool? cutoverEnabled,
  }) {
    if (importId.isEmpty) return AnkiEngineKind.legacy;
    final cutover =
        cutoverEnabled ?? LegacyAnkiMigrationFlags.cutoverEnabled;
    if (!cutover) return AnkiEngineKind.legacy;
    if (dao == null) {
      return const AnkiSourceRouteResolver().resolve(
        sourceKey: importId,
        cutoverEnabled: cutover,
      );
    }
    final row = dao.findByLegacyImport(
      profileId: profileId,
      legacyImportId: importId,
    );
    final hasOfficial = row?.officialSourceId != null &&
        row!.officialSourceId!.isNotEmpty;
    return const AnkiSourceRouteResolver().resolve(
      sourceKey: importId,
      recordedKind: parseRecordedKind(row?.recordedKind),
      officialCatalogHasSource: hasOfficial,
      cutoverEnabled: cutover,
    );
  }

  OfficialAnkiRoutedSource? reviewTargetForImport({
    required OfficialAnkiMigrationDao dao,
    required OfficialAnkiSourceDao sources,
    required String importId,
    String profileId = defaultProfileId,
    bool? cutoverEnabled,
  }) {
    if (engineForImport(
          importId: importId,
          dao: dao,
          sources: sources,
          profileId: profileId,
          cutoverEnabled: cutoverEnabled,
        ) !=
        AnkiEngineKind.official) {
      return null;
    }
    final row = dao.findByLegacyImport(
      profileId: profileId,
      legacyImportId: importId,
    );
    final sourceId = row?.officialSourceId;
    if (sourceId == null || sourceId.isEmpty) return null;
    final cards = sources.listCards(sourceId);
    if (cards.isEmpty) return null;
    return OfficialAnkiRoutedSource(
      importId: importId,
      sourceId: sourceId,
      deckId: cards.first.deckId,
      cardIds: {for (final card in cards) card.cardId},
    );
  }

  Set<String> officialImportIds({
    required OfficialAnkiMigrationDao dao,
    String profileId = defaultProfileId,
    bool? cutoverEnabled,
  }) {
    final cutover =
        cutoverEnabled ?? LegacyAnkiMigrationFlags.cutoverEnabled;
    if (!cutover) return const {};
    final out = <String>{};
    for (final row in dao.listMigrations(profileId: profileId)) {
      final engine = const AnkiSourceRouteResolver().resolve(
        sourceKey: row.legacyImportId,
        recordedKind: parseRecordedKind(row.recordedKind),
        officialCatalogHasSource: row.officialSourceId != null &&
            row.officialSourceId!.isNotEmpty,
        cutoverEnabled: cutover,
      );
      if (engine == AnkiEngineKind.official) {
        out.add(row.legacyImportId);
      }
    }
    return out;
  }

  bool canOpenOfficialReview([OfficialAnkiFeatureFlags? flags]) {
    if (Platform.operatingSystem != 'android') return false;
    return (flags ?? OfficialAnkiFeatureFlags.current).allowsOfficialScheduler;
  }

  Future<int> refreshHomeDue({
    required OfficialAnkiMigrationDao dao,
    required OfficialAnkiSourceDao sources,
    required Future<OfficialDeckCounts> Function(int deckId) countsForDeck,
    String profileId = defaultProfileId,
    bool? cutoverEnabled,
  }) async {
    final ids = officialImportIds(
      dao: dao,
      profileId: profileId,
      cutoverEnabled: cutoverEnabled,
    );
    OfficialAnkiHomeDue.officialImportIds = ids;
    OfficialAnkiHomeDue.officialDueByImport = {};
    var total = 0;
    final seenDecks = <int>{};
    for (final importId in ids) {
      final target = reviewTargetForImport(
        dao: dao,
        sources: sources,
        importId: importId,
        profileId: profileId,
        cutoverEnabled: cutoverEnabled,
      );
      if (target == null) continue;
      if (!seenDecks.add(target.deckId)) {
        OfficialAnkiHomeDue.officialDueByImport[importId] = 0;
        continue;
      }
      final counts = await countsForDeck(target.deckId);
      final n = counts.newCount + counts.reviewCount;
      OfficialAnkiHomeDue.officialDueByImport[importId] = n;
      total += n;
    }
    OfficialAnkiHomeDue.officialDue = total;
    OfficialAnkiHomeDue.officialDueUnavailable = false;
    return total;
  }

  Future<int> refreshHomeDueFromQueue({
    required OfficialAnkiMigrationDao dao,
    required OfficialAnkiSourceDao sources,
    required Future<OfficialReviewQueue> Function() getReviewQueue,
    String profileId = defaultProfileId,
    bool? cutoverEnabled,
  }) async {
    final ids = officialImportIds(
      dao: dao,
      profileId: profileId,
      cutoverEnabled: cutoverEnabled,
    );
    OfficialAnkiHomeDue.officialImportIds = ids;
    OfficialAnkiHomeDue.officialDueByImport = {};
    if (ids.isEmpty) {
      OfficialAnkiHomeDue.officialDue = 0;
      OfficialAnkiHomeDue.officialDueUnavailable = false;
      return 0;
    }
    final targets = <String, OfficialAnkiRoutedSource>{};
    final seenDecks = <int>{};
    for (final importId in ids) {
      final target = reviewTargetForImport(
        dao: dao,
        sources: sources,
        importId: importId,
        profileId: profileId,
        cutoverEnabled: cutoverEnabled,
      );
      if (target == null) continue;
      if (!seenDecks.add(target.deckId)) {
        OfficialAnkiHomeDue.officialDueByImport[importId] = 0;
        continue;
      }
      targets[importId] = target;
    }
    if (targets.isEmpty) {
      OfficialAnkiHomeDue.officialDue = 0;
      OfficialAnkiHomeDue.officialDueUnavailable = false;
      return 0;
    }
    final queue = await getReviewQueue();
    final total = queue.newCount + queue.learningCount + queue.reviewCount;
    final perImport = total ~/ targets.length;
    var remainder = total % targets.length;
    for (final importId in targets.keys) {
      final extra = remainder > 0 ? 1 : 0;
      if (remainder > 0) remainder--;
      OfficialAnkiHomeDue.officialDueByImport[importId] = perImport + extra;
    }
    for (final importId in ids) {
      OfficialAnkiHomeDue.officialDueByImport.putIfAbsent(importId, () => 0);
    }
    OfficialAnkiHomeDue.officialDue = total;
    OfficialAnkiHomeDue.officialDueUnavailable = false;
    return total;
  }

  OfficialAnkiPaths pathsForDefaultProfile(Directory supportDir) {
    return OfficialAnkiPaths(
      profileId: defaultProfileId,
      profileRoot: Directory('${supportDir.path}/official_anki/default'),
    );
  }
}

Set<String> officialRoutedImportIdsFromCatalogFile({
  required File catalogFile,
  String profileId = OfficialAnkiProductionRouter.defaultProfileId,
  bool? cutoverEnabled,
}) {
  if (!catalogFile.existsSync()) return const {};
  final db = OfficialAnkiDatabase.file(catalogFile.path);
  try {
    return const OfficialAnkiProductionRouter().officialImportIds(
      dao: OfficialAnkiMigrationDao(db),
      profileId: profileId,
      cutoverEnabled: cutoverEnabled,
    );
  } finally {
    db.close();
  }
}

String ankiImportIdFromWordId(String wordId) {
  return AnkiReviewAssembler.importIdFromWordId(wordId);
}
