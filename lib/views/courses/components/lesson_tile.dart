// Flutter imports:
import 'package:flutter/material.dart';

// Project imports:
import 'package:turna/domain/course/lesson.dart';
import 'package:turna/l10n/app_strings.dart';
import 'package:turna/views/courses/components/progress_spine.dart';
import 'package:turna/views/theme.dart';

enum LessonAttention { none, due, weak }

String? lessonAttentionText(LessonAttention attention, int count) =>
    switch (attention) {
      LessonAttention.due => AppStrings.coursesDueLessons(count),
      LessonAttention.weak => AppStrings.coursesWeakLessons(count),
      LessonAttention.none => null,
    };

IconData lessonTypeIcon(LessonType type) => switch (type) {
      LessonType.normal => Icons.menu_book_rounded,
      LessonType.listening => Icons.headphones_rounded,
      LessonType.reading => Icons.chrome_reader_mode_rounded,
      LessonType.review => Icons.replay_rounded,
      LessonType.challenge => Icons.emoji_events_rounded,
    };

String lessonTypeLabel(LessonType type) => switch (type) {
      LessonType.normal => AppStrings.coursesLessonTypeNormal,
      LessonType.listening => AppStrings.coursesLessonTypeListening,
      LessonType.reading => AppStrings.coursesLessonTypeReading,
      LessonType.review => AppStrings.coursesLessonTypeReview,
      LessonType.challenge => AppStrings.coursesLessonTypeChallenge,
    };

/// 课程行壳（Plan「湿地晨光」§3.3）：与 [UnitCard] 头部逐行拼成一张卡。
///
/// 外层延续卡面的白底与左右描边（末行收底圆角与投影），内层是下沉的
/// 「课程旅程面」（着色内嵌区），首行开面、末行收面。多行在视觉上连成
/// 一整块内嵌面，而每行仍是独立的 Sliver 列表子项——懒加载得以保留。
class LessonRowShell extends StatelessWidget {
  final LessonTile tile;
  final bool isFirst;
  final bool isLast;

  const LessonRowShell({
    required this.tile,
    required this.isFirst,
    required this.isLast,
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    final side = BorderSide(
      color: TurnaTheme.dividerBg(context).withValues(alpha: 0.85),
    );

    return DecoratedBox(
      decoration: BoxDecoration(
        color: TurnaTheme.cardBg(context),
        border: Border(
          left: side,
          right: side,
          bottom: isLast ? side : BorderSide.none,
        ),
        borderRadius: BorderRadius.vertical(
          bottom: Radius.circular(isLast ? TurnaTheme.radiusLarge : 0),
        ),
        boxShadow: isLast
            ? [
                BoxShadow(
                  color: Theme.of(context).brightness == Brightness.dark
                      ? Colors.black.withValues(alpha: 0.20)
                      : TurnaTheme.brandNavy.withValues(alpha: 0.05),
                  blurRadius: 12,
                  offset: const Offset(0, 4),
                ),
              ]
            : null,
      ),
      child: Padding(
        padding: EdgeInsets.fromLTRB(10, isFirst ? 10 : 0, 10, isLast ? 10 : 0),
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: TurnaTheme.inputFillColor(context),
            borderRadius: BorderRadius.vertical(
              top: Radius.circular(isFirst ? TurnaTheme.radiusMedium : 0),
              bottom: Radius.circular(isLast ? TurnaTheme.radiusMedium : 0),
            ),
          ),
          child: tile,
        ),
      ),
    );
  }
}

/// 课程瓦片（Plan「湿地晨光」§3.3）：旅程线格 + 课程行。
///
/// 「下一课」从内嵌面上浮起为独立小卡（白底 + 青绿描边 + 微投影），
/// 其余课程为内嵌面上的平铺行——层级即优先级。点按回调携带瓦片自身的
/// [BuildContext]，供容器变换测量源矩形（Plan §4）。
class LessonTile extends StatelessWidget {
  final Lesson lesson;
  final bool isCompleted;
  final bool isPerfect;
  final bool isNextUp;
  final LessonAttention attention;
  final bool isFirst;
  final bool isLast;
  final bool previousCompleted;

