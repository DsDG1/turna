// Flutter imports:
import 'package:flutter/material.dart';

// Package imports:
import 'package:auto_route/auto_route.dart';
import 'package:provider/provider.dart';

// Project imports:
import 'package:turna/application/progress_provider.dart';
import 'package:turna/core/motion.dart';
import 'package:turna/core/spacing.dart';
import 'package:turna/core/text_styles.dart';
import 'package:turna/core/theme.dart';
import 'package:turna/domain/course/lesson.dart';
import 'package:turna/domain/course/section.dart';
import 'package:turna/domain/course/unit.dart';
import 'package:turna/l10n/app_strings.dart';
import 'package:turna/routing/routing.gr.dart';
import 'package:turna/views/courses/components/course_tree_models.dart';
import 'package:turna/views/courses/components/section_bottom_sheet.dart';
import 'package:turna/views/courses/components/section_visuals.dart';
import 'package:turna/views/widgets/directory_rows.dart';

typedef NavigateToLessonCallback = void Function(
  BuildContext context,
  Lesson lesson,
  String? subLessonId,
);

/// 平面课时行（监听自身及前驱节点完成态）。
class CourseTreeLessonTile extends StatelessWidget {
  const CourseTreeLessonTile({
    super.key,
    required this.item,
    required this.onNavigate,
  });

  final CourseTreeLessonItem item;
  final NavigateToLessonCallback onNavigate;

  @override
  Widget build(BuildContext context) {
    final lesson = item.lesson;
    return Selector<ProgressProvider,
        ({bool completed, bool previousCompleted})>(
      selector: (_, provider) => (
        completed: provider.isLessonCompleted(lesson.id),
        previousCompleted: item.previousNode != null &&
            courseTreeNodeCompleted(
              provider,
              item.previousNode!.lessonId,
              item.previousNode!.subLessonId,
            ),
      ),
      builder: (context, value, _) {
        final status = courseTreeNodeStatus(
          completed: value.completed,
          isNextUp: item.isNextUp,
          isFirst: item.previousNode == null,
          previousCompleted: value.previousCompleted,
        );
        // 复习注意态优先于「下一课」位置标记：待复习是行动信息，位置
        // 信息由状态环与底部继续条承担。
        final attentionText = lessonAttentionText(item.attention);
        final isNextUp = item.isNextUp && !value.completed;
        return DirectoryLessonRow(
          status: status,
          title: lesson.name,
          meta:
              attentionText ?? (isNextUp ? AppStrings.coursesNextLesson : null),
          metaEmphasized: attentionText != null || isNextUp,
          showDivider: !item.isLast,
          onTap: () => onNavigate(context, lesson, null),
        );
      },
    );
  }
}

/// 多子课组的组头容器（读取组内已完成子课数）。
class CourseTreeGroupHeaderTile extends StatelessWidget {
  const CourseTreeGroupHeaderTile({super.key, required this.item});

  final CourseTreeSubLessonGroupHeaderItem item;

  @override
  Widget build(BuildContext context) {
    final lesson = item.lesson;
    final subIds = [for (final sub in item.subs) sub.id];

    return Selector<ProgressProvider, int>(
      selector: (_, provider) => subIds
          .where((id) => courseTreeNodeCompleted(provider, lesson.id, id))
          .length,
      builder: (context, completedCount, _) => CourseTreeSubLessonGroupRow(
        lesson: lesson,
        completedCount: completedCount,
        subCount: item.subs.length,
        attention: item.attention,
      ),
    );
  }
}

/// 子课节点行（带芦苇缩进引导线，监听自身及前驱节点完成态）。
class CourseTreeSubLessonTile extends StatelessWidget {
  const CourseTreeSubLessonTile({
    super.key,
    required this.item,
    required this.onNavigate,
  });

  final CourseTreeSubLessonItem item;
  final NavigateToLessonCallback onNavigate;

