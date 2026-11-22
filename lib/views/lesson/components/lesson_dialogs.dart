// Dart imports:
import 'dart:async';
import 'dart:math';

// Flutter imports:
import 'package:flutter/material.dart';

// Project imports:
import 'package:turna/application/lesson_viewmodel.dart';
import 'package:turna/core/spacing.dart';
import 'package:turna/core/text_styles.dart';
import 'package:turna/l10n/app_strings.dart';
import 'package:turna/views/widgets/animated_counter.dart';
import 'package:turna/views/profile/achievements/achievement_feedback_banner.dart';
import 'package:turna/core/theme.dart';
import 'package:turna/core/turna_icon_id.dart';
import 'package:turna/views/widgets/cosmetic_completion_badge.dart';
import 'package:turna/views/widgets/session_shell.dart';
import 'package:turna/views/widgets/turna_geometry.dart';
import 'package:turna/views/widgets/turna_icon.dart';
import 'package:turna/views/widgets/turna_sheet.dart';

enum MasteryDialogResult { retry, back }

/// 完成标记的视觉档（随机挑一档做标题与几何标记的强调色）。
///
/// 「湿地雾光」R06：强调色收敛到 teal / reed 系（P1「几何完成标记」），
/// 不再借用 warning / amethyst 等其他域的语义色。
class LessonCelebrationStyle {
  final TurnaIconId icon;
  final Color accent;
  final int styleIndex;

  const LessonCelebrationStyle({
    required this.icon,
    required this.accent,
    required this.styleIndex,
  });
}

const lessonCelebrationStyles = [
  LessonCelebrationStyle(
    icon: TurnaIconId.trophy,
    accent: TurnaTheme.brandReed,
    styleIndex: 0,
  ),
  LessonCelebrationStyle(
    icon: TurnaIconId.bolt,
    accent: TurnaTheme.brandTeal,
    styleIndex: 1,
  ),
  LessonCelebrationStyle(
    icon: TurnaIconId.spark,
    accent: TurnaTheme.brandReed,
    styleIndex: 2,
  ),
];

/// Shows the lesson-complete sheet: 几何完成标记 + 结果一行 + 收获纵向 +
/// 单一下一步（「湿地雾光」R06，不再用 85% 屏高弹层堆叠）。
///
/// 奖励数值走 [AnimatedCounter]；装备中的完成徽章装扮由
/// [CosmeticCompletionBadge] 呈现；新解锁成就在正文内以横幅带出。返回时
/// 弹层已闭合（「继续」是唯一出口）。
Future<void> showLessonCompletionDialog({
  required BuildContext context,
  required bool Function() isMounted,
  required int correctCount,
  required int incorrectCount,
  required int totalCount,
  required int durationSeconds,
  required int xpEarned,
  required int gemsEarned,
  required bool wasPerfect,
  required Random random,
  String? footnote,
}) async {
  if (!isMounted()) return;

  final navigator = Navigator.of(context);

  await Future.delayed(const Duration(milliseconds: 300));
  if (!isMounted()) return;

  final style =
      lessonCelebrationStyles[random.nextInt(lessonCelebrationStyles.length)];
  final title = switch (style.styleIndex) {
    0 => AppStrings.lessonCompleteTitle1,
    1 => AppStrings.lessonCompleteTitle2,
    2 => AppStrings.lessonCompleteTitle3,
    _ => AppStrings.lessonCompleteTitle1,
  };
  // 满分时副标题换成满分宣告，普通档保留随机庆祝语。
  final subtitle = wasPerfect
      ? AppStrings.lessonPerfectLesson
      : switch (style.styleIndex) {
          0 => AppStrings.lessonCompleteSubtitle1,
          1 => AppStrings.lessonCompleteSubtitle2,
          2 => AppStrings.lessonCompleteSubtitle3,
          _ => AppStrings.lessonCompleteSubtitle1,
        };

  await showTurnaSheet<void>(
    // ignore: use_build_context_synchronously
    context: context,
    title: title,
    subtitle: subtitle,
    showClose: false,
    body: _LessonCompletionSheetBody(
      style: style,
      correctCount: correctCount,
      incorrectCount: incorrectCount,
      totalCount: totalCount,
      durationSeconds: durationSeconds,
      xpEarned: xpEarned,
      gemsEarned: gemsEarned,
      footnote: footnote,
    ),
  );

  if (isMounted()) {
    // Pop unconditionally: maybePop on a PopScope(canPop: false) host page
    // re-enters the pop callback forever (the pop-loop landmine).
    navigator.pop();
  }
}