  /// 点按回调。参数为瓦片自身的 context，调用方可用
  /// `context.findRenderObject()` 取源矩形。
  final void Function(BuildContext tileContext) onTap;

  const LessonTile({
    required this.lesson,
    required this.isCompleted,
    required this.isPerfect,
    this.isNextUp = false,
    required this.attention,
    required this.isFirst,
    required this.isLast,
    this.previousCompleted = false,
    required this.onTap,
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    final attentionText = lessonAttentionText(attention, 1);
    final semanticsParts = <String>[
      lesson.name,
      lessonTypeLabel(lesson.type),
      if (isPerfect)
        AppStrings.coursesPerfect
      else if (isCompleted)
        AppStrings.commonDone,
      if (attentionText != null) attentionText,
    ];

    final content = _LessonRow(
      lesson: lesson,
      isCompleted: isCompleted,
      isPerfect: isPerfect,
      isNextUp: isNextUp,
      attention: attention,
      semanticsLabel: semanticsParts.join('，'),
      onTap: () => onTap(context),
    );

    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          ProgressSpine(
            isFirst: isFirst,
            isLast: isLast,
            status: isCompleted
                ? SpineStatus.completed
                : isNextUp
                    ? SpineStatus.nextUp
                    : SpineStatus.upcoming,
            previousCompleted: previousCompleted,
          ),
          const SizedBox(width: 8),
          Expanded(child: content),
        ],
      ),
    );
  }
}

class _LessonRow extends StatelessWidget {
  final Lesson lesson;
  final bool isCompleted;
  final bool isPerfect;
  final bool isNextUp;
  final LessonAttention attention;
  final String semanticsLabel;
  final VoidCallback onTap;

  const _LessonRow({
    required this.lesson,
    required this.isCompleted,
    required this.isPerfect,
    required this.isNextUp,
    required this.attention,
    required this.semanticsLabel,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    if (isNextUp) {
      // 下一课：浮起的白底小卡，从内嵌面里「弹」出来的优先级。
      final radius = BorderRadius.circular(TurnaTheme.radiusMedium);
      return Semantics(
        button: true,
        label: semanticsLabel,
        onTap: onTap,
        excludeSemantics: true,
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: TurnaTheme.cardBg(context),
            borderRadius: radius,
            border: Border.all(
              color: TurnaTheme.brandTeal.withValues(alpha: 0.4),
            ),
            boxShadow: [
              BoxShadow(
                color: TurnaTheme.brandNavy.withValues(alpha: 0.08),
                blurRadius: 10,
                offset: const Offset(0, 3),
              ),
            ],
          ),
          child: Material(
            color: Colors.transparent,
            child: InkWell(
              borderRadius: radius,
              onTap: onTap,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                child: _LessonRowContent(
                  lesson: lesson,
                  isCompleted: isCompleted,
                  isPerfect: isPerfect,
                  isNextUp: true,
                  attention: attention,
                ),
              ),
            ),
          ),
        ),
      );
    }

    return Semantics(
      button: true,
      label: semanticsLabel,
      onTap: onTap,
      excludeSemantics: true,
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(TurnaTheme.radiusMedium),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            child: _LessonRowContent(
              lesson: lesson,
              isCompleted: isCompleted,
              isPerfect: isPerfect,
              isNextUp: false,
              attention: attention,
            ),
          ),
        ),
      ),
    );
  }
}

class _LessonRowContent extends StatelessWidget {
  final Lesson lesson;
  final bool isCompleted;
  final bool isPerfect;
  final bool isNextUp;
  final LessonAttention attention;

