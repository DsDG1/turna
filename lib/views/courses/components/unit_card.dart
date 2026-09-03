// Flutter imports:
import 'package:flutter/material.dart';

// Project imports:
import 'package:turna/domain/course/unit.dart';
import 'package:turna/l10n/app_strings.dart';
import 'package:turna/views/courses/components/lesson_tile.dart';
import 'package:turna/views/home/motion/turna_motion.dart';
import 'package:turna/views/theme.dart';

/// 单元卡（Plan「湿地晨光」§3.3）：抬升的内容卡头部。
///
/// 折叠态是一张完整圆角的静置卡；展开时底边圆角归零、下缘投影撤去——
/// 课程行（[LessonTile] 行壳）在其下方逐行拼合为「卡身 + 内嵌课程旅程
/// 面」，视觉上是一整张卡，实际上保持 Sliver 列表的懒加载（百课单元
/// 不全量构建）。头部沿用进度环 / 角标 / chevron 的信息结构。
class UnitCard extends StatelessWidget {
  final Unit unit;
  final int completedCount;
  final int dueLessonCount;
  final int weakLessonCount;
  final bool expanded;
  final bool reduceMotion;
  final VoidCallback onHeaderTap;

  const UnitCard({
    required this.unit,
    required this.completedCount,
    required this.dueLessonCount,
    required this.weakLessonCount,
    required this.expanded,
    required this.reduceMotion,
    required this.onHeaderTap,
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    final lessonCount = unit.lessons.length;
    final isFullyComplete =
        completedCount == lessonCount && unit.lessons.isNotEmpty;
    final attention = dueLessonCount > 0
        ? LessonAttention.due
        : weakLessonCount > 0
            ? LessonAttention.weak
            : LessonAttention.none;
    final attentionCount = attention == LessonAttention.due
        ? dueLessonCount
        : attention == LessonAttention.weak
            ? weakLessonCount
            : 0;

    final duration = TurnaMotion.scaled(TurnaMotion.base, reduceMotion);
    final progressText = AppStrings.coursesUnitProgress(
      completedCount,
      lessonCount,
    );
    final attentionText = lessonAttentionText(attention, attentionCount);
    final semanticsParts = <String>[
      unit.name,
      progressText,
      if (attentionText != null) attentionText,
    ];

    final borderRadius = BorderRadius.vertical(
      top: const Radius.circular(TurnaTheme.radiusLarge),
      bottom: expanded ? Radius.zero : const Radius.circular(TurnaTheme.radiusLarge),
    );

    return Semantics(
      button: true,
      expanded: expanded,
      label: semanticsParts.join('，'),
      onTap: onHeaderTap,
      excludeSemantics: true,
      child: AnimatedContainer(
        duration: duration,
        curve: TurnaMotion.easeOut,
        decoration: BoxDecoration(
          color: TurnaTheme.cardBg(context),
          borderRadius: borderRadius,
          border: Border.all(
            color: TurnaTheme.dividerBg(context).withValues(
              alpha: expanded ? 0.85 : 0.5,
            ),
            width: 1.0,
          ),
          // 展开时撤去投影：下缘由课程行壳收尾，投影归末行承担。
          boxShadow: expanded
              ? null
              : [
                  BoxShadow(
                    color: Theme.of(context).brightness == Brightness.dark
                        ? Colors.black.withValues(alpha: 0.20)
                        : TurnaTheme.brandNavy.withValues(alpha: 0.05),
                    blurRadius: 12,
                    offset: const Offset(0, 4),
                  ),
                ],
        ),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            borderRadius: borderRadius,
            onTap: onHeaderTap,
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: _UnitHeaderRow(
                unit: unit,
                completedCount: completedCount,
                progressText: progressText,
                isFullyComplete: isFullyComplete,
                attention: attention,
                attentionCount: attentionCount,
                expanded: expanded,
                duration: duration,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _UnitHeaderRow extends StatelessWidget {
  final Unit unit;
  final int completedCount;
  final String progressText;
  final bool isFullyComplete;
  final LessonAttention attention;
  final int attentionCount;
  final bool expanded;
  final Duration duration;

  const _UnitHeaderRow({
    required this.unit,
    required this.completedCount,
    required this.progressText,
    required this.isFullyComplete,
    required this.attention,
    required this.attentionCount,
    required this.expanded,
    required this.duration,
  });

  @override
  Widget build(BuildContext context) {
    final lessonCount = unit.lessons.length;
    final title = _UnitTitle(unit: unit);
    final progress = Text(
      progressText,
      style: TextStyle(
        fontSize: 12,
        fontWeight: FontWeight.w700,
        color: isFullyComplete
            ? TurnaTheme.anatolianClay
            : TurnaTheme.textSecondaryColor(context),
      ),
    );
    final attentionChip = attention == LessonAttention.none
        ? null
        : AttentionChip(attention: attention, count: attentionCount);
    final chevron = AnimatedRotation(
      turns: expanded ? 0.5 : 0,
      duration: duration,
      curve: TurnaMotion.easeOut,
      child: Icon(
        Icons.expand_more_rounded,
        size: 22,
        color: TurnaTheme.textHintColor(context),
      ),
    );

    return LayoutBuilder(
      builder: (context, constraints) {
        final scale = MediaQuery.textScalerOf(context).scale(1);
        final stacked = constraints.maxWidth < 328 || scale >= 1.3;
        final ring = UnitProgressRing(
          completedCount: completedCount,
          lessonCount: lessonCount,
          reduceMotion: duration == Duration.zero,
        );

        if (stacked) {
          return Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              ring,
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    title,
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 8,
                      runSpacing: 6,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        progress,
                        if (attentionChip != null) attentionChip,
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 6),
              chevron,
            ],
          );
        }

        return Row(
          children: [
            ring,
            const SizedBox(width: 12),
            Expanded(child: title),
            const SizedBox(width: 10),
            progress,
            if (attentionChip != null) ...[
              const SizedBox(width: 8),
              attentionChip,
            ],
            const SizedBox(width: 4),
            chevron,
          ],
        );
      },
    );
  }
}

class _UnitTitle extends StatelessWidget {
  final Unit unit;

  const _UnitTitle({required this.unit});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          unit.name,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.w700,
            color: TurnaTheme.textPrimaryColor(context),
          ),
        ),
        if (unit.description.isNotEmpty) ...[
          const SizedBox(height: 2),
          Text(
            unit.description,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 13,
              color: TurnaTheme.textSecondaryColor(context),
            ),
          ),
        ],
      ],
    );
  }
}

