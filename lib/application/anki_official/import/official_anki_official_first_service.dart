import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:turna/application/anki_official/contract/official_anki_dto.dart';
import 'package:turna/application/anki_official/contract/official_anki_errors.dart';
import 'package:turna/application/anki_official/import/anki_import_execution_plan.dart';
import 'package:turna/application/anki_official/import/official_anki_import_saga.dart';
import 'package:turna/application/anki_official/import/official_anki_source_hasher.dart';
import 'package:turna/application/anki_official/import/official_anki_staging_manager.dart';
import 'package:turna/application/anki_official/official_anki_paths.dart';
import 'package:turna/application/anki_official/import/official_anki_import_state.dart';
import 'package:turna/application/anki_official/lifecycle/official_anki_lifecycle_models.dart';
import 'package:turna/application/anki_official/official_anki_composition.dart';
import 'package:turna/application/anki_official/official_anki_feature_flags.dart';
import 'package:turna/application/anki_official/projection/official_anki_course_entry.dart';
import 'package:turna/application/anki_official/projection/official_anki_mapping_suggestion.dart';
import 'package:turna/application/anki_official/storage/official_anki_import_attempt_dao.dart';
import 'package:turna/application/anki_official/storage/official_anki_source_dao.dart';
import 'package:turna/data/course_database.dart';

/// Projection-preview snapshot after Official-first staging.
class OfficialAnkiOfficialFirstPreview {
  const OfficialAnkiOfficialFirstPreview({
    required this.sourceId,
    required this.sourceHash,
    required this.cardCount,
    required this.noteCount,
    required this.decks,
    required this.cardCountByDeck,
    this.notetypeByDeck = const {},
    required this.schemas,
    required this.suggestions,
  });

  final String sourceId;
  final String sourceHash;
  final int cardCount;
  final int noteCount;
  final List<OfficialAnkiDeckNode> decks;

  /// deckId → 牌组真实卡数（含后代累计，staging 卡账本统计）。deck tree
  /// 的 new/learn/review 是今日到期队列数，不能当卡总数展示。
  final Map<int, int> cardCountByDeck;

  /// deckId → notetype that owns the most cards in that deck.
  final Map<int, int> notetypeByDeck;
  final List<OfficialAnkiProjectionSchema> schemas;
  final Map<int, OfficialAnkiMappingSuggestion> suggestions;
}

/// Hash plus an active source that already owns that package.
class OfficialAnkiPackageLookup {
  const OfficialAnkiPackageLookup({required this.digest, this.active});

  final OfficialAnkiSourceDigest digest;
  final OfficialAnkiSourceRow? active;
}

/// Application-side Official-first import service.
class OfficialAnkiOfficialFirstService {
  const OfficialAnkiOfficialFirstService({
    this.hasher = const OfficialAnkiSourceHasher(),
  });

  final OfficialAnkiSourceHasher hasher;

  /// Hash [filePath] and return the active source with the same sha256, if any.
  Future<OfficialAnkiPackageLookup> lookupPackage(String filePath) async {
    if (!File(filePath).existsSync()) {
      throw const OfficialAnkiException(
        code: OfficialAnkiErrorCode.packageNotFound,
        messageKey: 'official_anki.package_not_found',
      );
    }
    final digest = await hasher.hashFile(filePath);
    final catalog = OfficialAnkiCompositionRoot.readOnlyCatalog;
    final livePaths = OfficialAnkiCompositionRoot.locatorPaths;
    if (catalog == null || livePaths == null) {
      return OfficialAnkiPackageLookup(digest: digest);
    }
    final row = OfficialAnkiSourceDao(catalog).findByHash(
      livePaths.profileId,
      digest.sha256,
    );
    final active =
        row != null && row.state == OfficialAnkiSourceState.active.wire
            ? row
            : null;
    return OfficialAnkiPackageLookup(digest: digest, active: active);
  }

