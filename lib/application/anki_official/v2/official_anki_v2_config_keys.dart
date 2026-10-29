import 'dart:convert';

/// Turna 配置区命名空间（ADR 0043 D2 / ADR 0043 语义）：
/// 写侧强制 `turna.` 前缀，值恒为 JSON object，`null` = 删除。
///
/// v2 决策键清单（ADR 0043）：
/// - `turna.import.mapping.<sourceId>`   字段映射晋升决策
/// - `turna.course.placement.<deckId>`   牌组→课程放置决策
/// - `turna.course.scope`                课程 scope 选择（B6：切换=改一个键）
abstract final class OfficialAnkiV2ConfigKeys {
  static const namespace = 'turna.';

  static String importMapping(String sourceId) =>
      'turna.import.mapping.$sourceId';

  static String coursePlacement(int deckId) => 'turna.course.placement.$deckId';

  static const courseScope = 'turna.course.scope';

  /// SET_CONFIG (op 42) rejects non-`turna.` keys; every key built here
  /// passes that gate by construction.
  static bool isTurnaKey(String key) => key.startsWith(namespace);
}

/// 适配决策的配置区键族（ADR 0057 §6）。
///
/// 四个键族各管一件事，读取端只认 manifest：
/// - `turna.adapt.plan.<planId>.r<revision>`  不可变方案体
/// - `turna.adapt.manifest.<sourceId>`        scopeKey → {planId, revision}
/// - `turna.adapt.cards.<sourceId>`           单卡覆盖（一张小表，避免逐卡建键）
/// - `turna.adapt.index.<sourceId>`           已写过的 plan 键清单（GC / 卸载用）
///
/// 单卡覆盖刻意做成每 source 一个键：逐卡建键会让「按来源清理命名空间」
/// 需要枚举配置区，而引擎没有可靠的枚举语义。
abstract final class OfficialAnkiAdaptationConfigKeys {
  static const namespace = 'turna.adapt.';

  /// 一次修订的完整键。planId 里的 `.` 会与键分隔符混淆，构造时统一换成 `_`。
  static String plan(String planId, int revision) =>
      '${namespace}plan.${_sanitize(planId)}.r$revision';

  static String manifest(String sourceId) => '${namespace}manifest.$sourceId';

  static String cards(String sourceId) => '${namespace}cards.$sourceId';

  static String index(String sourceId) => '${namespace}index.$sourceId';

  static String _sanitize(String planId) => planId.replaceAll('.', '_');
}

/// 一个 scope 当前生效的修订引用。
class AdaptationManifestEntry {
  const AdaptationManifestEntry({
    required this.planId,
    required this.revision,
  });

  final String planId;
  final int revision;

  Map<String, Object?> toJson() => <String, Object?>{
        'planId': planId,
        'revision': revision,
      };

  static AdaptationManifestEntry? decode(Object? raw) {
    if (raw is! Map) return null;
    final planId = raw['planId'];
    final revision = raw['revision'];
    if (planId is! String || planId.isEmpty || revision is! num) return null;
    return AdaptationManifestEntry(
      planId: planId,
      revision: revision.toInt(),
    );
  }
}

/// `turna.adapt.manifest.<sourceId>` 的载荷。
///
/// 只有一个键的写是原子的，所以「切换生效」= 写这一个键；方案体先写、清单
/// 后切，中断时最多留下未被引用的候选修订，读端永远看不到半份方案。
class AdaptationManifest {
  const AdaptationManifest({
    required this.entries,
    this.schemaVersion = currentSchemaVersion,
  });

  static const AdaptationManifest empty = AdaptationManifest(entries: {});

  /// This build's payload schema. A payload carrying a higher version was
  /// written by a newer app and cannot be proven to mean what this build
  /// reads — the read side falls back (fail-closed) instead of guessing.
  static const int currentSchemaVersion = 1;

  /// scopeKey（`notetype:template[:cloze]`）→ 生效修订。
  final Map<String, AdaptationManifestEntry> entries;
  final int schemaVersion;

  Map<String, Object?> toJson() => <String, Object?>{
        'schema': schemaVersion,
        'entries': {
          for (final entry in entries.entries) entry.key: entry.value.toJson(),
        },
      };