class UnitProgressRing extends StatelessWidget {
  final int completedCount;
  final int lessonCount;
  final bool reduceMotion;

  const UnitProgressRing({
    required this.completedCount,
    required this.lessonCount,
    required this.reduceMotion,
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    final progress = lessonCount == 0 ? 0.0 : completedCount / lessonCount;
    final complete = lessonCount > 0 && completedCount == lessonCount;
    final color = complete ? TurnaTheme.anatolianClay : TurnaTheme.brandTeal;

    return SizedBox.square(
      dimension: 40,
      child: TweenAnimationBuilder<double>(
        tween: Tween(begin: 0, end: progress),
        duration: TurnaMotion.scaled(TurnaMotion.base, reduceMotion),
        curve: TurnaMotion.easeOut,
        builder: (context, value, _) => Stack(
          alignment: Alignment.center,
          children: [
            SizedBox.square(
              dimension: 38,
              child: CircularProgressIndicator(
                value: value,
                strokeWidth: 3,
                backgroundColor: TurnaTheme.dividerBg(context),
                valueColor: AlwaysStoppedAnimation<Color>(color),
              ),
            ),
            Icon(
              complete ? Icons.check_rounded : Icons.menu_book_rounded,
              size: 18,
              color: color,
            ),
          ],
        ),
      ),
    );
  }
}