  /// Official-first pick path: saga -> staging -> preview.
  Future<OfficialAnkiOfficialFirstPreview> importThenPreview({
    required String filePath,
    required AnkiImportExecutionPlan plan,
    required CourseDatabase course,
    OfficialAnkiFeatureFlags? flags,
    OfficialAnkiSourceDigest? digest,
    bool withMedia = true,
  }) async {
    if (!plan.isOfficialFirst) {
      throw const OfficialAnkiException(
        code: OfficialAnkiErrorCode.invalidState,
        messageKey: 'official_anki.flag_fail_closed',
        debugDetails: 'import_plan_missing',
      );
    }
    final catalog = OfficialAnkiCompositionRoot.readOnlyCatalog;
    final livePaths = OfficialAnkiCompositionRoot.locatorPaths;
    if (catalog == null || livePaths == null) {
      throw const OfficialAnkiException(
        code: OfficialAnkiErrorCode.capabilityMissing,
        messageKey: 'official_anki.catalog_missing',
        debugDetails: 'staging_import_requires_catalog',
      );
    }
    if (OfficialAnkiImportAttemptDao(catalog).hasUnfinished()) {
      throw const OfficialAnkiException(
        code: OfficialAnkiErrorCode.invalidState,
        messageKey: 'official_anki.unfinished_blocks_new',
        debugDetails: 'unfinished_import_blocks_new',
      );
    }
    OfficialAnkiCompositionRoot.stagingDiscardRequested = false;
    final official = await OfficialAnkiImportSaga(
      sources: OfficialAnkiSourceDao(catalog),
      attempts: OfficialAnkiImportAttemptDao(catalog),
      paths: livePaths,
    ).startStaging(
      packagePath: filePath,
      displayName: p.basename(filePath),
      digest: digest,
      withMedia: withMedia,
    );
    final state = official.state;
    if (!state.allowsPreview) {
      throw OfficialAnkiException(
        code: OfficialAnkiErrorCode.invalidState,
        messageKey: 'official_anki.import_not_active',
        debugDetails: 'official-first import ended in state ${state.name}',
      );
    }
    // C4：saga 已把刚算出的 sha256 放进 result，避免再查一次 source 行。
    final sourceHash = official.sourceHash ??
        readSourceHash(official.sourceId) ??
        'official-unknown';
    return preparePreview(
      official: official,
      sourceHash: sourceHash,
      course: course,
      flags: flags ?? OfficialAnkiFeatureFlags.current,
    );
  }

  String? readSourceHash(String sourceId) {
    final catalog = OfficialAnkiCompositionRoot.readOnlyCatalog ??
        OfficialAnkiCourseEntry.catalogOf?.call();
    if (catalog == null) return null;
    return OfficialAnkiSourceDao(catalog).findById(sourceId)?.sourceHash;
  }

  Future<OfficialAnkiOfficialFirstPreview> preparePreview({
    required OfficialAnkiImportResult official,
    required String sourceHash,
    required CourseDatabase course,
    OfficialAnkiFeatureFlags? flags,
  }) async {
    // A5：预览只读 staging 集合。live catalog 的 anki_source_cards 由
    // commit 期的 v2CardIndex 填充，此刻恒空（A3）；退回 live 引擎更是
    // 读错集合——staging engine 缺失时直接失败。
    final engine = OfficialAnkiCompositionRoot.stagingEngineFromSession();
    if (engine == null) {
      throw const OfficialAnkiException(
        code: OfficialAnkiErrorCode.capabilityMissing,
        messageKey: 'official_anki.importer_not_ready',
      );
    }

    // One aggregate when the engine supports it. Older engines and fakes
    // that return an empty summary still walk note ids in batches of 200.
    final notetypeIds = <int>{};
    final sourceDeckIds = <int>{};
    final directCounts = <int, int>{};
    var notetypeByDeck = <int, int>{};
    OfficialAnkiNoteDeckSummary? summary;
    try {
      summary = await engine.summarizeImportedNotes();
    } on OfficialAnkiException {
      summary = null;
    }
    if (summary != null && summary.rows.isNotEmpty) {
      notetypeIds.addAll(summary.notetypeIds);
      sourceDeckIds.addAll(summary.directCardCountByDeck.keys);
      directCounts.addAll(summary.directCardCountByDeck);
      notetypeByDeck = summary.primaryNotetypeByDeck;
    } else {
      final noteIds = official.associatedNoteIds;
      for (var offset = 0; offset < noteIds.length; offset += 200) {
        final end = offset + 200;
        final noteCards = await engine.getNoteCardsBatch(
          noteIds.sublist(offset, end > noteIds.length ? noteIds.length : end),
        );
        final cardIds = [
          for (final ids in noteCards.values) ...ids,
        ];
        if (cardIds.isEmpty) continue;
        for (final card in await engine.getCardDescriptorsBatch(cardIds)) {
          final id = card.notetypeId;
          if (id != null) notetypeIds.add(id);
          sourceDeckIds.add(card.deckId);
          directCounts[card.deckId] = (directCounts[card.deckId] ?? 0) + 1;
          if (id != null) notetypeByDeck.putIfAbsent(card.deckId, () => id);
        }
      }
    }

    final schemas = await engine.getProjectionSchemas(
      notetypeIds: notetypeIds.toList(),
      includeSamples: false,
    );
    final allDecks = await engine.listDeckTree();
    final decks = _scopeDecks(allDecks, sourceDeckIds);
    final countedCards = directCounts.values.fold<int>(0, (sum, n) => sum + n);
    return OfficialAnkiOfficialFirstPreview(
      sourceId: official.sourceId,
      sourceHash: sourceHash,
      cardCount: official.cardCount > 0
          ? official.cardCount
          : (summary?.cardCount ?? countedCards),
      noteCount: official.noteCount > 0
          ? official.noteCount
          : (summary?.noteCount ?? 0),
      decks: decks,
      cardCountByDeck: _cumulativeCardCountByDeck(allDecks, directCounts),
      notetypeByDeck: notetypeByDeck,
      schemas: schemas,
      suggestions: {
        for (final schema in schemas)
          schema.notetypeId: officialAnkiSuggestMapping(schema),
      },
    );
  }

