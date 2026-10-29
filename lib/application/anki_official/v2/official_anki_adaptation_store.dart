import 'dart:convert';

import 'package:turna/application/anki_official/contract/official_anki_errors.dart';
import 'package:turna/application/anki_official/engine/official_anki_engine.dart';
import 'package:turna/application/anki_official/lifecycle/official_anki_file_log.dart';
import 'package:turna/application/anki_official/v2/official_anki_v2_config_keys.dart';
import 'package:turna/domain/anki/adaptation/card_adaptation_plan.dart';

/// Outcome of looking up the plan that applies to one card.
///
/// Four states, because "no plan" and "a plan that points at a deleted body"
/// must not be confused: the first is the normal old-data path, the second is a
/// broken namespace that has to fall back to the original card without ever
/// pretending a plan is active (ADR 0057 §6).
sealed class AdaptationLookup {
  const AdaptationLookup();
}

final class AdaptationPlanFound extends AdaptationLookup {
  const AdaptationPlanFound(this.plan, {required this.fromCardOverride});

  final CardAdaptationPlan plan;
  final bool fromCardOverride;
}

/// The user pinned this card to the original rendering.
final class AdaptationExplicitlyOriginal extends AdaptationLookup {
  const AdaptationExplicitlyOriginal();
}

final class AdaptationNoPlan extends AdaptationLookup {
  const AdaptationNoPlan();
}

/// The manifest references a revision that is missing or unreadable.
final class AdaptationPlanMissing extends AdaptationLookup {
  const AdaptationPlanMissing(this.planId, this.revision);

  final String planId;
  final int revision;
}

/// `notetype:template[:cloze]` — the manifest's scope key.
String adaptationScopeKey(
  int notetypeId,
  int templateOrdinal, {
  int? clozeTarget,
}) {
  final base = '$notetypeId:$templateOrdinal';
  return clozeTarget == null ? base : '$base:c$clozeTarget';
}

/// Inverse of [adaptationScopeKey]. Null for a malformed key: a corrupt
/// manifest entry is skipped, never guessed at.
({int notetypeId, int templateOrdinal, int? clozeTarget})? parseAdaptationScopeKey(
  String key,
) {
  final parts = key.split(':');
  if (parts.length < 2 || parts.length > 3) return null;
  final notetypeId = int.tryParse(parts[0]);
  final templateOrdinal = int.tryParse(parts[1]);
  if (notetypeId == null || templateOrdinal == null) return null;
  int? clozeTarget;
  if (parts.length == 3) {
    final raw = parts[2];
    if (!raw.startsWith('c')) return null;
    clozeTarget = int.tryParse(raw.substring(1));
    if (clozeTarget == null) return null;
  }
  return (
    notetypeId: notetypeId,
    templateOrdinal: templateOrdinal,
    clozeTarget: clozeTarget,
  );
}

/// A lesson-scoped view of the adaptation namespace: manifest + overrides are
/// read once, revision bodies are read on demand and cached.
class AdaptationSnapshot {
  AdaptationSnapshot._({
    required AdaptationManifest manifest,
    required AdaptationCardOverrideTable overrides,
    required Future<CardAdaptationPlan?> Function(String, int) readRevision,
  })  : _manifest = manifest,
        _overrides = overrides,
        _readRevision = readRevision;

  final AdaptationManifest _manifest;
  final AdaptationCardOverrideTable _overrides;
  final Future<CardAdaptationPlan?> Function(String, int) _readRevision;
  final Map<String, CardAdaptationPlan?> _revisions = <String, CardAdaptationPlan?>{};

  bool get isEmpty =>
      _manifest.entries.isEmpty && _overrides.overrides.isEmpty;

  Future<CardAdaptationPlan?> _revision(String planId, int revision) async {
    final key = '$planId@$revision';
    if (_revisions.containsKey(key)) return _revisions[key];
    final plan = await _readRevision(planId, revision);
    _revisions[key] = plan;
    return plan;
  }

