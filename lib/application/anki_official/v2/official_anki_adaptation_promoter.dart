import 'package:turna/application/anki_official/engine/official_anki_engine.dart';
import 'package:turna/application/anki_official/v2/official_anki_adaptation_store.dart';
import 'package:turna/application/anki_official/v2/official_anki_v2_config_keys.dart';
import 'package:turna/domain/anki/adaptation/card_adaptation_plan.dart';

/// Why one scope did not survive promotion. Kept as data so the preview can
/// explain it instead of silently dropping a group.
enum AdaptationSkipReason {
  /// The staging manifest entry / requested scopeKey could not be parsed.
  malformedScope,

  /// The plan body the entry points at is missing or unreadable.
  missingBody,

  /// The live collection no longer has that template ordinal (a re-import
  /// merged or removed templates — staging IDs are not proof of live IDs).
  missingTemplate,

  /// The plan's own scope disagrees with the key it was found under.
  scopeMismatch,
}

class AdaptationPromotionReport {
  const AdaptationPromotionReport({
    required this.promoted,
    required this.skipped,
    required this.cardsCopied,
  });

  static const AdaptationPromotionReport empty = AdaptationPromotionReport(
    promoted: 0,
    skipped: <String, AdaptationSkipReason>{},
    cardsCopied: 0,
  );

  final int promoted;

  /// scopeKey → reason.
  final Map<String, AdaptationSkipReason> skipped;

  final int cardsCopied;

  bool get hasSkips => skipped.isNotEmpty;

  int get skippedCount => skipped.length;
}

/// staging → live 重绑定（ADR 0057 §6 / plan §12.3）。
///
/// 预览期不把方案写进 staging collection：`promoteStagingCollection` 是否把
/// 配置区一起搬过去属于后端语义，不能假设。受限做法是把候选方案留在会话内
/// （`promotePlans`），提交时对 live 真实的模板序号核一遍再写；进程中断则
/// 什么都不落地——原卡与本地识别结果仍然可用。
///
/// 两个入口共用同一条校验/写入路径：
/// - [promote]：从 staging 的配置区读候选（适用于预览与提交在同一 collection
///   生命周期内的场景）。
/// - [promotePlans]：从内存里的 scopeKey → plan 读候选（导入向导的默认路径）。
class OfficialAnkiAdaptationPromoter {
  const OfficialAnkiAdaptationPromoter();

  Future<AdaptationPromotionReport> promote({
    required OfficialAnkiEngine staging,
    required OfficialAnkiEngine live,
    required String sourceId,
    required Map<int, Set<int>> liveTemplateOrdinals,
  }) async {
    final stagingStore = OfficialAnkiAdaptationStore(staging);
    final stagingManifest = await stagingStore.readManifest(sourceId);
    if (stagingManifest.entries.isEmpty) {
      return AdaptationPromotionReport.empty;
    }
    final overrides = await stagingStore.readCardOverrides(sourceId);
    return _promoteEntries(
      live: live,
      sourceId: sourceId,
      entries: stagingManifest.entries,
      readPlan: stagingStore.readRevision,
      liveTemplateOrdinals: liveTemplateOrdinals,
      cardOverrides: overrides,
    );
  }

  /// Promote plans held in memory by the import session.
  ///
  /// This is the path the import wizard uses: the candidate never needs to be
  /// written into the staging collection, so its fate does not depend on what
  /// the native promote step does with the config area.
  Future<AdaptationPromotionReport> promotePlans({
    required OfficialAnkiEngine live,
    required String sourceId,
    required Map<String, CardAdaptationPlan> plans,
    required Map<int, Set<int>> liveTemplateOrdinals,
  }) async {
    if (plans.isEmpty) return AdaptationPromotionReport.empty;
    final entries = <String, AdaptationManifestEntry>{
      for (final entry in plans.entries)
        entry.key: AdaptationManifestEntry(
          planId: entry.value.planId,
          revision: entry.value.revision,
        ),
    };
    return _promoteEntries(
      live: live,
      sourceId: sourceId,
      entries: entries,
      readPlan: (planId, revision) async {
        for (final plan in plans.values) {
          if (plan.planId == planId && plan.revision == revision) return plan;
        }
        return null;
      },
      liveTemplateOrdinals: liveTemplateOrdinals,
      cardOverrides: AdaptationCardOverrideTable.empty,
    );
  }

  Future<AdaptationPromotionReport> _promoteEntries({
    required OfficialAnkiEngine live,
    required String sourceId,
    required Map<String, AdaptationManifestEntry> entries,
    required Future<CardAdaptationPlan?> Function(String, int) readPlan,
    required Map<int, Set<int>> liveTemplateOrdinals,
    required AdaptationCardOverrideTable cardOverrides,
  }) async {
    final liveStore = OfficialAnkiAdaptationStore(live);
    final promotedEntries = <String, AdaptationManifestEntry>{};
    final skipped = <String, AdaptationSkipReason>{};

    for (final entry in entries.entries) {
      final scopeKey = entry.key;
      final scope = parseAdaptationScopeKey(scopeKey);
      if (scope == null) {
        skipped[scopeKey] = AdaptationSkipReason.malformedScope;
        continue;
      }
      final liveOrdinals = liveTemplateOrdinals[scope.notetypeId];
      if (liveOrdinals == null || !liveOrdinals.contains(scope.templateOrdinal)) {
        skipped[scopeKey] = AdaptationSkipReason.missingTemplate;
        continue;
      }
      final plan = await readPlan(entry.value.planId, entry.value.revision);
      if (plan == null) {
        skipped[scopeKey] = AdaptationSkipReason.missingBody;
        continue;
      }
      if (plan.scope.notetypeId != scope.notetypeId ||
          plan.scope.templateOrdinal != scope.templateOrdinal) {
        skipped[scopeKey] = AdaptationSkipReason.scopeMismatch;
        continue;
      }
      // Same (planId, revision) and same bytes: an idempotent replay. A
      // different body under the same key throws, which is the correct
      // outcome — a revision must never mean two different things.
      await liveStore.writeRevision(sourceId: sourceId, plan: plan);
      promotedEntries[scopeKey] = entry.value;
    }

    if (promotedEntries.isNotEmpty) {
      // Merge, don't replace: older scopes of the same source that the user
      // did not touch keep their active revision.
      final liveManifest = await liveStore.readManifest(sourceId);
      final merged = Map<String, AdaptationManifestEntry>.from(
        liveManifest.entries,
      )..addAll(promotedEntries);
      await liveStore.replaceManifest(
        sourceId,
        AdaptationManifest(
          schemaVersion: liveManifest.schemaVersion,
          entries: merged,
        ),
      );
    }

    // Per-card decisions travel with the group: a card pinned to the original
    // rendering must stay pinned after the import is committed.
    var cardsCopied = 0;
    if (cardOverrides.overrides.isNotEmpty) {
      final liveOverrides = await liveStore.readCardOverrides(sourceId);
      final merged = Map<int, AdaptationCardOverride>.from(
        liveOverrides.overrides,
      )..addAll(cardOverrides.overrides);
      await liveStore.replaceCardOverrides(
        sourceId,
        AdaptationCardOverrideTable(
          overrides: merged,
          schemaVersion: liveOverrides.schemaVersion,
        ),
      );
      cardsCopied = cardOverrides.overrides.length;
    }

    return AdaptationPromotionReport(
      promoted: promotedEntries.length,
      skipped: Map<String, AdaptationSkipReason>.unmodifiable(skipped),
      cardsCopied: cardsCopied,
    );
  }
}
