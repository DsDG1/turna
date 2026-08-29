import 'dart:io';

import 'package:turna/application/anki_official/contract/official_anki_contract.dart';
import 'package:turna/application/anki_official/contract/official_anki_dto.dart';
import 'package:turna/application/anki_official/contract/official_anki_errors.dart';
import 'package:turna/application/anki_official/engine/official_formal_due_snapshot_builder.dart';
import 'package:turna/application/anki_official/migration/official_anki_engine_kind.dart';
import 'package:turna/application/anki_official/migration/official_anki_migration_dao.dart';
import 'package:turna/application/anki_official/official_anki_feature_flags.dart';
import 'package:turna/application/anki_official/official_anki_paths.dart';
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

  /// Collects the per-source six formal-due sets (maintainability plan
  /// §7.3). PURE: returns data — the caller (OfficialAnkiHomeDueSync)
  /// builds one update and commits one atomic snapshot. Must run after the
  /// collection is open.
  Future<OfficialFormalDueCollectionData> collectFormalDueCardIds({
    required OfficialAnkiMigrationDao dao,
    required OfficialAnkiSourceDao sources,
    required Future<void> Function(int deckId) setCurrentDeck,
    Future<OfficialReviewQueue> Function({int fetchLimit})? getReviewQueue,
    Future<Set<int>> Function({required int deckId})? searchSchedulerDueCardIds,

    /// Pre-eligibility scheduler numbers for [rawDueByImport]: the same
    /// due/learn/new search WITHOUT the suspended/buried negations, so the
    /// "unintroduced new" hint keeps counting the suspended backlog that
    /// [searchSchedulerDueCardIds] must exclude. Queue-derived collection
    /// (no search callbacks) ignores this — the queue is already
    /// suspension-free.
    Future<Set<int>> Function({required int deckId})? searchUnfilteredDueCardIds,
    Future<Set<int>> Function({int? deckId})? getSuspendedCardIds,
    Future<Set<int>> Function({int? deckId})? getBuriedCardIds,
    Future<Set<int>> Function({int? deckId})? getRetiredCardIds,
    String profileId = defaultProfileId,
    bool? cutoverEnabled,
    int fetchLimit = OfficialAnkiOperation.maxReviewQueueFetchLimit,
  }) async {
    assert(
      searchSchedulerDueCardIds != null || getReviewQueue != null,
      'collectFormalDueCardIds needs searchSchedulerDueCardIds or getReviewQueue',
    );
    final ids = officialImportIds(
      dao: dao,
      profileId: profileId,
      cutoverEnabled: cutoverEnabled,
    );
    final inputs = <OfficialFormalDueSourceInput>[];
    final rawDueByImport = <String, int>{};
    final queueIdsByDeck = <int, Set<int>>{};
    final unfilteredIdsByDeck = <int, Set<int>>{};

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
        inputs.add(
          OfficialFormalDueSourceInput(
            importId: importId,
            schedulerDueCardIds: const {},
            schedulerDueSynced: true,
          ),
        );
        rawDueByImport[importId] = 0;
        continue;
      }
      var queueIds = queueIdsByDeck[target.deckId];
      if (queueIds == null) {
        if (searchSchedulerDueCardIds != null) {
          queueIds = await searchSchedulerDueCardIds(deckId: target.deckId);
        } else {
          await setCurrentDeck(target.deckId);
          final queue = await _queueOrEmpty(
            getReviewQueue!,
            fetchLimit: fetchLimit,
          );
          queueIds = {for (final card in queue.cards) card.cardId};
        }
        queueIdsByDeck[target.deckId] = queueIds;
      }
      final dueIds = queueIds.intersection(target.cardIds);
      var rawIds = dueIds;
      if (searchUnfilteredDueCardIds != null) {
        var unfiltered = unfilteredIdsByDeck[target.deckId];
        if (unfiltered == null) {
          unfiltered = await searchUnfilteredDueCardIds(deckId: target.deckId);
          unfilteredIdsByDeck[target.deckId] = unfiltered;
        }
        rawIds = unfiltered.intersection(target.cardIds);
      }
      inputs.add(
        OfficialFormalDueSourceInput(
          importId: importId,
          schedulerDueCardIds: dueIds,
          schedulerDueSynced: true,
          activePlacementCardIds: Set<int>.from(target.cardIds),
          suspendedCardIds: allSuspended?.intersection(target.cardIds) ??
              const <int>{},
          buriedCardIds:
              allBuried?.intersection(target.cardIds) ?? const <int>{},
          retiredCardIds:
              allRetired?.intersection(target.cardIds) ?? const <int>{},
        ),
      );
      rawDueByImport[importId] = rawIds.length;
    }

    return OfficialFormalDueCollectionData(
      inputs: inputs,
      rawDueByImport: rawDueByImport,
    );
  }

  static Future<OfficialReviewQueue> _queueOrEmpty(
    Future<OfficialReviewQueue> Function({int fetchLimit}) getReviewQueue, {
    required int fetchLimit,
  }) async {
    try {
      return await getReviewQueue(
        fetchLimit: OfficialAnkiOperation.clampReviewQueueFetchLimit(fetchLimit),
      );
    } on OfficialAnkiException catch (error) {
      if (error.code == OfficialAnkiErrorCode.queueEmpty) {
        return const OfficialReviewQueue(
          sessionId: 'empty',
          queueEpoch: 1,
          newCount: 0,
          learningCount: 0,
          reviewCount: 0,
          cards: [],
        );
      }
      rethrow;
    }
  }

  /// Collects coarse deck-tree due counts (pre-eligibility scheduler
  /// numbers). PURE — returns data, writes nothing.
  Future<OfficialHomeDueCounts> collectHomeDueFromDeckTree({
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
    if (ids.isEmpty) {
      return OfficialHomeDueCounts(dueByImport: dueByImport, total: 0);
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

    return OfficialHomeDueCounts(dueByImport: dueByImport, total: total);
  }

  OfficialAnkiPaths pathsForDefaultProfile(Directory supportDir) {
    return OfficialAnkiPaths(
      profileId: defaultProfileId,
      profileRoot: Directory('${supportDir.path}/official_anki/default'),
    );
  }
}

/// Six-set collection result for every routed import (pure data).
class OfficialFormalDueCollectionData {
  const OfficialFormalDueCollectionData({
    required this.inputs,
    required this.rawDueByImport,
  });

  final List<OfficialFormalDueSourceInput> inputs;
  final Map<String, int> rawDueByImport;
}

/// Coarse deck-tree due counts (pure data).
class OfficialHomeDueCounts {
  const OfficialHomeDueCounts({required this.dueByImport, required this.total});

  final Map<String, int> dueByImport;
  final int total;
}

