import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:turna/application/anki_official/contract/official_anki_dto.dart';
import 'package:turna/application/anki_official/engine/official_anki_engine.dart';
import 'package:turna/application/anki_official/lifecycle/official_anki_file_log.dart';
import 'package:turna/application/anki_official/projection/official_anki_projection_ids.dart';
import 'package:turna/application/anki_official/storage/official_anki_database.dart';
import 'package:turna/application/anki_official/storage/official_anki_source_dao.dart';
import 'package:turna/application/anki_official/v2/official_anki_v2_config_keys.dart';
import 'package:turna/application/anki_official/v2/official_anki_v2_decision_store.dart';
import 'package:turna/application/anki_official/v2/official_anki_v2_view_store.dart';
import 'package:turna/data/course_database.dart';

/// 重建结果（诊断与测试断言用）。
class OfficialAnkiV2ViewRebuildResult {
  const OfficialAnkiV2ViewRebuildResult({
    required this.sourceCount,
    required this.rowCount,
    required this.elapsedMillis,
    this.cancelled = false,
  });

  final int sourceCount;
  final int rowCount;
  final int elapsedMillis;
  final bool cancelled;
}

/// 视图重建的取消令牌：批间检查；配合引擎自带取消通道使用。
class OfficialAnkiV2ViewRebuildCancelToken {
  bool _cancelled = false;
  bool get isCancelled => _cancelled;
  void cancel() => _cancelled = true;
}

/// B3：v2 课程树物化视图重建器（D3/D7/K11/K13）。
///
/// 输入 = Collection（op 8 牌组树——经会话引擎在 worker isolate 上执行，
/// 主线程零 native 忙等）+ 配置区决策（op 41 放置/映射）+ 账本
/// （`anki_source_cards` 所有权清单 + `anki_sources` v2 活跃行）；
/// 输出 = `anki_course_tree_view` 单事务原子换页。幂等：同输入重建任意
/// 次结果相同；重建期间读面持旧视图（事务原子性），UI 可经
/// [rebuilding] 显示「重建中」占位；内置 Turkish 课程不经本表、天然
/// 不受影响（K11）。重建被杀 → 事务回滚 → 旧视图完整，重启重跑即收敛。
class OfficialAnkiV2ViewRebuilder {
  OfficialAnkiV2ViewRebuilder({
    required this.engine,
    required this.catalog,
    required this.course,
    required this.profileId,
    this.nowMillis,
  });

  final OfficialAnkiEngine engine;
  final OfficialAnkiDatabase catalog;
  final CourseDatabase course;
  final String profileId;
  final int Function()? nowMillis;

  /// K11「重建中」占位信号（进程内、无持久状态——视图本身无状态）。
  static final ValueNotifier<bool> rebuilding = ValueNotifier<bool>(false);

  int get _now => nowMillis?.call() ?? DateTime.now().millisecondsSinceEpoch;

  /// 全量重建。只包含 chain='v2' 且 state='active' 的 source——retiring
  /// 的 source 立即从视图消失（用户视角即刻移除），已删 source 不出现。
  Future<OfficialAnkiV2ViewRebuildResult> rebuild({
    OfficialAnkiV2ViewRebuildCancelToken? cancelToken,
  }) async {
    final started = _now;
    final dao = OfficialAnkiSourceDao(catalog);
    final decisions = OfficialAnkiV2DecisionStore(engine);
    final store = OfficialAnkiV2ViewStore(course);
    rebuilding.value = true;
    try {
      final sources =
          dao.listV2Sources(profileId, states: {'active'});
      if (cancelToken?.isCancelled ?? false) {
        return _result(sources.length, 0, started, cancelled: true);
      }
      // Collection 输入：牌组树（deckId → '::' 路径段）。单次 RPC。
      final deckPaths = _deckPaths(await engine.listDeckTree());

      // 账本输入：每个 source 的所有权清单（读一次，循环内外共用）。
      final cardsBySource = <String, List<OfficialAnkiCardDescriptor>>{
        for (final source in sources)
          source.sourceId: dao.listCards(source.sourceId),
      };

      // 配置区输入：出现过的顶层牌组的放置决策（数量 = 顶层牌组数）。
      final topDeckIds = <int?>{
        for (final cards in cardsBySource.values)
          for (final card in cards) _topDeckId(card.deckId, deckPaths),
      }.whereType<int>().toSet();
      final placements = await decisions.readDeckPlacements(topDeckIds);

      final rows = <OfficialAnkiV2ViewRow>[];
      for (final source in sources) {
        if (cancelToken?.isCancelled ?? false) break;
        final mapping = await decisions.readImportMapping(source.sourceId);
        final kindsByNotetype = _kindsByNotetype(mapping);
        final skipped = mapping?.notetypeIdsSkipped ?? const <int>{};
        for (final card in cardsBySource[source.sourceId] ?? const []) {
          final path = deckPaths[card.deckId] ?? const <String>[];
          final topDeckId = _topDeckId(card.deckId, deckPaths);
          final placement =
              _place(source.sourceId, path, placements[topDeckId]);
          // 用户明确跳过的 notetype 不进课程树（与 v1 映射语义一致）。
          if (card.notetypeId != null && skipped.contains(card.notetypeId)) {
            continue;
          }
          rows.add(OfficialAnkiV2ViewRow(
            sourceId: source.sourceId,
            cardId: card.cardId,
            noteId: card.noteId,
            deckId: card.deckId,
            wordId:
                officialAnkiWordId(profileId: profileId, cardId: card.cardId),
            sectionKey: placement.sectionKey,
            sectionId: placement.sectionId,
            unitId: placement.unitId,
            lessonId: placement.lessonId,
            lessonKey: placement.lessonKey,
            presentationKind:
                kindsByNotetype[card.notetypeId ?? -1] ?? 'showWord',
            sourceHash: source.sourceHash,
          ));
        }
      }
      if (cancelToken?.isCancelled ?? false) {
        return _result(sources.length, 0, started, cancelled: true);
      }
      await store.replaceAll(rows: rows, rebuiltAtMillis: _now);
      officialAnkiV2Log(
        'view rebuild: ${sources.length} sources, ${rows.length} rows, '
        '${_now - started}ms',
      );
      return _result(sources.length, rows.length, started);
    } finally {
      rebuilding.value = false;
    }
  }