  const _LessonRowContent({
    required this.lesson,
    required this.isCompleted,
    required this.isPerfect,
    required this.isNextUp,
    required this.attention,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        LessonTypeIcon(
          type: lesson.type,
          completed: isCompleted,
          perfect: isPerfect,
          isNextUp: isNextUp,
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            lesson.name,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 14,
              fontWeight: isNextUp ? FontWeight.w700 : FontWeight.w600,
              color: isCompleted
                  ? TurnaTheme.textSecondaryColor(context)
                  : TurnaTheme.textPrimaryColor(context),
            ),
          ),
        ),
        if (isNextUp) ...[
          const SizedBox(width: 6),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2.5),
            decoration: BoxDecoration(
              color: TurnaTheme.brandTeal.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(TurnaTheme.radiusRound),
            ),
            child: Text(
              AppStrings.coursesNextLesson,
              style: const TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.w700,
                color: TurnaTheme.brandTeal,
              ),
            ),
          ),
        ],
        if (attention != LessonAttention.none) ...[
          const SizedBox(width: 6),
          AttentionChip(attention: attention, count: 1),
        ],
        const SizedBox(width: 2),
        Icon(
          Icons.chevron_right_rounded,
          size: 18,
          color: isNextUp
              ? TurnaTheme.brandTeal
              : TurnaTheme.textHintColor(context),
        ),
      ],
    );
  }
}

/// 课程类型彩色图标芯片 + 完成态角标。
class LessonTypeIcon extends StatelessWidget {
  final LessonType type;
  final bool completed;
  final bool perfect;
  final bool isNextUp;

  const LessonTypeIcon({
    required this.type,
    required this.completed,
    required this.perfect,
    this.isNextUp = false,
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    final (bgAlpha, iconColor) = switch (type) {
      LessonType.challenge => (0.15, TurnaTheme.warning),
      LessonType.listening => (0.12, TurnaTheme.brandSky),
      LessonType.reading => (0.12, TurnaTheme.brandTeal),
      LessonType.review => (0.12, TurnaTheme.leagueAmethyst),
      LessonType.normal => (0.09, TurnaTheme.brandTeal),
    };

    return SizedBox.square(
      dimension: 36,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Positioned.fill(
            child: Container(
              decoration: BoxDecoration(
                color: isNextUp
                    ? TurnaTheme.brandTeal.withValues(alpha: 0.14)
                    : iconColor.withValues(alpha: bgAlpha),
                borderRadius: BorderRadius.circular(TurnaTheme.radiusSmall),
                border: perfect
                    ? Border.all(
                        color: TurnaTheme.anatolianClay.withValues(alpha: 0.65),
                      )
                    : isNextUp
                        ? Border.all(
                            color: TurnaTheme.brandTeal.withValues(alpha: 0.5),
                          )
                        : null,
              ),
              child: Icon(
                lessonTypeIcon(type),
                size: 18,
                color: isNextUp ? TurnaTheme.brandTeal : iconColor,
              ),
            ),
          ),
          if (completed)
            Positioned(
              right: -3,
              bottom: -3,
              child: Container(
                width: 15,
                height: 15,
                decoration: BoxDecoration(
                  color: TurnaTheme.anatolianClay,
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: TurnaTheme.cardBg(context),
                    width: 1.5,
                  ),
                ),
                child: const Icon(
                  Icons.check_rounded,
                  size: 9,
                  color: TurnaTheme.textOnPrimary,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// 待复习 / 需加强角标（单元头与课程行共用）。
class AttentionChip extends StatelessWidget {
  final LessonAttention attention;
  final int count;

  const AttentionChip({required this.attention, required this.count, super.key});

  @override
  Widget build(BuildContext context) {
    final (background, foreground, icon) = switch (attention) {
      LessonAttention.due => (
          TurnaTheme.warning.withValues(alpha: 0.14),
          TurnaTheme.warning,
          Icons.schedule_rounded,
        ),
      LessonAttention.weak => (
          TurnaTheme.error.withValues(alpha: 0.10),
          TurnaTheme.error,
          Icons.fitness_center_rounded,
        ),
      LessonAttention.none => (
          Colors.transparent,
          TurnaTheme.textSecondaryColor(context),
          Icons.circle_outlined,
        ),
    };

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(TurnaTheme.radiusRound),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 13, color: foreground),
          const SizedBox(width: 4),
          Text(
            lessonAttentionText(attention, count) ?? '',
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              color: foreground,
            ),
          ),
        ],
      ),
    );
  }
}
