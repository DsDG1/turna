// Flutter imports:
import 'package:flutter/foundation.dart';

// Project imports:
import 'package:turna/application/course_provider.dart';
import 'package:turna/application/progress_provider.dart';
import 'package:turna/domain/course/lesson.dart';
import 'package:turna/domain/course/section.dart';
import 'package:turna/domain/course/sub_lesson_summary.dart';
import 'package:turna/domain/course/unit.dart';
import 'package:turna/l10n/app_strings.dart';
import 'package:turna/views/widgets/directory_rows.dart';

/// 课时行的复习注意标记（due = 该课有词待复习，weak = 有薄弱词）。
enum LessonAttention { none, due, weak }

String? lessonAttentionText(LessonAttention attention) => switch (attention) {
      LessonAttention.due => AppStrings.coursesLessonDueMeta,
      LessonAttention.weak => AppStrings.coursesLessonWeakMeta,
      LessonAttention.none => null,
    };

/// 旅程线上的可玩节点引用：平面课（subLessonId 为 null）或多子课组内
/// 的一节子课。
typedef JourneyNode = ({String lessonId, String? subLessonId});

/// 揭示控制器与旅程行共用的 section/unit 键：State 的静态包装与 item
/// 类（顶层）都从这里取。
String journeyUnitKey(String sectionId, String unitId) => '$sectionId/$unitId';

/// 单元内已完成课数（progress 缺席时为 0）。单元条与章节头共用。
int countCompletedLessons(ProgressProvider? progress, Unit unit) {
  if (progress == null) return 0;
  var completed = 0;
  for (final lesson in unit.lessons) {
    if (progress.isLessonCompleted(lesson.id)) completed++;
  }
  return completed;
}

/// 节点完成态。整课完成（含早于子课节点追踪的旧记录）⇒ 其全部子课
/// 节点视为完成；平面节点只看整课记录。
bool courseTreeNodeCompleted(
  ProgressProvider progress,
  String lessonId,
  String? subLessonId,
) {
  if (progress.isLessonCompleted(lessonId)) return true;
  return subLessonId != null &&
      progress.isSubLessonCompleted(lessonId, subLessonId);
}

/// 节点旅程状态：完成 / 当前（下一个）/ 可学 / 锁定。
DirectoryNodeStatus courseTreeNodeStatus({
  required bool completed,
  required bool isNextUp,
  required bool isFirst,
  required bool previousCompleted,
}) {
  if (completed) return DirectoryNodeStatus.done;
  if (isNextUp) return DirectoryNodeStatus.current;
  if (isFirst || previousCompleted) return DirectoryNodeStatus.todo;
  return DirectoryNodeStatus.locked;
}

/// 多子课的课返回其 L1 子课摘要；拆组门槛 ≥2 与播放侧
/// `LessonViewModel._targetedSubLessonSession` 保持一致（1 节的课播放
/// 本就是单段，不拆）。
List<SubLessonSummary>? courseTreeSubLessonNodes(Lesson lesson) {
  final subs = lesson.subLessonSummaries;
  return subs.length >= 2 ? subs : null;
}

int courseTreeLessonRowCount(Lesson lesson) {
  final subs = courseTreeSubLessonNodes(lesson);
  return subs == null ? 1 : subs.length + 1;
}

bool courseTreeIsNode(
  JourneyNode? node,
  String lessonId,
  String? subLessonId,
) =>
    node != null &&
    node.lessonId == lessonId &&
    node.subLessonId == subLessonId;

/// 单元内第一个未完成的可玩节点（节点粒度）。无 progress 时返回首
/// 节点——与旧的「无进度从第一课开始」行为一致。
JourneyNode? courseTreeNextUpNode(ProgressProvider? progress, Unit unit) {
  for (final lesson in unit.lessons) {
    final subs = courseTreeSubLessonNodes(lesson);
    if (subs == null) {
      if (progress == null || !courseTreeNodeCompleted(progress, lesson.id, null)) {
        return (lessonId: lesson.id, subLessonId: null);
      }
      continue;
    }
    for (final sub in subs) {
      if (progress == null ||
          !courseTreeNodeCompleted(progress, lesson.id, sub.id)) {
        return (lessonId: lesson.id, subLessonId: sub.id);
      }
    }
  }
  return null;
}

/// 整个章节的第一个未完成节点（继续条的目标）。无 progress 时返回
/// 首单元首节点。
({Unit unit, Lesson lesson, SubLessonSummary? sub})? courseTreeSectionNextUpNode(
  ProgressProvider? progress,
  Section section,
) {
  for (final unit in section.units) {
    final node = courseTreeNextUpNode(progress, unit);
    if (node == null) continue;
    for (final lesson in unit.lessons) {
      if (lesson.id != node.lessonId) continue;
      SubLessonSummary? sub;
      if (node.subLessonId != null) {
        for (final candidate in lesson.subLessonSummaries) {
          if (candidate.id == node.subLessonId) sub = candidate;
        }
      }
      return (unit: unit, lesson: lesson, sub: sub);
    }
  }
  return null;
}

class CourseTreeSnapshot {
  final bool hasSections;
  final bool isLoaded;
  final String? currentSectionId;
  final Section? section;
  final SectionLoadState loadState;
  final Object? error;