class _LessonCompletionSheetBody extends StatelessWidget {
  final LessonCelebrationStyle style;
  final int correctCount;
  final int incorrectCount;
  final int totalCount;
  final int durationSeconds;
  final int xpEarned;
  final int gemsEarned;
  final String? footnote;

  const _LessonCompletionSheetBody({
    required this.style,
    required this.correctCount,
    required this.incorrectCount,
    required this.totalCount,
    required this.durationSeconds,
    required this.xpEarned,
    required this.gemsEarned,
    this.footnote,
  });

  @override
  Widget build(BuildContext context) {
    final accuracyPercent = totalCount == 0
        ? 0
        : ((correctCount / totalCount) * 100).round();

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Flexible(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.pageMargin,
              AppSpacing.sm,
              AppSpacing.pageMargin,
              0,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                _GeometryCompletionMark(icon: style.icon, accent: style.accent),
                const SizedBox(height: AppSpacing.md),
                Text(
                  '${AppStrings.lessonResultsCount(correctCount, totalCount)}'
                  ' · ${AppStrings.lessonAccuracy} '
                  '${AppStrings.lessonPercentValue(accuracyPercent)}',
                  textAlign: TextAlign.center,
                  style: AppTextStyles.cardTitle(context),
                ),
                const SizedBox(height: AppSpacing.lg),
                _HarvestList(
                  rows: [
                    _HarvestRowData(
                      icon: TurnaIconId.checkCircle,
                      color: TurnaTheme.success,
                      label: AppStrings.lessonCorrect,
                      value: correctCount,
                    ),
                    _HarvestRowData(
                      icon: TurnaIconId.cancel,
                      color: TurnaTheme.error,
                      label: AppStrings.lessonWrong,
                      value: incorrectCount,
                    ),
                    _HarvestRowData(
                      icon: TurnaIconId.timer,
                      color: TurnaTheme.brandSky,
                      label: AppStrings.lessonTime,
                      valueText: _formatDuration(durationSeconds),
                    ),
                    _HarvestRowData(
                      icon: TurnaIconId.star,
                      color: TurnaTheme.warning,
                      label: AppStrings.lessonXp,
                      value: xpEarned,
                    ),
                    _HarvestRowData(
                      icon: TurnaIconId.diamond,
                      color: TurnaTheme.brandReed,
                      label: AppStrings.lessonGems,
                      value: gemsEarned,
                    ),
                  ],
                ),
                if (footnote != null && footnote!.isNotEmpty) ...[
                  const SizedBox(height: AppSpacing.md),
                  Text(
                    footnote!,
                    style: AppTextStyles.captionSm(context)
                        .copyWith(color: TurnaTheme.textHintColor(context)),
                    textAlign: TextAlign.center,
                  ),
                ],
                // New achievements unlocked by this completion surface as
                // part of the summary — no follow-up modal spam after the
                // sheet closes (plan §7.5).
                const Padding(
                  padding: EdgeInsets.only(top: AppSpacing.md),
                  child: AchievementFeedbackBanner(),
                ),
                const SizedBox(height: AppSpacing.lg),
              ],
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.pageMargin,
            0,
            AppSpacing.pageMargin,
            AppSpacing.lg,
          ),
          child: SessionPrimaryAction(
            label: AppStrings.lessonContinueUpper,
            onPressed: () => Navigator.of(context).pop(),
          ),
        ),
      ],
    );
  }

  String _formatDuration(int seconds) {
    final m = seconds ~/ 60;
    final s = seconds % 60;
    if (m == 0) return AppStrings.lessonDurationSeconds(s);
    return AppStrings.lessonDurationMinutes(m, s);
  }
}

