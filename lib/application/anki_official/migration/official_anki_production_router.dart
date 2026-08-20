import 'dart:io';

import 'package:turna/application/anki_official/contract/official_anki_dto.dart';
import 'package:turna/application/anki_official/engine/official_anki_home_due.dart';
import 'package:turna/application/anki_official/migration/official_anki_engine_kind.dart';
import 'package:turna/application/anki_official/migration/official_anki_migration_dao.dart';
import 'package:turna/application/anki_official/official_anki_feature_flags.dart';
import 'package:turna/application/anki_official/official_anki_ids.dart';
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
    String? sourceHash,
    String? platform,
  }) {
    if (importId.isEmpty) return AnkiEngineKind.legacy;
    final cutover = cutoverEnabled ?? LegacyAnkiMigrationFlags.cutoverEnabled;
    if (!cutover) return AnkiEngineKind.legacy;
    if (dao == null) {
      return const AnkiSourceRouteResolver().resolve(
        sourceKey: importId,
        cutoverEnabled: cutover,
        platform: platform,
      );
    }
    final row = dao.findByLegacyImport(
      profileId: profileId,
      legacyImportId: importId,
    );
    final hash = (sourceHash ?? row?.sourceHash)?.trim();
    final byHash = hash == null || hash.isEmpty || sources == null
        ? null
        : sources.findByHash(profileId, hash);
    final byId = sources?.findById(importId);
    final hasOfficial =
        (row?.officialSourceId != null && row!.officialSourceId!.isNotEmpty) ||
            byHash != null ||
            byId != null;
    return const AnkiSourceRouteResolver().resolve(
      sourceKey: importId,
      recordedKind: parseRecordedKind(row?.recordedKind),
      officialCatalogHasSource: hasOfficial,
      cutoverEnabled: cutover,
      platform: platform,
    );
  }

  OfficialAnkiRoutedSource? reviewTargetForImport({
    required OfficialAnkiMigrationDao dao,
    required OfficialAnkiSourceDao sources,
    String profileId = defaultProfileId,
    bool? cutoverEnabled,
    String? sourceHash,
    required String importId,
    String? platform,
  }) {
    if (engineForImport(
          importId: importId,
          dao: dao,
          sources: sources,
          profileId: profileId,
          cutoverEnabled: cutoverEnabled,
          sourceHash: sourceHash,
          platform: platform,
        ) !=
        AnkiEngineKind.official) {
      return null;
    }
    final row = dao.findByLegacyImport(
      profileId: profileId,
      legacyImportId: importId,
    );
    var sourceId = row?.officialSourceId;
    if (sourceId == null || sourceId.isEmpty) {
      if (sources.findById(importId) != null) {
        sourceId = importId;
      } else {
        final hash = (sourceHash ?? row?.sourceHash)?.trim();
        if (hash != null && hash.isNotEmpty) {
          sourceId = sources.findByHash(profileId, hash)?.sourceId;
        }
      }
    }
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

  /// Link a course import to an official catalog source. Skips explicit
  /// `recordedKind=legacy` rollback rows.
  void adoptExistingIfCatalogMatches({
    required OfficialAnkiMigrationDao dao,
    required OfficialAnkiSourceDao sources,
    required String importId,
    required String sourceHash,
    String profileId = defaultProfileId,
    int? nowMillis,
  }) {
    if (importId.isEmpty || sourceHash.isEmpty) return;
    final src = sources.findByHash(profileId, sourceHash);
    if (src == null) return;
    final now = nowMillis ?? DateTime.now().millisecondsSinceEpoch;
    final row = dao.findByLegacyImport(
      profileId: profileId,
      legacyImportId: importId,
    );
    if (parseRecordedKind(row?.recordedKind) == AnkiEngineKind.legacy) {
      return;
    }
    if (row == null) {
      dao.insertObservingOfficial(
        migrationId: 'mig-$importId',
        profileId: profileId,
        legacyImportId: importId,
        officialSourceId: src.sourceId,
        sourceHash: sourceHash,
        nowMillis: now,
        cardCount: sources.cardCount(src.sourceId),
      );
      return;
    }
    if (row.recordedKind != 'official' ||
        row.officialSourceId != src.sourceId) {
      dao.setOfficialSourceAndRecordedKind(
        migrationId: row.migrationId,
        officialSourceId: src.sourceId,
        recordedKind: 'official',
        nowMillis: now,
      );
    }
  }

  Set<String> officialImportIds({
    required OfficialAnkiMigrationDao dao,
    String profileId = defaultProfileId,
    bool? cutoverEnabled,
  }) {
    final cutover = cutoverEnabled ?? LegacyAnkiMigrationFlags.cutoverEnabled;
    if (!cutover) return const {};
    final out = <String>{};
    for (final row in dao.listMigrations(profileId: profileId)) {
      final engine = const AnkiSourceRouteResolver().resolve(
        sourceKey: row.legacyImportId,
        recordedKind: parseRecordedKind(row.recordedKind),
        officialCatalogHasSource:
            row.officialSourceId != null && row.officialSourceId!.isNotEmpty,
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
    if (targets.length == 1) {
      OfficialAnkiHomeDue.officialDueByImport[targets.keys.first] = total;
    } else {
      for (final importId in targets.keys) {
        OfficialAnkiHomeDue.officialDueByImport[importId] = 0;
      }
    }
    for (final importId in ids) {
      OfficialAnkiHomeDue.officialDueByImport.putIfAbsent(importId, () => 0);
    }
    OfficialAnkiHomeDue.officialDue = total;
    OfficialAnkiHomeDue.officialDueUnavailable = false;
    return total;
  }

  /// Refresh due counts from one authoritative official deck-tree snapshot.
  /// Counts are assigned once per effective deck; a selected parent deck owns
  /// any selected descendants because Anki parent counts already include them.
  Future<int> refreshHomeDueFromDeckTree({
    required OfficialAnkiMigrationDao dao,
    required OfficialAnkiSourceDao sources,
    required Future<List<OfficialAnkiDeckNode>> Function() getDeckTree,
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
    for (final importId in ids) {
      final target = reviewTargetForImport(
        dao: dao,
        sources: sources,
        importId: importId,
        profileId: profileId,
        cutoverEnabled: cutoverEnabled,
      );
      if (target != null) targets[importId] = target;
    }

    final nodes = await getDeckTree();
    final nodeById = <int, OfficialAnkiDeckNode>{
      for (final node in nodes) node.deckId: node,
    };
    final ancestorsById = <int, List<int>>{};
    final stack = <OfficialAnkiDeckNode>[];
    for (final node in nodes) {
      while (stack.isNotEmpty && stack.last.level >= node.level) {
        stack.removeLast();
      }
      ancestorsById[node.deckId] = [for (final parent in stack) parent.deckId];
      stack.add(node);
    }

    final selectedDeckIds =
        targets.values.map((target) => target.deckId).toSet();
    int representativeFor(int deckId) {
      final ancestors = ancestorsById[deckId] ?? const <int>[];
      for (final ancestorId in ancestors) {
        if (selectedDeckIds.contains(ancestorId)) return ancestorId;
      }
      return deckId;
    }

    final importsByRepresentative = <int, List<String>>{};
    for (final importId in ids) {
      final target = targets[importId];
      if (target == null) {
        OfficialAnkiHomeDue.officialDueByImport[importId] = 0;
        continue;
      }
      final representative = representativeFor(target.deckId);
      importsByRepresentative
          .putIfAbsent(representative, () => <String>[])
          .add(importId);
      OfficialAnkiHomeDue.officialDueByImport[importId] = 0;
    }

    var total = 0;
    for (final entry in importsByRepresentative.entries) {
      final representative = entry.key;
      final node = nodeById[representative];
      if (node == null) continue;
      final importIds = entry.value..sort();
      final owner = importIds.firstWhere(
        (importId) => targets[importId]?.deckId == representative,
        orElse: () => importIds.first,
      );
      OfficialAnkiHomeDue.officialDueByImport[owner] = node.dueCount;
      total += node.dueCount;
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
  return LegacyAnkiIdentifiers.importIdFromWordId(wordId);
}