  /// Same precedence as [OfficialAnkiAdaptationStore.lookup], from the snapshot.
  Future<AdaptationLookup> lookup({
    required int notetypeId,
    required int templateOrdinal,
    required int cardId,
    int? clozeTarget,
  }) async {
    final override = _overrides.overrides[cardId];
    if (override != null) {
      switch (override.mode) {
        case AdaptationOverrideMode.original:
          return const AdaptationExplicitlyOriginal();
        case AdaptationOverrideMode.plan:
          final plan = await _revision(override.planId!, override.revision!);
          if (plan == null) {
            return AdaptationPlanMissing(override.planId!, override.revision!);
          }
          return AdaptationPlanFound(plan, fromCardOverride: true);
      }
    }

    final scopeKeys = <String>[
      if (clozeTarget != null)
        adaptationScopeKey(
          notetypeId,
          templateOrdinal,
          clozeTarget: clozeTarget,
        ),
      adaptationScopeKey(notetypeId, templateOrdinal),
    ];
    for (final key in scopeKeys) {
      final entry = _manifest.entries[key];
      if (entry == null) continue;
      final plan = await _revision(entry.planId, entry.revision);
      if (plan == null) {
        return AdaptationPlanMissing(entry.planId, entry.revision);
      }
      return AdaptationPlanFound(plan, fromCardOverride: false);
    }
    return const AdaptationNoPlan();
  }
}

/// 适配方案的持久化与激活（ADR 0057 §6）。
///
/// 三条纪律：
/// 1. 方案体不可变——同键不同内容直接拒绝，而不是悄悄覆盖。
/// 2. 先写方案体、后切 manifest；读端只认 manifest，中断不会产生半份方案。
/// 3. 单卡覆盖优先于模板方案；「明确回原卡」与「没有任何方案」是两种状态。
///
/// 全部写在 Collection 配置区（随 collection.anki2 备份走），不碰 catalog
/// 表、不写 scheduler、不复制卡面。
class OfficialAnkiAdaptationStore {
  const OfficialAnkiAdaptationStore(this._engine);

  final OfficialAnkiEngine _engine;

  Future<AdaptationManifest> readManifest(String sourceId) async {
    final value =
        await _engine.getConfig(OfficialAnkiAdaptationConfigKeys.manifest(sourceId));
    if (!value.found) return AdaptationManifest.empty;
    final decoded = AdaptationManifest.decode(value.value);
    if (decoded == null) {
      // 损坏按「没有方案」处理（回退行为不变），但必须留痕——「这个来源
      // 本来就没有方案」和「有一份读不懂的方案」在日志里要能区分（B5）。
      officialAnkiV2Log(
        'adaptation manifest for $sourceId is corrupt; '
        'treating as no plans',
        warning: true,
      );
      return AdaptationManifest.empty;
    }
    if (decoded.schemaVersion > AdaptationManifest.currentSchemaVersion) {
      // 更高版本 = 更新的 app 写的，本版本无法证明自己读得懂：不套用其
      // 条目，卡面走原卡/识别结果，而不是猜一个语义。
      officialAnkiV2Log(
        'adaptation manifest for $sourceId has schema '
        '${decoded.schemaVersion} > ${AdaptationManifest.currentSchemaVersion}; '
        'ignoring it (written by a newer app)',
        warning: true,
      );
      return AdaptationManifest.empty;
    }
    return decoded;
  }

  Future<AdaptationCardOverrideTable> readCardOverrides(String sourceId) async {
    final value =
        await _engine.getConfig(OfficialAnkiAdaptationConfigKeys.cards(sourceId));
    if (!value.found) return AdaptationCardOverrideTable.empty;
    final decoded = AdaptationCardOverrideTable.decode(value.value);
    if (decoded == null) {
      officialAnkiV2Log(
        'adaptation card overrides for $sourceId are corrupt; '
        'treating as none',
        warning: true,
      );
      return AdaptationCardOverrideTable.empty;
    }
    if (decoded.schemaVersion > AdaptationCardOverrideTable.currentSchemaVersion) {
      officialAnkiV2Log(
        'adaptation card overrides for $sourceId have schema '
        '${decoded.schemaVersion} > '
        '${AdaptationCardOverrideTable.currentSchemaVersion}; ignoring them',
        warning: true,
      );
      return AdaptationCardOverrideTable.empty;
    }
    return decoded;
  }