  /// Reopen a preview_ready staging collection without importing again.
  /// Returns null when the staging directory is missing or incomplete.
  Future<OfficialAnkiOfficialFirstPreview?> resumePreview({
    required String sourceId,
    required AnkiImportExecutionPlan plan,
    required CourseDatabase course,
  }) async {
    final catalog = OfficialAnkiCompositionRoot.readOnlyCatalog;
    final livePaths = OfficialAnkiCompositionRoot.locatorPaths;
    if (catalog == null || livePaths == null) return null;
    final attempt =
        OfficialAnkiImportAttemptDao(catalog).unfinishedBySource(sourceId);
    if (attempt == null ||
        attempt.phase != OfficialAnkiAttemptPhase.previewReady) {
      return null;
    }
    final stagingPath = attempt.stagingPath;
    if (stagingPath == null || stagingPath.isEmpty) return null;
    final stagingPaths = OfficialAnkiPaths(
      profileId: livePaths.profileId,
      profileRoot: Directory(stagingPath),
    );
    if (!OfficialAnkiStagingManager(livePaths: livePaths)
        .isIntact(stagingPaths)) {
      return null;
    }
    await OfficialAnkiStagingManager(livePaths: livePaths)
        .acquire(stagingPaths);
    final source = OfficialAnkiSourceDao(catalog).findById(sourceId);
    return preparePreview(
      official: OfficialAnkiImportResult(
        sourceId: sourceId,
        attemptId: attempt.attemptId,
        state: OfficialAnkiSourceState.previewReady,
        cardCount: source == null ? 0 : 0,
        noteCount: 0,
        sourceHash: source?.sourceHash,
      ),
      sourceHash: source?.sourceHash ?? 'official-unknown',
      course: course,
      flags: OfficialAnkiFeatureFlags.current,
    );
  }
}

List<OfficialAnkiDeckNode> _scopeDecks(
  List<OfficialAnkiDeckNode> all,
  Set<int> sourceDeckIds,
) {
  if (sourceDeckIds.isEmpty) return all;
  final names = {
    for (final deck in all)
      if (sourceDeckIds.contains(deck.deckId)) deck.name,
  };
  return [
    for (final deck in all)
      if (sourceDeckIds.contains(deck.deckId) ||
          names.any(
            (name) => name == deck.name || name.startsWith('${deck.name}::'),
          ))
        deck,
  ];
}

/// deckId → 牌组（含后代）卡数：对每个有卡的牌组沿其名字路径
/// （'A::B::C'）逐级前缀累计直接计数，父牌组行即显示子树总数。
/// 不在树里的 deckId 无处展示，跳过。
Map<int, int> _cumulativeCardCountByDeck(
  List<OfficialAnkiDeckNode> tree,
  Map<int, int> directCounts,
) {
  final nameByDeckId = {for (final deck in tree) deck.deckId: deck.name};
  final deckIdByName = {for (final deck in tree) deck.name: deck.deckId};
  final counts = <int, int>{};
  for (final entry in directCounts.entries) {
    final name = nameByDeckId[entry.key];
    if (name == null) continue;
    final segments = name.split('::');
    for (var i = 1; i <= segments.length; i++) {
      final ancestorId = deckIdByName[segments.sublist(0, i).join('::')];
      if (ancestorId != null) {
        counts[ancestorId] = (counts[ancestorId] ?? 0) + entry.value;
      }
    }
  }
  return counts;
}