/// Result sheet for one finished sub-lesson ("小课") inside a lesson that
/// still has more to play.
///
/// Deliberately lighter than [showLessonCompletionDialog]: no XP/gems (those
/// settle once per lesson, at the end), no achievement banner — the checkpoint
/// answers one question ("how did this chunk go?") and offers two exits: keep
/// walking, or leave and resume later from exactly this boundary.
///
/// Returns `true` when the player chose to continue.
Future<bool> showSubLessonCompletionDialog({
  required BuildContext context,
  required bool Function() isMounted,
  required String segmentName,
  required int segmentNumber,
  required int segmentCount,
  required int correctCount,
  required int incorrectCount,
  required int totalCount,
}) async {
  if (!isMounted()) return false;

  final result = await showTurnaSheet<bool>(
    context: context,
    title: AppStrings.subLessonCompleteTitle,
    subtitle:
        '$segmentName · ${AppStrings.lessonSubLessonIndex(segmentNumber, segmentCount)}',
    showClose: false,
    body: _SubLessonSheetBody(
      correctCount: correctCount,
      incorrectCount: incorrectCount,
      totalCount: totalCount,
    ),
  );
  return result ?? false;
}

class _SubLessonSheetBody extends StatelessWidget {
  final int correctCount;
  final int incorrectCount;
  final int totalCount;

  const _SubLessonSheetBody({
    required this.correctCount,
    required this.incorrectCount,
    required this.totalCount,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Flexible(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.pageMargin,
              AppSpacing.sm,
              AppSpacing.pageMargin,
              0,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const _GeometryCompletionMark(
                  icon: TurnaIconId.checkCircle,
                  accent: TurnaTheme.brandTeal,
                ),
                const SizedBox(height: AppSpacing.md),
                Text(
                  AppStrings.lessonResultsCount(correctCount, totalCount),
                  textAlign: TextAlign.center,
                  style: AppTextStyles.cardTitle(context),
                ),
                const SizedBox(height: AppSpacing.lg),
                _HarvestList(
                  rows: [
                    _HarvestRowData(
                      icon: TurnaIconId.checkCircle,
                      color: TurnaTheme.success,
                      label: AppStrings.lessonCorrect,
                      value: correctCount,
                    ),
                    _HarvestRowData(
                      icon: TurnaIconId.cancel,
                      color: TurnaTheme.error,
                      label: AppStrings.lessonWrong,
                      value: incorrectCount,
                    ),
                  ],
                ),
                const SizedBox(height: AppSpacing.lg),
              ],
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.pageMargin,
            0,
            AppSpacing.pageMargin,
            AppSpacing.sm,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              SessionPrimaryAction(
                label: AppStrings.subLessonContinueNext,
                onPressed: () => Navigator.of(context).pop(true),
              ),
              TextButton(
                onPressed: () => Navigator.of(context).pop(false),
                child: Text(
                  AppStrings.subLessonTakeABreak,
                  style: AppTextStyles.captionSm(context)
                      .copyWith(color: TurnaTheme.textHintColor(context)),
                ),
              ),
              Text(
                AppStrings.subLessonCompleteSubtitle,
                style: AppTextStyles.captionSm(context)
                    .copyWith(color: TurnaTheme.textHintColor(context)),
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// 顶部几何完成标记：几何底纹（圆 / 弧线）+ 圆形徽章位。装备中的完成
/// 徽章装扮优先呈现，未装备时回退到本档的图标与强调色。
class _GeometryCompletionMark extends StatelessWidget {
  const _GeometryCompletionMark({required this.icon, required this.accent});

  final TurnaIconId icon;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    return TurnaGeometry(
      kind: TurnaGeometryKind.achievement,
      accent: accent,
      size: 128,
      child: CosmeticCompletionBadge(
        fallbackIcon: icon,
        fallbackColor: accent,
        size: 76,
        iconSize: 38,
      ),
    );
  }
}

class _HarvestRowData {
  const _HarvestRowData({
    required this.icon,
    required this.color,
    required this.label,
    this.value,
    this.valueText,
  });

  final TurnaIconId icon;
  final Color color;
  final String label;
  final int? value;
  final String? valueText;
}

/// 收获纵向列表：图标 + 标签在左、数值右对齐，行间发丝线。
///
/// 数值是「结果注释」而非放大数字堆叠——[AnimatedCounter] 保留滚动动画，
/// 字号与正文同级（R06 决定）。
class _HarvestList extends StatelessWidget {
  const _HarvestList({required this.rows});

  final List<_HarvestRowData> rows;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (var i = 0; i < rows.length; i++) ...[
          _HarvestRow(data: rows[i]),
          if (i < rows.length - 1)
            Container(height: 1, color: TurnaTheme.dividerBg(context)),
        ],
      ],
    );
  }
}

