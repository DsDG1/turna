import 'package:turna/application/anki_official/official_anki_composition.dart';
import 'package:turna/application/anki_official/official_anki_feature_flags.dart';
import 'package:turna/application/anki_official/storage/official_anki_database.dart';
import 'package:turna/application/anki_official/storage/official_anki_source_dao.dart';
import 'package:turna/application/anki_official/v2/official_anki_v2_view_store.dart';
import 'package:turna/courses/course_loader.dart';
import 'package:turna/data/course_database.dart'
    hide Section, Unit, Lesson, LessonContent;
import 'package:turna/domain/course/lesson.dart';
import 'package:turna/domain/course/lesson_content.dart';
import 'package:turna/domain/course/section.dart';
import 'package:turna/domain/course/unit.dart';

/// B6：v2 课程树读面（step4.md）。
///
/// flag 关（默认）时本类所有入口返回空/false，读面 = v1 原样——这是
/// 「v1 零回归」的结构保证。flag 开时：
/// - 课程树壳从 `anki_course_tree_view` 长出来（与 v1 投影片壳并存，
///   两代数据同时可见——回退语义的对称面：flag 只路由新导入）；
/// - 目录条目按「视图 + 账本 active」合成（retiring 即刻消失）；
/// - 复习链课时→卡映射走视图（lesson card index 的 v2 分支）。
///
/// 课程切换 = 改一个配置区决策键（`turna.course.scope`，由
/// CourseProvider.setScope 写穿）+ 视图过滤——不再有跨库状态机
/// （Step 1 发现 #2 的 v2 答复）。
class OfficialAnkiV2CourseRead {
  OfficialAnkiV2CourseRead({required this.catalog, required this.course});

  final OfficialAnkiDatabase catalog;
  final CourseDatabase course;

  static OfficialAnkiFeatureFlags Function() flagsOf =
      () => OfficialAnkiFeatureFlags.current;

  /// flag 开 + catalog/course 可得 + 视图有内容时返回 true；任何一步
  /// 不可用都回落 v1 读面。
  static Future<bool> get enabled {
    if (!flagsOf().allowsV2ImportChain) return Future.value(false);
    final catalog = OfficialAnkiCompositionRoot.readOnlyCatalog;
    CourseDatabase? course;
    try {
      course = CourseLoader.databaseOrNull();
    } catch (_) {
      course = null;
    }
    if (catalog == null || course == null) return Future.value(false);
    return OfficialAnkiV2CourseRead(catalog: catalog, course: course)
        ._hasContent;
  }

  Future<bool> get _hasContent async {
    try {
      return await OfficialAnkiV2ViewStore(course).isAvailable;
    } catch (_) {
      return false;
    }
  }

  /// 视图活跃 section id 集（`OfficialAnkiCourseEntry.filterShells` 的
  /// v2 供给）。section id 由重建器按 owned-tree 规则生成，天然通过
  /// `officialAnkiIsOwnedTreeId` 校验。
  Future<Set<String>> activeSectionIds() async {
    if (!flagsOf().allowsV2ImportChain) return const {};
    final summaries = await OfficialAnkiV2ViewStore(course).sectionSummaries();
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
    if (!flagsOf().allowsV2ImportChain) return const [];
    final store = OfficialAnkiV2ViewStore(course);
    final summaries = await store.sectionSummaries();
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
    for (final row in await _treeRows()) {
      if (!activeSources.contains(row.sourceId)) continue;
      unitNames.putIfAbsent(row.unitId, () => row.lessonKey);
      lessonNames.putIfAbsent(row.lessonId, () => row.lessonKey);
      lessonUnits.putIfAbsent(row.lessonId, () => row.unitId);
      lessonOrder.putIfAbsent(row.lessonId, () => row.cardId);
      unitOrder.putIfAbsent(row.unitId, () => row.cardId);
      sectionUnits
          .putIfAbsent(row.sectionId, () => <String>{})
          .add(row.unitId);
    }

    final sections = <Section>[];
    for (final summary in summaries) {
      if (!activeSources.contains(summary.sourceId)) continue;
      final units = <Unit>[];
      final unitIds = (sectionUnits[summary.sectionId] ?? const <String>{})
          .toList()
        ..sort((a, b) =>
            (unitOrder[a] ?? 0).compareTo(unitOrder[b] ?? 0));
      for (final unitId in unitIds) {
        final unitLessonIds = [
          for (final entry in lessonUnits.entries)
            if (entry.value == unitId) entry.key,
        ]..sort((a, b) =>
            (lessonOrder[a] ?? 0).compareTo(lessonOrder[b] ?? 0));
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
        units.add(Unit(id: unitId, name: unitNames[unitId] ?? unitId, lessons: lessons));
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

  Future<List<OfficialAnkiV2ViewRow>> _treeRows() async {
    try {
      final rows = await course.customSelect(
        'SELECT source_id, card_id, note_id, deck_id, word_id, section_key, '
        'section_id, unit_id, lesson_id, lesson_key, presentation_kind, '
        'source_hash, mapping_version FROM anki_course_tree_view '
        'ORDER BY source_id, section_id, unit_id, lesson_id, card_id',
      ).get();
      return [
        for (final row in rows)
          OfficialAnkiV2ViewRow(
            sourceId: row.read<String>('source_id'),
            cardId: row.read<int>('card_id'),
            noteId: row.read<int>('note_id'),
            deckId: row.read<int>('deck_id'),
            wordId: row.read<String>('word_id'),
            sectionKey: row.read<String>('section_key'),
            sectionId: row.read<String>('section_id'),
            unitId: row.read<String>('unit_id'),
            lessonId: row.read<String>('lesson_id'),
            lessonKey: row.read<String>('lesson_key'),
            presentationKind: row.read<String>('presentation_kind'),
            sourceHash: row.read<String>('source_hash'),
            mappingVersion: row.read<int>('mapping_version'),
          ),
      ];
    } catch (_) {
      return const [];
    }
  }

  /// 复习链课时→卡映射（lesson card index 的 v2 供给，稳定 card-id 序）。
  Future<List<({String wordId, int cardId, String sourceId})>>
      lessonCardEntriesForLesson(String lessonId) async {
    if (!flagsOf().allowsV2ImportChain) return const [];
    final rows = await OfficialAnkiV2ViewStore(course).rowsForLesson(lessonId);
    final activeSources = _activeV2SourceIds();
    return [
      for (final row in rows)
        if (activeSources.contains(row.sourceId))
          (wordId: row.wordId, cardId: row.cardId, sourceId: row.sourceId),
    ];
  }

  /// 该课时是否由 v2 视图供給（lesson card index 的分叉判定）。
  Future<bool> isV2Lesson(String lessonId) async {
    if (!flagsOf().allowsV2ImportChain) return false;
    final rows = await OfficialAnkiV2ViewStore(course).rowsForLesson(lessonId);
    return rows.isNotEmpty;
  }
}
