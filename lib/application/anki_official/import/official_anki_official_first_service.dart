import 'package:path/path.dart' as p;
import 'package:turna/application/anki_official/contract/official_anki_dto.dart';
import 'package:turna/application/anki_official/contract/official_anki_errors.dart';
import 'package:turna/application/anki_official/import/anki_import_execution_plan.dart';
import 'package:turna/application/anki_official/import/official_anki_import_saga.dart';
import 'package:turna/application/anki_official/import/official_anki_import_state.dart';
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
  final List<OfficialAnkiProjectionSchema> schemas;
  final Map<int, OfficialAnkiMappingSuggestion> suggestions;
}

/// Application-side Official-first import service.
class OfficialAnkiOfficialFirstService {
  const OfficialAnkiOfficialFirstService();

  /// Official-first pick path: saga -> staging -> preview.
  Future<OfficialAnkiOfficialFirstPreview> importThenPreview({
    required String filePath,
    required AnkiImportExecutionPlan plan,
    required CourseDatabase course,
    OfficialAnkiFeatureFlags? flags,
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
    if (OfficialAnkiImportAttemptDao(catalog).unfinished().isNotEmpty) {
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
    );
    final state = official.state;
    if (!state.allowsPreview) {
      throw OfficialAnkiException(
        code: OfficialAnkiErrorCode.invalidState,
        messageKey: 'official_anki.import_not_active',
        debugDetails: 'official-first import ended in state ${state.name}',
      );
    }
    final sourceHash = readSourceHash(official.sourceId) ?? 'official-unknown';
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
    final engine = OfficialAnkiCompositionRoot.stagingEngineFromSession() ??
        OfficialAnkiCompositionRoot.projectionEngineFromSession();
    if (engine == null) {
      throw const OfficialAnkiException(
        code: OfficialAnkiErrorCode.capabilityMissing,
        messageKey: 'official_anki.importer_not_ready',
      );
    }
    final catalog = OfficialAnkiCompositionRoot.readOnlyCatalog ??
        OfficialAnkiCourseEntry.catalogOf?.call();
    if (catalog == null) {
      throw const OfficialAnkiException(
        code: OfficialAnkiErrorCode.capabilityMissing,
        messageKey: 'official_anki.catalog_missing',
      );
    }

    final cards = OfficialAnkiSourceDao(catalog).listCards(official.sourceId);
    final ids = <int>{};
    final sourceDeckIds = <int>{};
    for (final card in cards) {
      final id = card.notetypeId;
      if (id != null) ids.add(id);
      sourceDeckIds.add(card.deckId);
    }
    final notetypeIds = ids.toList();

    final schemas = await engine.getProjectionSchemas(
      notetypeIds: notetypeIds,
      includeSamples: true,
      sampleLimit: 30,
    );
    final allDecks = await engine.listDeckTree();
    final decks = _scopeDecks(allDecks, sourceDeckIds);
    return OfficialAnkiOfficialFirstPreview(
      sourceId: official.sourceId,
      sourceHash: sourceHash,
      cardCount: official.cardCount,
      noteCount: official.noteCount,
      decks: decks,
      cardCountByDeck: _cumulativeCardCountByDeck(allDecks, cards),
      schemas: schemas,
      suggestions: {
        for (final schema in schemas)
          schema.notetypeId: officialAnkiSuggestMapping(schema),
      },
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
            (name) =>
                name == deck.name ||
                name.startsWith('${deck.name}::'),
          ))
        deck,
  ];
}

/// deckId → 牌组（含后代）卡数：对每张卡沿其牌组名路径（'A::B::C'）逐级
/// 前缀累计，父牌组行即显示子树总数。不在树里的 deckId 无处展示，跳过。
Map<int, int> _cumulativeCardCountByDeck(
  List<OfficialAnkiDeckNode> tree,
  List<OfficialAnkiCardDescriptor> cards,
) {
  final nameByDeckId = {for (final deck in tree) deck.deckId: deck.name};
  final deckIdByName = {for (final deck in tree) deck.name: deck.deckId};
  final counts = <int, int>{};
  for (final card in cards) {
    final name = nameByDeckId[card.deckId];
    if (name == null) continue;
    final segments = name.split('::');
    for (var i = 1; i <= segments.length; i++) {
      final ancestorId = deckIdByName[segments.sublist(0, i).join('::')];
      if (ancestorId != null) {
        counts[ancestorId] = (counts[ancestorId] ?? 0) + 1;
      }
    }
  }
  return counts;
}