  OfficialAnkiV2ViewRebuildResult _result(
    int sourceCount,
    int rowCount,
    int started, {
    bool cancelled = false,
  }) {
    return OfficialAnkiV2ViewRebuildResult(
      sourceCount: sourceCount,
      rowCount: rowCount,
      elapsedMillis: _now - started,
      cancelled: cancelled,
    );
  }

  /// deckId → 名字路径（'A::B::C' 拆段）。
  static Map<int, List<String>> _deckPaths(List<OfficialAnkiDeckNode> tree) {
    return {
      for (final node in tree) node.deckId: node.name.split('::'),
    };
  }

  /// 路径首段对应的顶层牌组 id（放置决策按顶层牌组落键）。
  static int? _topDeckId(int deckId, Map<int, List<String>> deckPaths) {
    final path = deckPaths[deckId];
    if (path == null || path.isEmpty) return null;
    final topName = path.first;
    for (final entry in deckPaths.entries) {
      if (entry.value.length == 1 && entry.value.first == topName) {
        return entry.key;
      }
    }
    return null;
  }

  /// 放置决策：覆盖优先（D2 用户决策），否则按 deck 路径默认派生——
  /// 第一段 = section、第二段 = unit、末段 = lesson；单段牌组三级同段。
  static _Placement _place(
    String sourceId,
    List<String> path,
    OfficialAnkiV2PlacementDecision? override,
  ) {
    final effective = path.isEmpty ? const ['Cards'] : path;
    String sectionKey;
    String unitKey;
    String lessonKey;
    if (override != null) {
      sectionKey = override.sectionKey;
      unitKey = override.unitKey;
      lessonKey = override.lessonKey;
    } else if (effective.length == 1) {
      sectionKey = unitKey = lessonKey = effective.first;
    } else if (effective.length == 2) {
      sectionKey = effective.first;
      unitKey = lessonKey = effective.last;
    } else {
      sectionKey = effective.first;
      unitKey = effective[1];
      lessonKey = effective.last;
    }
    return _Placement(
      sectionKey: sectionKey,
      sectionId: officialAnkiSectionIdForTopDeck(
        sourceId: sourceId,
        topDeckName: sectionKey,
      ),
      unitId: officialAnkiUnitId(
        sourceId: sourceId,
        deckPath: [sectionKey, unitKey],
      ),
      lessonId: officialAnkiLessonId(
        sourceId: sourceId,
        groupKey: [sectionKey, unitKey, lessonKey].join('\u001f'),
        part: 1,
      ),
      lessonKey: lessonKey,
    );
  }

  /// notetype → 主呈现 kind（决策里 enabledKinds 的第一个）。
  static Map<int, String> _kindsByNotetype(
    OfficialAnkiV2MappingDecision? mapping,
  ) {
    if (mapping == null) return const {};
    try {
      final decoded = jsonDecode(mapping.suggestionsJson);
      if (decoded is! Map) return const {};
      final out = <int, String>{};
      for (final entry in decoded.entries) {
        final id = int.tryParse('${entry.key}');
        if (id == null || entry.value is! Map) continue;
        final kinds = (entry.value as Map)['enabledKinds'];
        if (kinds is List && kinds.isNotEmpty) {
          out[id] = '${kinds.first}';
        }
      }
      return out;
    } catch (_) {
      return const {};
    }
  }
}

class _Placement {
  const _Placement({
    required this.sectionKey,
    required this.sectionId,
    required this.unitId,
    required this.lessonId,
    required this.lessonKey,
  });

  final String sectionKey;
  final String sectionId;
  final String unitId;
  final String lessonId;
  final String lessonKey;
}