  /// Write one immutable revision and remember its key for cleanup.
  ///
  /// Throws when the same `(planId, revision)` already holds a different body:
  /// that is a caller bug (revision numbers must be bumped), and silently
  /// overwriting would let an old manifest reference mean something new.
  Future<bool> writeRevision({
    required String sourceId,
    required CardAdaptationPlan plan,
  }) async {
    final key =
        OfficialAnkiAdaptationConfigKeys.plan(plan.planId, plan.revision);
    final encoded = jsonEncode(plan.toJson());

    final existing = await _engine.getConfig(key);
    if (existing.found) {
      final existingJson = jsonEncode(existing.value);
      if (existingJson != encoded) {
        throw const OfficialAnkiException(
          code: OfficialAnkiErrorCode.invalidState,
          messageKey: 'official_anki.invalid_state',
          debugDetails: 'adaptation_revision_not_immutable',
        );
      }
      return true; // same bytes: idempotent replay
    }

    final result = await _engine.setConfig(key, plan.toJson());
    if (!result.ok) {
      throw const OfficialAnkiException(
        code: OfficialAnkiErrorCode.invalidState,
        messageKey: 'official_anki.invalid_state',
        debugDetails: 'adaptation_revision_write_failed',
      );
    }
    await _rememberKey(sourceId, key);
    return true;
  }

  Future<CardAdaptationPlan?> readRevision(
    String planId,
    int revision,
  ) async {
    final value = await _engine.getConfig(
      OfficialAnkiAdaptationConfigKeys.plan(planId, revision),
    );
    if (!value.found || value.value is! Map) return null;
    try {
      final plan = CardAdaptationPlan.fromJson(
        Map<String, Object?>.from(value.value as Map),
      );
      if (plan.schemaVersion > AdaptationVocabulary.schemaVersion) {
        // 更新版本 app 写的方案：本版本不套用（fail-closed 回原卡），留痕
        // 说明「读不懂」而不是「不存在」（B5）。
        officialAnkiV2Log(
          'adaptation plan $planId@$revision has schema '
          '${plan.schemaVersion} > ${AdaptationVocabulary.schemaVersion}; '
          'treating as missing (written by a newer app)',
          warning: true,
        );
        return null;
      }
      return plan;
    } catch (error) {
      // 损坏读作 missing（配置区读语义先例）: the caller falls back to the
      // original card — logged so "corrupt" is distinguishable from "absent".
      officialAnkiV2Log(
        'adaptation plan $planId@$revision is corrupt: $error; '
        'treating as missing',
        warning: true,
      );
      return null;
    }
  }

  /// Activate one revision for one scope.
  ///
  /// The manifest write is the only atomic step that matters: it happens after
  /// the body is written *and* read back, so a crash in between leaves an
  /// unreferenced revision (harmless, swept on uninstall) rather than a
  /// reference to nothing.
  Future<bool> activate({
    required String sourceId,
    required String scopeKey,
    required CardAdaptationPlan plan,
  }) async {
    await writeRevision(sourceId: sourceId, plan: plan);
    final readable = await readRevision(plan.planId, plan.revision);
    if (readable == null) {
      return false;
    }

    final manifest = await readManifest(sourceId);
    final entries = Map<String, AdaptationManifestEntry>.from(manifest.entries)
      ..[scopeKey] = AdaptationManifestEntry(
        planId: plan.planId,
        revision: plan.revision,
      );
    return _writeManifest(
      sourceId,
      AdaptationManifest(schemaVersion: manifest.schemaVersion, entries: entries),
    );
  }

  /// Remove one scope's active revision. The body stays on disk until the
  /// namespace is deleted, so switching back and forth costs no rewrites.
  Future<bool> deactivate({
    required String sourceId,
    required String scopeKey,
  }) async {
    final manifest = await readManifest(sourceId);
    if (!manifest.entries.containsKey(scopeKey)) return true;
    final entries = Map<String, AdaptationManifestEntry>.from(manifest.entries)
      ..remove(scopeKey);
    return _writeManifest(
      sourceId,
      AdaptationManifest(schemaVersion: manifest.schemaVersion, entries: entries),
    );
  }

  /// Which plan applies to this card, honoring the precedence order
  /// card override > exact cloze scope > template scope > none.
  Future<AdaptationLookup> lookup({
    required String sourceId,
    required int notetypeId,
    required int templateOrdinal,
    required int cardId,
    int? clozeTarget,
  }) async {
    final snapshot = await this.snapshot(sourceId);
    return snapshot.lookup(
      notetypeId: notetypeId,
      templateOrdinal: templateOrdinal,
      cardId: cardId,
      clozeTarget: clozeTarget,
    );
  }

  /// Read the manifest and the override table once, then answer every card in
  /// a lesson from that snapshot. Revision bodies are read lazily and cached,
  /// so a 20-card lesson costs 2 + (distinct plans) config reads instead of
  /// 3 × cards.
  Future<AdaptationSnapshot> snapshot(String sourceId) async {
    final manifest = await readManifest(sourceId);
    final overrides = await readCardOverrides(sourceId);
    return AdaptationSnapshot._(
      manifest: manifest,
      overrides: overrides,
      readRevision: readRevision,
    );
  }