class _HarvestRow extends StatelessWidget {
  const _HarvestRow({required this.data});

  final _HarvestRowData data;

  @override
  Widget build(BuildContext context) {
    final valueStyle = AppTextStyles.cardTitle(context)
        .copyWith(fontFeatures: const [FontFeature.tabularFigures()]);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm + 2),
      child: Row(
        children: [
          TurnaIcon(data.icon, color: data.color, size: 20),
          const SizedBox(width: AppSpacing.sm + 2),
          Expanded(
            child: Text(data.label, style: AppTextStyles.bodyText(context)),
          ),
          if (data.valueText != null)
            Text(data.valueText!, style: valueStyle)
          else
            AnimatedCounter(target: data.value ?? 0, style: valueStyle),
        ],
      ),
    );
  }
}

/// Shows the mastery retry dialog. Caller handles the result.
Future<MasteryDialogResult?> showMasteryRetryDialog({
  required BuildContext context,
  required bool Function() isMounted,
  required LessonViewModel vm,
}) async {
  if (!isMounted()) return null;

  await Future.delayed(const Duration(milliseconds: 300));
  if (!isMounted()) return null;

  final total = vm.totalInteractionCount;
  final correct = vm.correctAnswers;
  final accuracyPercent = total == 0 ? 0 : ((correct / total) * 100).round();

  return showDialog<MasteryDialogResult>(
    // ignore: use_build_context_synchronously
    context: context,
    barrierDismissible: false,
    builder: (ctx) => TurnaDialogPanel(
      title: AppStrings.lessonNotYet,
      body: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const SizedBox(height: AppSpacing.sm),
          Container(
            padding: const EdgeInsets.all(AppSpacing.lg),
            decoration: BoxDecoration(
              color: TurnaTheme.error.withValues(alpha: 0.12),
              shape: BoxShape.circle,
            ),
            child: const TurnaIcon(
              TurnaIconId.refresh,
              color: TurnaTheme.error,
              size: 36,
            ),
          ),
          const SizedBox(height: AppSpacing.lg),
          Text(
            AppStrings.lessonMasteryMessage(correct, total, accuracyPercent),
            style: AppTextStyles.bodyText(ctx)
                .copyWith(color: TurnaTheme.textSecondaryColor(ctx)),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: AppSpacing.sm),
        ],
      ),
      actions: [
        TurnaSheetAction(
          label: AppStrings.lessonBackToCourses,
          onPressed: () => Navigator.of(ctx).pop(MasteryDialogResult.back),
        ),
        TurnaSheetAction(
          label: AppStrings.lessonTryAgain,
          primary: true,
          onPressed: () => Navigator.of(ctx).pop(MasteryDialogResult.retry),
        ),
      ],
    ),
  );
}