  static AdaptationManifest? decode(Object? value) {
    if (value is! Map) return null;
    final rawEntries = value['entries'];
    final entries = <String, AdaptationManifestEntry>{};
    if (rawEntries is Map) {
      for (final entry in rawEntries.entries) {
        final decoded = AdaptationManifestEntry.decode(entry.value);
        if (decoded != null) entries['${entry.key}'] = decoded;
      }
    }
    return AdaptationManifest(
      entries: entries,
      schemaVersion: (value['schema'] as num?)?.toInt() ?? 1,
    );
  }
}

/// 单卡覆盖：要么明确回原卡，要么指定另一份修订。
class AdaptationCardOverride {
  const AdaptationCardOverride.original()
      : mode = AdaptationOverrideMode.original,
        planId = null,
        revision = null;

  const AdaptationCardOverride.plan({
    required String this.planId,
    required int this.revision,
  }) : mode = AdaptationOverrideMode.plan;

  final AdaptationOverrideMode mode;
  final String? planId;
  final int? revision;

  Map<String, Object?> toJson() => <String, Object?>{
        'mode': mode.name,
        if (planId != null) 'planId': planId,
        if (revision != null) 'revision': revision,
      };

  static AdaptationCardOverride? decode(Object? raw) {
    if (raw is! Map) return null;
    final mode = raw['mode'];
    if (mode == AdaptationOverrideMode.original.name) {
      return const AdaptationCardOverride.original();
    }
    final planId = raw['planId'];
    final revision = raw['revision'];
    if (planId is String && revision is num) {
      return AdaptationCardOverride.plan(
        planId: planId,
        revision: revision.toInt(),
      );
    }
    return null;
  }
}

enum AdaptationOverrideMode { original, plan }

/// `turna.adapt.cards.<sourceId>` 的载荷：cardId → 覆盖。
class AdaptationCardOverrideTable {
  const AdaptationCardOverrideTable({
    required this.overrides,
    this.schemaVersion = AdaptationManifest.currentSchemaVersion,
  });

  static const AdaptationCardOverrideTable empty =
      AdaptationCardOverrideTable(overrides: {});

  /// Same forward-compat rule as [AdaptationManifest.currentSchemaVersion].
  static const int currentSchemaVersion =
      AdaptationManifest.currentSchemaVersion;

  final Map<int, AdaptationCardOverride> overrides;
  final int schemaVersion;

  Map<String, Object?> toJson() => <String, Object?>{
        'schema': schemaVersion,
        'overrides': {
          for (final entry in overrides.entries)
            '${entry.key}': entry.value.toJson(),
        },
      };

  static AdaptationCardOverrideTable? decode(Object? value) {
    if (value is! Map) return null;
    final raw = value['overrides'];
    final overrides = <int, AdaptationCardOverride>{};
    if (raw is Map) {
      for (final entry in raw.entries) {
        final cardId = int.tryParse('${entry.key}');
        if (cardId == null) continue;
        final decoded = AdaptationCardOverride.decode(entry.value);
        if (decoded != null) overrides[cardId] = decoded;
      }
    }
    return AdaptationCardOverrideTable(
      overrides: overrides,
      schemaVersion: (value['schema'] as num?)?.toInt() ?? 1,
    );
  }
}

/// `turna.adapt.index.<sourceId>` 的载荷：这个来源写过的 plan 键清单。
class AdaptationPlanIndex {
  const AdaptationPlanIndex({required this.keys, this.schemaVersion = 1});

  static const AdaptationPlanIndex empty = AdaptationPlanIndex(keys: []);

  final List<String> keys;
  final int schemaVersion;

  Map<String, Object?> toJson() => <String, Object?>{
        'schema': schemaVersion,
        'keys': keys,
      };

  static AdaptationPlanIndex? decode(Object? value) {
    if (value is! Map) return null;
    final raw = value['keys'];
    return AdaptationPlanIndex(
      keys: raw is List ? [for (final key in raw) '$key'] : const <String>[],
      schemaVersion: (value['schema'] as num?)?.toInt() ?? 1,
    );
  }
}

