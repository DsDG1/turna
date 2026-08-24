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
    final dueByImport = <String, int>{};
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
        dueByImport[importId] = 0;
        continue;
      }
      final counts = await countsForDeck(target.deckId);
      final n = counts.newCount + counts.reviewCount;
      dueByImport[importId] = n;
      total += n;
    }
    OfficialAnkiHomeDue.officialImportIds = ids;
    OfficialAnkiHomeDue.officialDueByImport = dueByImport;
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
    final dueByImport = <String, int>{};
    final schedulerDueByImport = <String, Set<int>>{};
    final placementsByImport = <String, Set<int>>{};
    OfficialAnkiHomeDue.officialImportIds = ids;
    if (ids.isEmpty) {
      OfficialAnkiHomeDue.officialDueByImport = dueByImport;
      OfficialAnkiHomeDue.officialSchedulerDueCardIdsByImport =
          schedulerDueByImport;
      OfficialAnkiHomeDue.activePlacementCardIdsByImport = placementsByImport;
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
      placementsByImport[importId] = Set<int>.from(target.cardIds);
      if (!seenDecks.add(target.deckId)) {
        dueByImport[importId] = 0;
        schedulerDueByImport[importId] = const {};
        continue;
      }
      targets[importId] = target;
    }
    if (targets.isEmpty) {
      OfficialAnkiHomeDue.officialDueByImport = dueByImport;
      OfficialAnkiHomeDue.officialSchedulerDueCardIdsByImport =
          schedulerDueByImport;
      OfficialAnkiHomeDue.activePlacementCardIdsByImport = placementsByImport;
      OfficialAnkiHomeDue.officialDueUnavailable = false;
      return 0;
    }
    final queue = await getReviewQueue();
    final queueCardIds = {for (final card in queue.cards) card.cardId};
    final total = queue.newCount + queue.learningCount + queue.reviewCount;
    for (final entry in targets.entries) {
      final dueIds = queueCardIds.intersection(entry.value.cardIds);
      dueByImport[entry.key] = dueIds.length;
      schedulerDueByImport[entry.key] = dueIds;
    }
    for (final importId in ids) {
      dueByImport.putIfAbsent(importId, () => 0);
      schedulerDueByImport.putIfAbsent(importId, () => const {});
    }
    OfficialAnkiHomeDue.officialDueByImport = dueByImport;
    OfficialAnkiHomeDue.officialSchedulerDueCardIdsByImport =
        schedulerDueByImport;
    OfficialAnkiHomeDue.activePlacementCardIdsByImport = placementsByImport;
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
    final dueByImport = <String, int>{};
    OfficialAnkiHomeDue.officialImportIds = ids;
    if (ids.isEmpty) {
      OfficialAnkiHomeDue.officialDueByImport = dueByImport;
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
      if (target != null) {
        final representative = representativeFor(target.deckId);
        importsByRepresentative
            .putIfAbsent(representative, () => <String>[])
            .add(importId);
      }
      dueByImport[importId] = 0;
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
      dueByImport[owner] = node.dueCount;
      total += node.dueCount;
    }

    OfficialAnkiHomeDue.officialDueByImport = dueByImport;
    OfficialAnkiHomeDue.officialDueUnavailable = false;
    return total;
  }

  /// Populate exact scheduler-due card ids for each Official import.
  ///
  /// Must run after collection open. Writes
  /// [OfficialAnkiHomeDue.officialSchedulerDueCardIdsByImport] and
  /// [OfficialAnkiHomeDue.activePlacementCardIdsByImport] so home/deck due
  /// uses card-id intersection instead of count approximation.
  Future<void> refreshFormalDueCardIds({
    required OfficialAnkiMigrationDao dao,
    required OfficialAnkiSourceDao sources,
    required Future<void> Function(int deckId) setCurrentDeck,
    required Future<OfficialReviewQueue> Function({int fetchLimit})
        getReviewQueue,
    Future<Set<int>> Function({int? deckId})? getSuspendedCardIds,
    Future<Set<int>> Function({int? deckId})? getBuriedCardIds,
    Future<Set<int>> Function({int? deckId})? getRetiredCardIds,
    String profileId = defaultProfileId,
    bool? cutoverEnabled,
    int fetchLimit = 500,
  }) async {
    final ids = officialImportIds(
      dao: dao,
      profileId: profileId,
      cutoverEnabled: cutoverEnabled,
    );
    OfficialAnkiHomeDue.officialImportIds = {
      ...OfficialAnkiHomeDue.officialImportIds,
      ...ids,
    };
    final dueByImport = <String, Set<int>>{};
    final placementsByImport = <String, Set<int>>{};
    final countsByImport = <String, int>{};
    final suspendedByImport = <String, Set<int>>{};
    final buriedByImport = <String, Set<int>>{};
    final retiredByImport = <String, Set<int>>{};
    final queueIdsByDeck = <int, Set<int>>{};

    Set<int>? allSuspended;
    Set<int>? allBuried;
    Set<int>? allRetired;

    if (getSuspendedCardIds != null) {
      allSuspended = await getSuspendedCardIds();
    }
    if (getBuriedCardIds != null) {
      allBuried = await getBuriedCardIds();
    }
    if (getRetiredCardIds != null) {
      allRetired = await getRetiredCardIds();
    }

    for (final importId in ids) {
      final target = reviewTargetForImport(
        dao: dao,
        sources: sources,
        importId: importId,
        profileId: profileId,
        cutoverEnabled: cutoverEnabled,
      );
      if (target == null) {
        dueByImport[importId] = const {};
        placementsByImport[importId] = const {};
        countsByImport[importId] = 0;
        suspendedByImport[importId] = const {};
        buriedByImport[importId] = const {};
        retiredByImport[importId] = const {};
        continue;
      }
      placementsByImport[importId] = Set<int>.from(target.cardIds);
      if (allSuspended != null) {
        suspendedByImport[importId] = allSuspended.intersection(target.cardIds);
      }
      if (allBuried != null) {
        buriedByImport[importId] = allBuried.intersection(target.cardIds);
      }
      if (allRetired != null) {
        retiredByImport[importId] = allRetired.intersection(target.cardIds);
      }
      var queueIds = queueIdsByDeck[target.deckId];
      if (queueIds == null) {
        await setCurrentDeck(target.deckId);
        final queue = await getReviewQueue(fetchLimit: fetchLimit);
        queueIds = {for (final card in queue.cards) card.cardId};
        queueIdsByDeck[target.deckId] = queueIds;
      }
      final dueIds = queueIds.intersection(target.cardIds);
      dueByImport[importId] = dueIds;
      countsByImport[importId] = dueIds.length;
    }

    OfficialAnkiHomeDue.officialSchedulerDueCardIdsByImport = dueByImport;
    OfficialAnkiHomeDue.activePlacementCardIdsByImport = placementsByImport;
    if (allSuspended != null) {
      OfficialAnkiHomeDue.suspendedCardIdsByImport = {
        ...OfficialAnkiHomeDue.suspendedCardIdsByImport,
        ...suspendedByImport,
      };
    }
    if (allBuried != null) {
      OfficialAnkiHomeDue.buriedCardIdsByImport = {
        ...OfficialAnkiHomeDue.buriedCardIdsByImport,
        ...buriedByImport,
      };
    }
    if (allRetired != null) {
      OfficialAnkiHomeDue.retiredCardIdsByImport = {
        ...OfficialAnkiHomeDue.retiredCardIdsByImport,
        ...retiredByImport,
      };
    }
    OfficialAnkiHomeDue.officialDueByImport = countsByImport;
    // officialDue is DERIVED (introduced ∩ placement ∩ …); it must never be
    // set from raw counts (plan 34 D6).
    OfficialAnkiHomeDue.officialDueUnavailable = false;
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