  @override
  Widget build(BuildContext context) {
    final lesson = item.lesson;
    return Selector<ProgressProvider,
        ({bool completed, bool previousCompleted})>(
      selector: (_, provider) => (
        completed: courseTreeNodeCompleted(provider, lesson.id, item.sub.id),
        previousCompleted: item.previousNode != null &&
            courseTreeNodeCompleted(
              provider,
              item.previousNode!.lessonId,
              item.previousNode!.subLessonId,
            ),
      ),
      builder: (context, value, _) {
        final status = courseTreeNodeStatus(
          completed: value.completed,
          isNextUp: item.isNextUp,
          isFirst: false,
          previousCompleted: value.previousCompleted,
        );
        // 子课行：芦苇缩进线由外层容器画，行本体走目录行族。
        return Container(
          decoration: const BoxDecoration(
            border: Border(
              left: BorderSide(
                color: TurnaTheme.subLessonIndentGuide,
                width: 2,
              ),
            ),
          ),
          padding: const EdgeInsets.only(left: AppSpacing.md + 2),
          child: DirectorySubLessonRow(
            status: status,
            title: item.sub.name,
            meta: item.isNextUp && !value.completed
                ? AppStrings.coursesNextLesson
                : null,
            onTap: () => onNavigate(context, lesson, item.sub.id),
            showDivider: !item.isLast,
          ),
        );
      },
    );
  }
}

/// 轻量章节进度带：几何图标 + 章节名 + 细进度条；点击进章节切换。
class CourseTreeSectionHeadBand extends StatelessWidget {
  const CourseTreeSectionHeadBand({super.key, required this.section});

  final Section section;