  Future<bool> writeCardOverride({
    required String sourceId,
    required int cardId,
    required AdaptationCardOverride override,
  }) async {
    final table = await readCardOverrides(sourceId);
    final overrides = Map<int, AdaptationCardOverride>.from(table.overrides)
      ..[cardId] = override;
    return _writeTable(sourceId, overrides, table.schemaVersion);
  }

  Future<bool> clearCardOverride({
    required String sourceId,
    required int cardId,
  }) async {
    final table = await readCardOverrides(sourceId);
    if (!table.overrides.containsKey(cardId)) return true;
    final overrides = Map<int, AdaptationCardOverride>.from(table.overrides)
      ..remove(cardId);
    return _writeTable(sourceId, overrides, table.schemaVersion);
  }

  /// Uninstall / source removal: drop the manifest, the overrides and every
  /// revision this source ever wrote. The index is the only reason this can be
  /// complete — the config area has no enumeration operation.
  Future<void> deleteSourceNamespace(String sourceId) async {
    final indexValue =
        await _engine.getConfig(OfficialAnkiAdaptationConfigKeys.index(sourceId));
    final index = indexValue.found
        ? AdaptationPlanIndex.decode(indexValue.value)
        : null;
    for (final key in index?.keys ?? const <String>[]) {
      await _engine.setConfig(key, null);
    }
    await _engine.setConfig(OfficialAnkiAdaptationConfigKeys.manifest(sourceId), null);
    await _engine.setConfig(OfficialAnkiAdaptationConfigKeys.cards(sourceId), null);
    await _engine.setConfig(OfficialAnkiAdaptationConfigKeys.index(sourceId), null);
  }

  Future<bool> _writeManifest(
    String sourceId,
    AdaptationManifest manifest,
  ) async {
    final result = await _engine.setConfig(
      OfficialAnkiAdaptationConfigKeys.manifest(sourceId),
      manifest.toJson(),
    );
    return result.ok;
  }

  /// Replace the whole active manifest in one write.
  ///
  /// Promotion (staging → live) needs this: writing N single-scope switches
  /// would let a crash expose a half-promoted group, while one manifest write
  /// is atomic and leaves the previous state intact on failure.
  Future<bool> replaceManifest(
    String sourceId,
    AdaptationManifest manifest,
  ) => _writeManifest(sourceId, manifest);

  /// Replace the whole card-override table (used by promotion, which copies
  /// the user's per-card decisions to the live collection).
  Future<bool> replaceCardOverrides(
    String sourceId,
    AdaptationCardOverrideTable table,
  ) => _writeTable(
        sourceId,
        table.overrides,
        table.schemaVersion,
      );

  Future<bool> _writeTable(
    String sourceId,
    Map<int, AdaptationCardOverride> overrides,
    int schemaVersion,
  ) async {
    if (overrides.isEmpty) {
      // An empty table is a delete: keeping `{}` would make "has overrides"
      // indistinguishable from "no overrides" for callers that only check keys.
      final result = await _engine.setConfig(
        OfficialAnkiAdaptationConfigKeys.cards(sourceId),
        null,
      );
      return result.ok;
    }
    final result = await _engine.setConfig(
      OfficialAnkiAdaptationConfigKeys.cards(sourceId),
      AdaptationCardOverrideTable(
        overrides: overrides,
        schemaVersion: schemaVersion,
      ).toJson(),
    );
    return result.ok;
  }

  /// Best-effort index maintenance: a failed index write leaves an orphan
  /// revision behind on uninstall, which is bounded and harmless, so it must
  /// not fail the activation the user just confirmed.
  Future<void> _rememberKey(String sourceId, String key) async {
    try {
      final value = await _engine
          .getConfig(OfficialAnkiAdaptationConfigKeys.index(sourceId));
      final index =
          value.found ? AdaptationPlanIndex.decode(value.value) : null;
      final keys = [...index?.keys ?? const <String>[]];
      if (keys.contains(key)) return;
      keys.add(key);
      await _engine.setConfig(
        OfficialAnkiAdaptationConfigKeys.index(sourceId),
        AdaptationPlanIndex(keys: keys, schemaVersion: index?.schemaVersion ?? 1)
            .toJson(),
      );
    } catch (error) {
      officialAnkiV2Log('adaptation index write failed: $error', warning: true);
    }
  }
}