/// `turna.import.mapping.<sourceId>` 的载荷：映射晋升写进配置区的那份
/// 决策（字段映射的「唯一事实」随 collection.anki2 原生备份走）。
class OfficialAnkiV2MappingDecision {
  const OfficialAnkiV2MappingDecision({
    required this.notetypeIdsConfirmed,
    required this.notetypeIdsSkipped,
    required this.suggestionsJson,
    this.excludedDeckIds = const <int>{},
    this.schemaVersion = 1,
  });

  /// 向导确认（或自动确认）的 notetype id 集。
  final Set<int> notetypeIdsConfirmed;

  /// 用户明确跳过的 notetype id 集。
  final Set<int> notetypeIdsSkipped;

  /// `<notetypeId, suggestion>` 的 JSON 编码（识别器建议快照，配置区
  /// 损坏时可据此重建议——ADR「决策丢失 ≠ 数据丢失」）。
  final String suggestionsJson;

  /// Decks the user left unchecked. Cards stay in the collection and are
  /// suspended; they are omitted from the course tree.
  final Set<int> excludedDeckIds;

  final int schemaVersion;

  Map<String, Object?> toJson() => {
        'schema': schemaVersion,
        'confirmed': notetypeIdsConfirmed.toList()..sort(),
        'skipped': notetypeIdsSkipped.toList()..sort(),
        'excludedDecks': excludedDeckIds.toList()..sort(),
        'suggestions': suggestionsJson,
      };

  factory OfficialAnkiV2MappingDecision.fromJson(Map<String, Object?> json) {
    Set<int> ids(Object? raw) => {
          if (raw is List)
            for (final e in raw)
              if (e is num) e.toInt(),
        };
    return OfficialAnkiV2MappingDecision(
      notetypeIdsConfirmed: ids(json['confirmed']),
      notetypeIdsSkipped: ids(json['skipped']),
      excludedDeckIds: ids(json['excludedDecks']),
      suggestionsJson: (json['suggestions'] as String?) ?? '{}',
      schemaVersion: (json['schema'] as num?)?.toInt() ?? 1,
    );
  }

  String encode() => jsonEncode(toJson());

  static OfficialAnkiV2MappingDecision? decode(Object? value) {
    if (value is! Map) return null;
    try {
      return OfficialAnkiV2MappingDecision.fromJson(
        Map<String, Object?>.from(value),
      );
    } catch (_) {
      // 配置区损坏按 missing 处理（rslib 读语义先例），识别器可重建议。
      return null;
    }
  }
}

/// `turna.course.placement.<deckId>` 的载荷：一个牌组落进课程树的哪
/// 一层。deck path 是默认派生；本决策存在即覆盖（D2：用户放置决策）。
class OfficialAnkiV2PlacementDecision {
  const OfficialAnkiV2PlacementDecision({
    required this.deckPath,
    required this.sectionKey,
    required this.unitKey,
    required this.lessonKey,
    this.schemaVersion = 1,
  });

  final String deckPath;
  final String sectionKey;
  final String unitKey;
  final String lessonKey;
  final int schemaVersion;

  Map<String, Object?> toJson() => {
        'schema': schemaVersion,
        'deckPath': deckPath,
        'section': sectionKey,
        'unit': unitKey,
        'lesson': lessonKey,
      };

  factory OfficialAnkiV2PlacementDecision.fromJson(Map<String, Object?> json) {
    String s(String key) => (json[key] as String?) ?? '';
    return OfficialAnkiV2PlacementDecision(
      deckPath: s('deckPath'),
      sectionKey: s('section'),
      unitKey: s('unit'),
      lessonKey: s('lesson'),
      schemaVersion: (json['schema'] as num?)?.toInt() ?? 1,
    );
  }

  String encode() => jsonEncode(toJson());

  static OfficialAnkiV2PlacementDecision? decode(Object? value) {
    if (value is! Map) return null;
    try {
      return OfficialAnkiV2PlacementDecision.fromJson(
        Map<String, Object?>.from(value),
      );
    } catch (_) {
      return null;
    }
  }
}
