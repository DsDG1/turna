import 'package:turna/application/anki_official/official_anki_composition.dart';
import 'package:turna/application/anki_official/storage/official_anki_database.dart';
import 'package:turna/application/anki_official/storage/official_anki_source_dao.dart';
import 'package:turna/courses/course_loader.dart';
import 'package:turna/domain/course/lesson.dart';
import 'package:turna/domain/course/lesson_content.dart';
import 'package:turna/domain/course/section.dart';
import 'package:turna/domain/course/unit.dart';
import 'package:turna/domain/repositories/i_official_anki_v2_view_store.dart';

/// B6：v2 课程树读面（ADR 0043）。
///
/// - 课程树壳从 `anki_course_tree_view` 长出来（与 v1 投影片壳并存，
///   两代数据同时可见）；
/// - 目录条目按「视图 + 账本 active」合成（retiring 即刻消失）；
/// - 复习链课时→卡映射走视图（lesson card index 的 v2 分支）。
///
/// 课程切换 = 改一个配置区决策键（`turna.course.scope`，由
/// CourseProvider.setScope 写穿）+ 视图过滤——不再有跨库状态机
/// （Step 1 发现 #2 的 v2 答复）。
class OfficialAnkiV2CourseRead {
  OfficialAnkiV2CourseRead({required this.catalog, required this.viewStore});

  final OfficialAnkiDatabase catalog;
  final IOfficialAnkiV2ViewStore viewStore;

  /// catalog/viewStore 可得 + 视图有内容时返回 true；任何一步不可用都
  /// 回落 v1 读面。
  static Future<bool> get enabled {
    final catalog = OfficialAnkiCompositionRoot.readOnlyCatalog;
    IOfficialAnkiV2ViewStore? viewStore;
    try {
      viewStore = CourseLoader.v2ViewStoreOrNull();
    } catch (_) {
      // best-effort 探测：视图仓储尚未装配属于冷启动路径。
      viewStore = null;
    }
    if (catalog == null || viewStore == null) return Future.value(false);
    return OfficialAnkiV2CourseRead(catalog: catalog, viewStore: viewStore)
        ._hasContent;
  }

  Future<bool> get _hasContent async {
    try {
      return await viewStore.isAvailable;
    } catch (_) {
      return false;
    }
  }

  /// 视图活跃 section id 集（`OfficialAnkiCourseEntry.filterShells` 的
  /// v2 供给）。section id 由重建器按 owned-tree 规则生成，天然通过
  /// `officialAnkiIsOwnedTreeId` 校验。
  Future<Set<String>> activeSectionIds() async {
    final summaries = await viewStore.sectionSummaries();
    final activeSources = _activeV2SourceIds();
    return {
      for (final summary in summaries)
        if (activeSources.contains(summary.sourceId)) summary.sectionId,
    };
  }

  Set<String> _activeV2SourceIds() {
    final profileId = OfficialAnkiCompositionRoot.locatorPaths?.profileId ??
        'profile-default-01';
    return {
      for (final source in OfficialAnkiSourceDao(catalog)
          .listV2Sources(profileId, states: {'active'}))
        source.sourceId,
    };
  }