  @override
  Widget build(BuildContext context) {
    final colors = SectionVisuals.colorsFor(section.id);

    return Selector<ProgressProvider, double>(
      selector: (_, progress) {
        var total = 0;
        var completed = 0;
        for (final unit in section.units) {
          for (final lesson in unit.lessons) {
            total++;
            if (progress.isLessonCompleted(lesson.id)) completed++;
          }
        }
        return total == 0 ? 0 : completed / total;
      },
      builder: (context, progressValue, _) => Padding(
        padding: const EdgeInsets.fromLTRB(
          AppSpacing.pageMargin,
          AppSpacing.xs,
          AppSpacing.pageMargin,
          AppSpacing.md,
        ),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: () => showSectionBottomSheet(context),
            borderRadius: BorderRadius.circular(TurnaTheme.radiusMedium),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
              child: Row(
                children: [
                  Container(
                    width: 32,
                    height: 32,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: colors.background,
                      borderRadius:
                          BorderRadius.circular(TurnaTheme.cardRadius),
                    ),
                    child: Icon(
                      SectionVisuals.iconFor(section.id),
                      size: 17,
                      color: colors.foreground,
                    ),
                  ),
                  const SizedBox(width: AppSpacing.md),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          section.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: AppTextStyles.sectionTitle(context)
                              .copyWith(fontSize: 16, height: 1.2),
                        ),
                        if ((section.level ?? '').trim().isNotEmpty) ...[
                          const SizedBox(height: AppSpacing.xs),
                          SectionLevelLabel(section.level),
                        ],
                        const SizedBox(height: AppSpacing.sm),
                        Semantics(
                          label: AppStrings.coursesSectionProgressSemantic(
                            (progressValue * 100).round(),
                          ),
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(2),
                            child: LinearProgressIndicator(
                              value: progressValue,
                              minHeight: 3,
                              backgroundColor: TurnaTheme.dividerBg(context),
                              valueColor: const AlwaysStoppedAnimation<Color>(
                                TurnaTheme.brandTeal,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  Icon(
                    Icons.expand_more_rounded,
                    size: 18,
                    color: TurnaTheme.textSecondaryColor(context),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// 吸顶单元条的 SliverPersistentHeader 适配。
class CourseTreeUnitStripDelegate extends SliverPersistentHeaderDelegate {
  CourseTreeUnitStripDelegate({
    required this.sectionId,
    required this.unit,
    required this.unitIndex,
    required this.dueLessonCount,
    required this.weakLessonCount,
    required this.expanded,
    required this.reduceMotion,
    required this.headerKey,
    required this.onToggle,
  });

  final String sectionId;
  final Unit unit;
  final int unitIndex;
  final int dueLessonCount;
  final int weakLessonCount;
  final bool expanded;
  final bool reduceMotion;
  final GlobalKey headerKey;
  final VoidCallback onToggle;

  static const double height = 54;

  @override
  double get minExtent => height;

  @override
  double get maxExtent => height;

  @override
  Widget build(
    BuildContext context,
    double shrinkOffset,
    bool overlapsContent,
  ) {
    return CourseTreeUnitStrip(
      key: headerKey,
      unitIndex: unitIndex,
      unit: unit,
      dueLessonCount: dueLessonCount,
      weakLessonCount: weakLessonCount,
      expanded: expanded,
      reduceMotion: reduceMotion,
      onToggle: onToggle,
      pinned: true,
    );
  }

  @override
  bool shouldRebuild(covariant CourseTreeUnitStripDelegate old) =>
      old.sectionId != sectionId ||
      old.unit != unit ||
      old.unitIndex != unitIndex ||
      old.expanded != expanded ||
      old.reduceMotion != reduceMotion ||
      old.headerKey != headerKey ||
      old.dueLessonCount != dueLessonCount ||
      old.weakLessonCount != weakLessonCount;
}

/// 单元条：统一两种状态的几何尺寸，以组间留白、序号块和细线分层；
/// 展开单元钉在目录顶部，只有当前焦点使用 teal 淡色底。
class CourseTreeUnitStrip extends StatelessWidget {
  const CourseTreeUnitStrip({
    required this.unitIndex,
    required this.unit,
    required this.dueLessonCount,
    required this.weakLessonCount,
    required this.expanded,
    required this.reduceMotion,
    required this.onToggle,
    this.pinned = false,
    super.key,
  });

  final int unitIndex;
  final Unit unit;
  final int dueLessonCount;
  final int weakLessonCount;
  final bool expanded;
  final bool reduceMotion;
  final VoidCallback onToggle;
  final bool pinned;

  @override
  Widget build(BuildContext context) {
    final hasAttention = dueLessonCount > 0 || weakLessonCount > 0;
    final attentionColor =
        dueLessonCount > 0 ? TurnaTheme.warning : TurnaTheme.brandSky;
    final duration = TurnaMotion.scaled(TurnaMotion.base, reduceMotion);
    final borderRadius = BorderRadius.circular(TurnaTheme.radiusMedium);

    // 完成计数响应课级进度记录——目录里每个单元条的 k/n 都要跟着走，
    // 不能只在整树重建时算一遍。
    return Selector<ProgressProvider, int>(
      selector: (_, progress) => countCompletedLessons(progress, unit),
      builder: (context, completedCount, _) => Material(
        color: pinned ? TurnaTheme.scaffoldBg(context) : Colors.transparent,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
          child: AnimatedContainer(
            duration: duration,
            curve: TurnaMotion.easeOut,
            decoration: BoxDecoration(
              color: expanded
                  ? TurnaTheme.brandTeal.withValues(alpha: 0.07)
                  : Colors.transparent,
              borderRadius: borderRadius,
              border: Border(
                bottom: BorderSide(color: TurnaTheme.dividerBg(context)),
              ),
            ),
            child: Semantics(
              label: '${unit.name}，$completedCount/${unit.lessons.length}',
              button: true,
              expanded: expanded,
              onTap: onToggle,
              excludeSemantics: true,
              child: InkWell(
                onTap: onToggle,
                borderRadius: borderRadius,
                child: SizedBox(
                  height: CourseTreeUnitStripDelegate.height - AppSpacing.sm,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: AppSpacing.pageMargin,
                    ),
                    child: Row(
                      children: [
                        AnimatedContainer(
                          width: 22,
                          height: 22,
                          alignment: Alignment.center,
                          duration: duration,
                          curve: TurnaMotion.easeOut,
                          decoration: BoxDecoration(
                            color: expanded
                                ? TurnaTheme.brandTeal
                                : TurnaTheme.brandTeal.withValues(alpha: 0.09),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: AnimatedDefaultTextStyle(
                            duration: duration,
                            curve: TurnaMotion.easeOut,
                            style: TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.w700,
                              color: expanded
                                  ? TurnaTheme.textOnPrimary
                                  : TurnaTheme.brandTeal,
                            ),
                            child: Text('$unitIndex'),
                          ),
                        ),
                        const SizedBox(width: AppSpacing.sm + 2),
                        Expanded(
                          child: AnimatedDefaultTextStyle(
                            duration: duration,
                            curve: TurnaMotion.easeOut,
                            style: AppTextStyles.bodyText(context).copyWith(
                              fontSize: 14,
                              fontWeight:
                                  expanded ? FontWeight.w700 : FontWeight.w600,
                            ),
                            child: Text(
                              unit.name,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ),
                        if (hasAttention) ...[
                          const SizedBox(width: AppSpacing.sm),
                          Container(
                            width: 6,
                            height: 6,
                            decoration: BoxDecoration(
                              color: attentionColor,
                              shape: BoxShape.circle,
                            ),
                          ),
                        ],
                        const SizedBox(width: AppSpacing.sm),
                        Text(
                          '$completedCount/${unit.lessons.length}',
                          style: TextStyle(
                            fontSize: 12,
                            color: expanded
                                ? TurnaTheme.brandTeal
                                : TurnaTheme.textSecondaryColor(context),
                            fontFeatures: const [
                              FontFeature.tabularFigures(),
                            ],
                          ),
                        ),
                        const SizedBox(width: AppSpacing.xs + 2),
                        AnimatedRotation(
                          turns: expanded ? 0.5 : 0,
                          duration: duration,
                          curve: TurnaMotion.easeOut,
                          child: Icon(
                            Icons.keyboard_arrow_down_rounded,
                            size: 18,
                            color: expanded
                                ? TurnaTheme.brandTeal
                                : TurnaTheme.textSecondaryColor(context),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// 多子课的课的组头行（ADR 0064）：课级归属与进度，不可点——进入与重玩
/// 都点子课行。
class CourseTreeSubLessonGroupRow extends StatelessWidget {
  const CourseTreeSubLessonGroupRow({
    super.key,
    required this.lesson,
    required this.completedCount,
    required this.subCount,
    required this.attention,
  });

  final Lesson lesson;
  final int completedCount;
  final int subCount;
  final LessonAttention attention;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm + 2),
      child: Row(
        children: [
          Expanded(
            child: Text(
              lesson.name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: AppTextStyles.bodyText(context).copyWith(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: TurnaTheme.textPrimaryColor(context),
              ),
            ),
          ),
          if (attention != LessonAttention.none) ...[
            const SizedBox(width: AppSpacing.sm),
            Text(
              lessonAttentionText(attention) ?? '',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: attention == LessonAttention.due
                    ? TurnaTheme.warning
                    : TurnaTheme.brandSky,
              ),
            ),
          ],
          const SizedBox(width: AppSpacing.sm),
          Text(
            '$completedCount/$subCount',
            style: TextStyle(
              fontSize: 12,
              color: TurnaTheme.textSecondaryColor(context),
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
        ],
      ),
    );
  }
}

/// 底部常驻继续条：下一个可学节点 + 单一主行动。列表再长，继续学习
/// 始终可达（P1 紧凑稿评审确认）。
class CourseTreeResumeBar extends StatelessWidget {
  const CourseTreeResumeBar({super.key, required this.section});

  final Section section;

  @override
  Widget build(BuildContext context) {
    return Selector<ProgressProvider,
        ({String lessonId, String? subLessonId, String name})?>(
      selector: (_, progress) {
        final next = courseTreeSectionNextUpNode(progress, section);
        if (next == null) return null;
        return (
          lessonId: next.lesson.id,
          subLessonId: next.sub?.id,
          name: next.sub?.name ?? next.lesson.name,
        );
      },
      builder: (context, next, _) {
        if (next == null) return const SizedBox.shrink();
        return Padding(
          padding: EdgeInsets.only(
            left: AppSpacing.pageMargin,
            right: AppSpacing.pageMargin,
            top: AppSpacing.sm + 2,
            // 外层 HomePage 已把底部导航的 overlay 余量注入 MediaQuery。
            bottom: AppSpacing.xs + MediaQuery.paddingOf(context).bottom,
          ),
          child: Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: () => context.router.push(
                NewLessonRoute(
                  lessonId: next.lessonId,
                  subLessonId: next.subLessonId,
                ),
              ),
              borderRadius: BorderRadius.circular(TurnaTheme.cardRadius),
              child: Container(
                padding: const EdgeInsets.all(AppSpacing.md - 1),
                decoration: BoxDecoration(
                  color: TurnaTheme.cardBg(context),
                  borderRadius: BorderRadius.circular(TurnaTheme.cardRadius),
                  border: Border.all(
                    color: TurnaTheme.brandTeal.withValues(alpha: 0.40),
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: TurnaTheme.brandNavy.withValues(alpha: 0.12),
                      blurRadius: 22,
                      offset: const Offset(0, 10),
                    ),
                  ],
                ),
                child: Row(
                  children: [
                    Container(
                      width: 38,
                      height: 38,
                      alignment: Alignment.center,
                      decoration: const BoxDecoration(
                        color: TurnaTheme.brandTeal,
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(
                        Icons.arrow_right_alt_rounded,
                        size: 20,
                        color: TurnaTheme.textOnPrimary,
                      ),
                    ),
                    const SizedBox(width: AppSpacing.md),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            AppStrings.coursesResumeCap,
                            style: const TextStyle(
                              fontSize: 11,
                              letterSpacing: 0.6,
                              fontWeight: FontWeight.w600,
                              color: TurnaTheme.brandTeal,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            next.name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: AppTextStyles.bodyText(context).copyWith(
                              fontSize: 15,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    ),
                    Icon(
                      Icons.chevron_right_rounded,
                      size: 18,
                      color: TurnaTheme.textSecondaryColor(context),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

class CourseTreeEmptyMessage extends StatelessWidget {
  const CourseTreeEmptyMessage({super.key});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(
            AppStrings.coursesNoUnitsAvailable,
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.w600,
              color: TurnaTheme.textSecondaryColor(context),
            ),
          ),
          const SizedBox(height: 16),
          FilledButton(
            onPressed: () => context.router.push(CourseManagementRoute()),
            child: Text(AppStrings.courseManagementTitle),
          ),
        ],
      ),
    );
  }
}

class CourseTreeOfficialUnavailableBanner extends StatelessWidget {
  const CourseTreeOfficialUnavailableBanner({
    super.key,
    required this.onRetry,
  });

  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: TurnaTheme.warningSurface(context),
          borderRadius: BorderRadius.circular(TurnaTheme.cardRadius),
          border: Border.all(color: TurnaTheme.warning.withValues(alpha: 0.4)),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Icon(
              Icons.warning_amber_rounded,
              size: 20,
              color: TurnaTheme.warning,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                AppStrings.coursesOfficialTreeUnavailable,
                style: TextStyle(
                  fontSize: 13,
                  height: 1.35,
                  color: TurnaTheme.textPrimaryColor(context),
                ),
              ),
            ),
            const SizedBox(width: 8),
            TextButton(
              onPressed: onRetry,
              child: Text(AppStrings.commonRetry),
            ),
          ],
        ),
      ),
    );
  }
}

class CourseTreeLoadingIndicator extends StatelessWidget {
  const CourseTreeLoadingIndicator({super.key});

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        SizedBox(
          width: 40,
          height: 40,
          child: CircularProgressIndicator(
            strokeWidth: 3,
            valueColor: AlwaysStoppedAnimation<Color>(
              TurnaTheme.brandTeal.withValues(alpha: 0.7),
            ),
          ),
        ),
        const SizedBox(height: 16),
        Text(
          AppStrings.coursesLoadingCourses,
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: TurnaTheme.textHintColor(context),
                fontWeight: FontWeight.w500,
              ),
        ),
      ],
    );
  }
}

class CourseTreeErrorMessage extends StatelessWidget {
  const CourseTreeErrorMessage({
    super.key,
    required this.title,
    required this.error,
    required this.onRetry,
  });

  final String title;
  final Object? error;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.error_outline_rounded,
              size: 56,
              color: TurnaTheme.error.withValues(alpha: 0.8),
            ),
            const SizedBox(height: 16),
            Text(
              title,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                    color: TurnaTheme.textPrimaryColor(context),
                  ),
            ),
            if (error != null) ...[
              const SizedBox(height: 8),
              Text(
                error.toString(),
                textAlign: TextAlign.center,
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: TurnaTheme.textSecondaryColor(context),
                    ),
              ),
            ],
            const SizedBox(height: 24),
            ElevatedButton.icon(
              onPressed: onRetry,
              icon: const Icon(Icons.refresh_rounded),
              label: Text(AppStrings.commonRetry),
              style: ElevatedButton.styleFrom(
                backgroundColor: TurnaTheme.brandTeal,
                foregroundColor: TurnaTheme.textOnPrimary,
                padding: const EdgeInsets.symmetric(
                  horizontal: 24,
                  vertical: 12,
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(TurnaTheme.radiusMedium),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