  const CourseTreeSnapshot({
    required this.hasSections,
    required this.isLoaded,
    required this.currentSectionId,
    required this.section,
    required this.loadState,
    required this.error,
  });

  factory CourseTreeSnapshot.from(CourseProvider provider) {
    final currentSectionId = provider.currentSectionId;
    final loadState = currentSectionId == null
        ? SectionLoadState.initial
        : provider.sectionLoadState(currentSectionId);
    return CourseTreeSnapshot(
      hasSections: provider.sections.isNotEmpty,
      isLoaded: provider.isLoaded,
      currentSectionId: currentSectionId,
      section: provider.currentSection,
      loadState: loadState,
      error: currentSectionId == null
          ? null
          : provider.sectionLoadError(currentSectionId),
    );
  }

  static bool shouldRebuild(
    CourseTreeSnapshot previous,
    CourseTreeSnapshot next,
  ) =>
      previous.hasSections != next.hasSections ||
      previous.isLoaded != next.isLoaded ||
      previous.currentSectionId != next.currentSectionId ||
      !identical(previous.section, next.section) ||
      previous.loadState != next.loadState ||
      previous.error != next.error;
}

sealed class CourseTreeItem {
  const CourseTreeItem();

  Key get key;

  /// 揭示动画控制器键（section/unit）。
  String get revealControllerKey;

  /// 揭示交错序号（单元内的旅程行序）。
  int get revealIndex;

  /// 揭示渐变键的稳定尾巴（平面课 = 课 id；沿用 `lesson-reveal-*` 键
  /// 契约，测试按它找 FadeTransition）。
  String get revealTag;
}

class CourseTreeLessonItem extends CourseTreeItem {
  final String sectionId;
  final Unit unit;
  final Lesson lesson;
  final LessonAttention attention;
  final bool isLast;
  @override
  final int revealIndex;
  final bool isNextUp;

  /// 旅程线上紧邻的前一节点（跨组时为上一组最后一节子课），驱动解锁
  /// 判定；单元首行为 null。
  final JourneyNode? previousNode;

  const CourseTreeLessonItem({
    required this.sectionId,
    required this.unit,
    required this.lesson,
    required this.attention,
    required this.isLast,
    required this.revealIndex,
    required this.previousNode,
    this.isNextUp = false,
  });

  @override
  Key get key => ValueKey<String>('lesson-$sectionId-${lesson.id}');

  @override
  String get revealControllerKey => journeyUnitKey(sectionId, unit.id);

  @override
  String get revealTag => lesson.id;
}

/// 多子课的课的组头行（ADR 0064）：课级归属标识，不可点——进入与重玩
/// 都点子课行。
class CourseTreeSubLessonGroupHeaderItem extends CourseTreeItem {
  final String sectionId;
  final Unit unit;
  final Lesson lesson;
  final List<SubLessonSummary> subs;
  final LessonAttention attention;

  /// 恒为 false：组内必有子课行，组头永不收底。
  final bool isLast;
  @override
  final int revealIndex;
  final JourneyNode? previousNode;

  const CourseTreeSubLessonGroupHeaderItem({
    required this.sectionId,
    required this.unit,
    required this.lesson,
    required this.subs,
    required this.attention,
    required this.isLast,
    required this.revealIndex,
    required this.previousNode,
  });

  @override
  Key get key => ValueKey<String>('lessongroup-$sectionId-${lesson.id}');

  @override
  String get revealControllerKey => journeyUnitKey(sectionId, unit.id);

  @override
  String get revealTag => 'group-${lesson.id}';
}

/// 一节子课的行：点击进入只玩这一节的独立会话（ADR 0064）。
class CourseTreeSubLessonItem extends CourseTreeItem {
  final String sectionId;
  final Unit unit;
  final Lesson lesson;
  final SubLessonSummary sub;
  final int subIndex;
  final int subCount;
  final bool isLast;
  @override
  final int revealIndex;
  final bool isNextUp;
  final JourneyNode? previousNode;

  const CourseTreeSubLessonItem({
    required this.sectionId,
    required this.unit,
    required this.lesson,
    required this.sub,
    required this.subIndex,
    required this.subCount,
    required this.isLast,
    required this.revealIndex,
    required this.previousNode,
    this.isNextUp = false,
  });

  @override
  Key get key => ValueKey<String>('lesson-$sectionId-${lesson.id}-${sub.id}');

  @override
  String get revealControllerKey => journeyUnitKey(sectionId, unit.id);

  @override
  String get revealTag => '${lesson.id}-${sub.id}';
}

class CourseTreeStatusProjection {
  final Set<String> dueLessonIds;
  final Set<String> weakLessonIds;
  final Map<String, int> dueCountByUnit;
  final Map<String, int> weakCountByUnit;
  final bool officialTreeUnavailable;

  const CourseTreeStatusProjection({
    required this.dueLessonIds,
    required this.weakLessonIds,
    required this.dueCountByUnit,
    required this.weakCountByUnit,
    this.officialTreeUnavailable = false,
  });

  LessonAttention attentionForLesson(String lessonId) {
    if (dueLessonIds.contains(lessonId)) return LessonAttention.due;
    if (weakLessonIds.contains(lessonId)) return LessonAttention.weak;
    return LessonAttention.none;
  }
}
