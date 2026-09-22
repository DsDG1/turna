import 'dart:convert';
import 'dart:isolate';

import 'package:flutter/foundation.dart';
import 'package:turna/application/anki_import/recognition/recognize/result.dart';
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
    this.sectionCount = 0,
    this.lessonCount = 0,
  });

  final int sourceCount;
  final int rowCount;
  final int elapsedMillis;
  final bool cancelled;

  /// 整视图的 distinct section/lesson 数（commit receipt 用）。全量
  /// rebuild 从内存 rows 直接算；scoped rebuild 换页后查视图（C6）。
  final int sectionCount;
  final int lessonCount;
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
    this.lessonSize = defaultLessonSize,
    this.nowMillis,
  });

  /// 每课时卡数上限（v1 投影器 lessonSize=20 的 v2 对齐语义）：同一
  /// (section, unit, lesson) 组内按 cardId 稳定序切片，part = 序号 ~/ size + 1。
  static const int defaultLessonSize = 20;

  final OfficialAnkiEngine engine;
  final OfficialAnkiDatabase catalog;
  final CourseDatabase course;
  final String profileId;
  final int lessonSize;
  final int Function()? nowMillis;

  /// 跨 isolate 读用 [catalog.filePath]——offload 连接必须与调用方看到
  /// 的是同一个库（内存库 / 测试 catalog 一律回落本 isolate 直读）。

  /// K11「重建中」占位信号（进程内、无持久状态——视图本身无状态）。
  static final ValueNotifier<bool> rebuilding = ValueNotifier<bool>(false);

  /// 宿主环境不支持 isolate 内开 sqlite（如测试宿主缺原生库解析）时
  /// 置位——一次失败永久回落 inline，不再每趟刷警告。
  static bool _isolateReadBroken = false;

  int get _now => nowMillis?.call() ?? DateTime.now().millisecondsSinceEpoch;

  /// 账本侧的大头读（每 source 全量卡行物化）尽量移出 UI isolate：
  /// 在 spawn 出的 isolate 里开第二条 catalog 连接读完再传回。失败
  /// （宿主不支持 / 并发冲突）回落本 isolate 直读，语义不变。
  Future<Map<String, List<OfficialAnkiCardDescriptor>>> _readCardsBySource(
    OfficialAnkiSourceDao dao,
    List<String> sourceIds,
  ) async {
    final path = catalog.filePath;
    if (path == null || sourceIds.isEmpty || _isolateReadBroken) {
      return {for (final id in sourceIds) id: dao.listCards(id)};
    }
    try {
      return await Isolate.run(() => _readCardsFromCatalog(path, sourceIds));
    } catch (error) {
      _isolateReadBroken = true;
      officialAnkiV2Log(
        'offloaded catalog read failed, inline fallback: $error',
        warning: true,
      );
      return {for (final id in sourceIds) id: dao.listCards(id)};
    }
  }

  static Map<String, List<OfficialAnkiCardDescriptor>> _readCardsFromCatalog(
      String catalogPath, List<String> sourceIds) {
    final db = OfficialAnkiDatabase.file(catalogPath);
    try {
      final dao = OfficialAnkiSourceDao(db);
      return {for (final id in sourceIds) id: dao.listCards(id)};
    } finally {
      db.close();
    }
  }

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
      final sources = dao.listV2Sources(profileId, states: {'active'});
      if (cancelToken?.isCancelled ?? false) {
        return _result(sources.length, 0, started, cancelled: true);
      }
      // Collection 输入：牌组树（deckId → '::' 路径段）。单次 RPC。
      final deckPaths = _deckPaths(await engine.listDeckTree());
      final topDeckIdByName = _topDeckIdByName(deckPaths);

      // 账本输入：每个 source 的所有权清单——尽量在 spawn isolate 里
      // 读（B1），全量物化不再占 UI isolate。
      final cardsBySource = await _readCardsBySource(
        dao,
        [for (final source in sources) source.sourceId],
      );

      // 配置区输入：出现过的顶层牌组的放置决策（数量 = 顶层牌组数）。
      final topDeckIds = <int>{
        for (final cards in cardsBySource.values)
          for (final card in cards)
            if (_topDeckId(card.deckId, deckPaths, topDeckIdByName)
                case final id?)
              id,
      };
      final placements = await decisions.readDeckPlacements(topDeckIds);

      final rowsBySource = <String, List<OfficialAnkiV2ViewRow>>{};
      for (final source in sources) {
        if (cancelToken?.isCancelled ?? false) break;
        final mapping = await decisions.readImportMapping(source.sourceId);
        rowsBySource[source.sourceId] = _rowsFor(
          source: source,
          cards: cardsBySource[source.sourceId] ??
              const <OfficialAnkiCardDescriptor>[],
          deckPaths: deckPaths,
          topDeckIdByName: topDeckIdByName,
          placements: placements,
          mapping: mapping,
        );
      }
      if (cancelToken?.isCancelled ?? false) {
        return _result(sources.length, 0, started, cancelled: true);
      }
      // D2：按 source 分组换页——同一事务内先删已不在 active 集合的
      // 残留行，再逐 source DELETE+INSERT；live 集合是权威清单。
      await store.replaceScoped(
        liveSourceIds: {for (final source in sources) source.sourceId},
        rowsBySource: rowsBySource,
        rebuiltAtMillis: _now,
      );
      // C6：section/lesson 计数直接从内存 rows 聚合，不再回查视图。
      var rowCount = 0;
      final sectionIds = <String>{};
      final lessonIds = <String>{};
      for (final rows in rowsBySource.values) {
        rowCount += rows.length;
        for (final row in rows) {
          sectionIds.add(row.sectionId);
          lessonIds.add(row.lessonId);
        }
      }
      officialAnkiV2Log(
        'view rebuild: ${sources.length} sources, $rowCount rows, '
        '${_now - started}ms',
      );
      return _result(
        sources.length,
        rowCount,
        started,
        sectionCount: sectionIds.length,
        lessonCount: lessonIds.length,
      );
    } finally {
      rebuilding.value = false;
    }
  }

  /// D2：只重建单个 source 的视图行——commit 成功路径用：本次导入只可能
  /// 改变这个 source 的行；其它 live source 的行保持不动，已不在 active
  /// 集合的 source 残留顺手清掉。与全量 rebuild 同一事务原子性。
  Future<OfficialAnkiV2ViewRebuildResult> rebuildSource(
    String sourceId, {
    OfficialAnkiV2ViewRebuildCancelToken? cancelToken,
  }) async {
    final started = _now;
    final dao = OfficialAnkiSourceDao(catalog);
    final decisions = OfficialAnkiV2DecisionStore(engine);
    final store = OfficialAnkiV2ViewStore(course);
    rebuilding.value = true;
    try {
      final active = dao.listV2Sources(profileId, states: {'active'});
      final liveSourceIds = {for (final s in active) s.sourceId};
      if (cancelToken?.isCancelled ?? false) {
        return _result(0, 0, started, cancelled: true);
      }
      final deckPaths = _deckPaths(await engine.listDeckTree());
      final topDeckIdByName = _topDeckIdByName(deckPaths);
      OfficialAnkiSourceRow? source;
      for (final row in active) {
        if (row.sourceId == sourceId) {
          source = row;
          break;
        }
      }
      final rowsBySource = <String, List<OfficialAnkiV2ViewRow>>{};
      if (source != null) {
        final cards = (await _readCardsBySource(dao, [sourceId]))[sourceId] ??
            const <OfficialAnkiCardDescriptor>[];
        if (cancelToken?.isCancelled ?? false) {
          return _result(0, 0, started, cancelled: true);
        }
        final topDeckIds = <int>{
          for (final card in cards)
            if (_topDeckId(card.deckId, deckPaths, topDeckIdByName)
                case final id?)
              id,
        };
        final placements = await decisions.readDeckPlacements(topDeckIds);
        final mapping = await decisions.readImportMapping(sourceId);
        rowsBySource[sourceId] = _rowsFor(
          source: source,
          cards: cards,
          deckPaths: deckPaths,
          topDeckIdByName: topDeckIdByName,
          placements: placements,
          mapping: mapping,
        );
      }
      if (cancelToken?.isCancelled ?? false) {
        return _result(0, 0, started, cancelled: true);
      }
      await store.replaceScoped(
        liveSourceIds: liveSourceIds,
        rowsBySource: rowsBySource,
        rebuiltAtMillis: _now,
      );
      final rowCount = rowsBySource[sourceId]?.length ?? 0;
      officialAnkiV2Log(
        'view rebuild (scoped $sourceId): $rowCount rows, '
        '${_now - started}ms',
      );
      return _result(
        source == null ? 0 : 1,
        rowCount,
        started,
        sectionCount: await store.distinctSectionCount(),
        lessonCount: await store.distinctLessonCount(),
      );
    } finally {
      rebuilding.value = false;
    }
  }

  /// 单 source 的行构建：deck 路径 → 放置键 + 呈现 kind，再按组切片。
  List<OfficialAnkiV2ViewRow> _rowsFor({
    required OfficialAnkiSourceRow source,
    required List<OfficialAnkiCardDescriptor> cards,
    required Map<int, List<String>> deckPaths,
    required Map<String, int> topDeckIdByName,
    required Map<int, OfficialAnkiV2PlacementDecision> placements,
    required OfficialAnkiV2MappingDecision? mapping,
  }) {
    final kindsByNotetype = _kindsByNotetype(mapping);
    final skipped = mapping?.notetypeIdsSkipped ?? const <int>{};
    final excludedDecks = mapping?.excludedDeckIds ?? const <int>{};
    // 牌组路径 → 放置键（section/unit/lesson）。lessonId 不在此定：
    // 同组卡按 cardId 稳定序切片后再定 part（见 _chunkedRows）。
    final placed = <_PlacedCard>[];
    for (final card in cards) {
      final path = deckPaths[card.deckId] ?? const <String>[];
      final topDeckId = _topDeckId(card.deckId, deckPaths, topDeckIdByName);
      // 用户明确跳过的 notetype 不进课程树（与 v1 映射语义一致）。
      if (card.notetypeId != null && skipped.contains(card.notetypeId)) {
        continue;
      }
      if (excludedDecks.contains(card.deckId)) continue;
      placed.add(_PlacedCard(
        card: card,
        placement: _place(source.sourceId, path, placements[topDeckId]),
        presentationKind: kindsByNotetype[card.notetypeId ?? -1] ?? 'flip',
      ));
    }
    return _chunkedRows(source, placed);
  }

  OfficialAnkiV2ViewRebuildResult _result(
    int sourceCount,
    int rowCount,
    int started, {
    bool cancelled = false,
    int sectionCount = 0,
    int lessonCount = 0,
  }) {
    return OfficialAnkiV2ViewRebuildResult(
      sourceCount: sourceCount,
      rowCount: rowCount,
      elapsedMillis: _now - started,
      cancelled: cancelled,
      sectionCount: sectionCount,
      lessonCount: lessonCount,
    );
  }

  /// 同 (section, unit, lesson) 组内按 cardId 稳定序每 [lessonSize] 张切
  /// 一片：part = 序号 ~/ size + 1。组不超片长时 part=1，lessonId 与旧
  /// 「一牌组一路径 = 一课时」派生完全一致（小牌组零迁移影响）。
  List<OfficialAnkiV2ViewRow> _chunkedRows(
    OfficialAnkiSourceRow source,
    List<_PlacedCard> placed,
  ) {
    final size = lessonSize < 1 ? 1 : lessonSize;
    final byGroup = <String, List<_PlacedCard>>{};
    for (final entry in placed) {
      final groupKey = [
        entry.placement.sectionKey,
        entry.placement.unitKey,
        entry.placement.lessonKey,
      ].join('\u001f');
      byGroup.putIfAbsent(groupKey, () => []).add(entry);
    }
    final rows = <OfficialAnkiV2ViewRow>[];
    for (final groupEntry in byGroup.entries) {
      final group = groupEntry.value
        ..sort((a, b) => a.card.cardId.compareTo(b.card.cardId));
      for (var i = 0; i < group.length; i++) {
        final placedCard = group[i];
        final placement = placedCard.placement;
        rows.add(OfficialAnkiV2ViewRow(
          sourceId: source.sourceId,
          cardId: placedCard.card.cardId,
          noteId: placedCard.card.noteId,
          deckId: placedCard.card.deckId,
          wordId: officialAnkiWordId(
            profileId: profileId,
            cardId: placedCard.card.cardId,
          ),
          sectionKey: placement.sectionKey,
          sectionId: placement.sectionId,
          unitId: placement.unitId,
          lessonId: officialAnkiLessonId(
            sourceId: source.sourceId,
            groupKey: groupEntry.key,
            part: (i ~/ size) + 1,
          ),
          lessonKey: placement.lessonKey,
          presentationKind: placedCard.presentationKind,
          sourceHash: source.sourceHash,
        ));
      }
    }
    return rows;
  }

  /// deckId → 名字路径（'A::B::C' 拆段）。
  static Map<int, List<String>> _deckPaths(List<OfficialAnkiDeckNode> tree) {
    return {
      for (final node in tree) node.deckId: node.name.split('::'),
    };
  }

  /// 顶层牌组名 → deckId 的查找表：一次构建 O(牌组数)，替代每卡
  /// 线性扫 deckPaths 的 O(卡数×牌组数)（B1）。
  static Map<String, int> _topDeckIdByName(Map<int, List<String>> deckPaths) {
    return {
      for (final entry in deckPaths.entries)
        if (entry.value.length == 1) entry.value.first: entry.key,
    };
  }

  /// 路径首段对应的顶层牌组 id（放置决策按顶层牌组落键）。
  static int? _topDeckId(
    int deckId,
    Map<int, List<String>> deckPaths,
    Map<String, int> topDeckIdByName,
  ) {
    final path = deckPaths[deckId];
    if (path == null || path.isEmpty) return null;
    return topDeckIdByName[path.first];
  }

  /// 放置决策：覆盖优先（D2 用户决策），否则按 deck 路径默认派生——
  /// 第一段 = section、第二段 = unit、末段 = lesson；单段牌组三级同段。
  /// lessonId 由 [_chunkedRows] 切片后生成。
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
      unitKey: unitKey,
      lessonKey: lessonKey,
    );
  }

  /// notetype → 主呈现 kind（依据识别原型与 enabledKinds 决策）。
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
        final map = entry.value as Map;
        final archetypeStr = map['archetype'] as String?;
        final rawKinds = map['enabledKinds'];
        final enabled = rawKinds is List
            ? rawKinds.map((e) => '$e').toSet()
            : const <String>{};
        out[id] = _resolvePrimaryKind(
          archetypeStr: archetypeStr,
          enabledKinds: enabled,
        );
      }
      return out;
    } catch (_) {
      return const {};
    }
  }

  static String _resolvePrimaryKind({
    required String? archetypeStr,
    required Set<String> enabledKinds,
  }) {
    final archetype = CardArchetype.values.firstWhere(
      (a) => a.name == archetypeStr,
      orElse: () => CardArchetype.basicPair,
    );
    return switch (archetype) {
      CardArchetype.choice => enabledKinds.contains('multipleChoice')
          ? 'multipleChoice'
          : (enabledKinds.contains('multiSelect')
              ? 'multiSelect'
              : (enabledKinds.contains('flip') ? 'flip' : 'canonicalLink')),
      CardArchetype.cloze =>
        enabledKinds.contains('fillBlank') ? 'fillBlank' : 'canonicalLink',
      CardArchetype.audioFirst => enabledKinds.contains('listenPick')
          ? 'listenPick'
          : (enabledKinds.contains('flip') ? 'flip' : 'canonicalLink'),
      CardArchetype.typeIn => enabledKinds.contains('typeAnswer')
          ? 'typeAnswer'
          : (enabledKinds.contains('flip') ? 'flip' : 'canonicalLink'),
      CardArchetype.richHtml => 'canonicalLink',
      CardArchetype.basicPair => enabledKinds.contains('flip')
          ? 'flip'
          : (enabledKinds.contains('showWord') ? 'showWord' : 'canonicalLink'),
    };
  }
}

class _PlacedCard {
  const _PlacedCard({
    required this.card,
    required this.placement,
    required this.presentationKind,
  });

  final OfficialAnkiCardDescriptor card;
  final _Placement placement;
  final String presentationKind;
}

class _Placement {
  const _Placement({
    required this.sectionKey,
    required this.sectionId,
    required this.unitId,
    required this.unitKey,
    required this.lessonKey,
  });

  final String sectionKey;
  final String sectionId;
  final String unitId;
  final String unitKey;
  final String lessonKey;
}
