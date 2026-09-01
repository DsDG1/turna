import 'dart:convert';

/// Turna 配置区命名空间（ADR 0043 D2 / step3.md op 42 语义）：
/// 写侧强制 `turna.` 前缀，值恒为 JSON object，`null` = 删除。
///
/// v2 决策键清单（step4.md B1/B6）：
/// - `turna.import.mapping.<sourceId>`   字段映射晋升决策
/// - `turna.course.placement.<deckId>`   牌组→课程放置决策
/// - `turna.course.scope`                课程 scope 选择（B6：切换=改一个键）
abstract final class OfficialAnkiV2ConfigKeys {
  static const namespace = 'turna.';

  static String importMapping(String sourceId) =>
      'turna.import.mapping.$sourceId';

  static String coursePlacement(int deckId) =>
      'turna.course.placement.$deckId';

  static const courseScope = 'turna.course.scope';

  /// SET_CONFIG (op 42) rejects non-`turna.` keys; every key built here
  /// passes that gate by construction.
  static bool isTurnaKey(String key) => key.startsWith(namespace);
}

/// `turna.import.mapping.<sourceId>` 的载荷：映射晋升写进配置区的那份
/// 决策（字段映射的「唯一事实」随 collection.anki2 原生备份走）。
class OfficialAnkiV2MappingDecision {
  const OfficialAnkiV2MappingDecision({
    required this.notetypeIdsConfirmed,
    required this.notetypeIdsSkipped,
    required this.suggestionsJson,
    this.schemaVersion = 1,
  });

  /// 向导确认（或自动确认）的 notetype id 集。
  final Set<int> notetypeIdsConfirmed;

  /// 用户明确跳过的 notetype id 集。
  final Set<int> notetypeIdsSkipped;

  /// `<notetypeId, suggestion>` 的 JSON 编码（识别器建议快照，配置区
  /// 损坏时可据此重建议——ADR「决策丢失 ≠ 数据丢失」）。
  final String suggestionsJson;

  final int schemaVersion;

  Map<String, Object?> toJson() => {
        'schema': schemaVersion,
        'confirmed': notetypeIdsConfirmed.toList()..sort(),
        'skipped': notetypeIdsSkipped.toList()..sort(),
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