  /// 视图合成的课程树壳（section → units（含课时壳））。
  ///
  /// 壳是展示层骨架；课时正文（练习 interactions）仍由既有装载管线按
  /// 课时 id 驱动，卡映射经 lesson card index 的 v2 分支解析——视图是
  /// 结构事实的唯一来源，正文派生自卡（D3：可重建）。
  Future<List<Section>> sectionShells() async {
    final summaries = await viewStore.sectionSummaries();
    if (summaries.isEmpty) return const [];
    final activeSources = _activeV2SourceIds();

    final unitNames = <String, String>{}; // unitId → 名
    final lessonNames = <String, String>{}; // lessonId → 名
    final lessonUnits = <String, String>{}; // lessonId → unitId
    final sectionUnits = <String, Set<String>>{}; // sectionId → unitIds
    // 树序：lesson_id/unit_id 都是 hash，不能当排序键；按组内首卡
    // （最小 card_id）排序，切分课时后 Lesson 1..N 才按卡序出现。
    final lessonOrder = <String, int>{}; // lessonId → 最小 cardId
    final unitOrder = <String, int>{}; // unitId → 最小 cardId
    for (final row in await viewStore.treeRows()) {
      if (!activeSources.contains(row.sourceId)) continue;
      unitNames.putIfAbsent(
        row.unitId,
        () => row.unitKey.isEmpty ? row.lessonKey : row.unitKey,
      );
      lessonNames.putIfAbsent(row.lessonId, () => row.lessonKey);
      lessonUnits.putIfAbsent(row.lessonId, () => row.unitId);
      lessonOrder.putIfAbsent(row.lessonId, () => row.cardId);
      unitOrder.putIfAbsent(row.unitId, () => row.cardId);
      sectionUnits.putIfAbsent(row.sectionId, () => <String>{}).add(row.unitId);
    }

    final sections = <Section>[];
    for (final summary in summaries) {
      if (!activeSources.contains(summary.sourceId)) continue;
      final units = <Unit>[];
      final unitIds = (sectionUnits[summary.sectionId] ?? const <String>{})
          .toList()
        ..sort((a, b) => (unitOrder[a] ?? 0).compareTo(unitOrder[b] ?? 0));
      for (final unitId in unitIds) {
        final unitLessonIds = [
          for (final entry in lessonUnits.entries)
            if (entry.value == unitId) entry.key,
        ]..sort((a, b) => (lessonOrder[a] ?? 0).compareTo(lessonOrder[b] ?? 0));
        // 同一 unit 内多个课时共用同一 lessonKey（切分的 part 片）时按
        // 卡序加 (n) 后缀，避免 N 个课时同名；不同 lessonKey 互不加缀。
        final namesInUnit = <String, int>{}; // lessonKey → 片数
        for (final lessonId in unitLessonIds) {
          final key = lessonNames[lessonId] ?? lessonId;
          namesInUnit[key] = (namesInUnit[key] ?? 0) + 1;
        }
        final partCounter = <String, int>{};
        final lessons = <Lesson>[];
        for (final lessonId in unitLessonIds) {
          final key = lessonNames[lessonId] ?? lessonId;
          final hasSiblings = (namesInUnit[key] ?? 0) > 1;
          final part = hasSiblings
              ? (partCounter[key] = (partCounter[key] ?? 0) + 1)
              : null;
          lessons.add(Lesson(
            id: lessonId,
            name: part == null ? key : '$key ($part)',
            content: const LessonContent(),
          ));
        }
        units.add(Unit(
            id: unitId, name: unitNames[unitId] ?? unitId, lessons: lessons));
      }
      sections.add(Section(
        id: summary.sectionId,
        name: summary.sectionKey,
        description: 'Official Anki · ${summary.sourceId}',
        level: 'OfficialAnki',
        units: units,
      ));
    }
    return sections;
  }

  /// 复习链课时→卡映射（lesson card index 的 v2 供给，稳定 card-id 序）。
  Future<List<({String wordId, int cardId, String sourceId})>>
      lessonCardEntriesForLesson(String lessonId) async {
    final rows = await viewStore.rowsForLesson(lessonId);
    final activeSources = _activeV2SourceIds();
    return [
      for (final row in rows)
        if (activeSources.contains(row.sourceId))
          (wordId: row.wordId, cardId: row.cardId, sourceId: row.sourceId),
    ];
  }

  /// 该课时是否由 v2 视图供給（lesson card index 的分叉判定）。
  Future<bool> isV2Lesson(String lessonId) async {
    final rows = await viewStore.rowsForLesson(lessonId);
    return rows.isNotEmpty;
  }
}
