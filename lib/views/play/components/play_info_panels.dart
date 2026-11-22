// Flutter imports:
import 'package:flutter/material.dart';

// Project imports:
import 'package:turna/application/ai/engine/ai_engine_config.dart';
import 'package:turna/application/study_stats_provider.dart';
import 'package:turna/core/spacing.dart';
import 'package:turna/core/text_styles.dart';
import 'package:turna/core/theme.dart';
import 'package:turna/core/turna_icon_id.dart';
import 'package:turna/domain/course/mistake_entry.dart';
import 'package:turna/domain/study/daily_stats.dart';
import 'package:turna/l10n/app_strings.dart';
import 'package:turna/views/play/components/info_popup.dart';
import 'package:turna/views/widgets/turna_icon.dart';
import 'package:turna/views/widgets/turna_loader.dart';

/// Play Hub 队列数据快照：一次从 providers 读取，供浮窗面板纯展示。
/// 全部字段同步可得（复习进度面板的 7 日数据除外，面板内自己 FutureBuilder）。
class PlayQueueSnapshot {
  const PlayQueueSnapshot({
    required this.mistakeCount,
    required this.mistakeGrammarCount,
    required this.mistakeRewriteCount,
    required this.recentMistakes,
    required this.srsDue,
    required this.srsExpressionDue,
    required this.srsSeen,
    required this.srsRegistered,
    required this.srsLapse,
    required this.grammarDue,
    required this.grammarSeen,
    required this.grammarRegistered,
    required this.legacyAnkiDue,
    this.officialAnkiDue,
    required this.ankiUnavailable,
    required this.weakWords,
    this.ankiCourse = false,
  });

  /// 待复习错题总数。
  final int mistakeCount;
  final int mistakeGrammarCount;
  final int mistakeRewriteCount;
  final List<MistakeEntry> recentMistakes;

  final int srsDue;
  final int srsExpressionDue;
  final int srsSeen;
  final int srsRegistered;
  final int srsLapse;

  final int grammarDue;
  final int grammarSeen;
  final int grammarRegistered;

  final int legacyAnkiDue;
  final int? officialAnkiDue;
  final bool ankiUnavailable;

  final List<WeakWord> weakWords;

  /// ADR 0037：记忆卡课程激活时，练习队列只看记忆卡到期。
  final bool ankiCourse;

  /// 记忆卡聚合到期数（legacy fail-closed 为 0；unavailable 时调用方
  /// 自行显示「—」，见 [ankiDueCount] 的用途——记忆卡行与长按浮窗）。
  int get ankiDueCount {
    if (ankiUnavailable) return 0;
    return legacyAnkiDue + (officialAnkiDue ?? 0);
  }

  int get totalDue {
    if (ankiCourse) return ankiDueCount;
    return mistakeCount + srsDue + grammarDue;
  }
}

// ────────────────────────────────────────────────────────────────────
// 浮窗外壳 + 通用构件
// ────────────────────────────────────────────────────────────────────

/// 浮窗统一外壳：accent 头部（4px 图标井 + 标题）+ 内容 + 「进入」底栏。
/// `onEnter` 由调用方负责「先关浮窗再导航」。
class InfoPanelShell extends StatelessWidget {
  final String title;
  final TurnaIconId icon;
  final Color accentColor;
  final Widget child;
  final VoidCallback? onEnter;

  const InfoPanelShell({
    required this.title,
    required this.icon,
    required this.accentColor,
    required this.child,
    this.onEnter,
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    final accent = TurnaTheme.accentOnCard(context, accentColor);

    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.lg,
        vertical: AppSpacing.md + 2,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          InfoStaggeredRow(
            index: 0,
            child: Row(
              children: [
                Container(
                  width: 36,
                  height: 36,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: TurnaTheme.softTint(context, accent, alpha: 0.12),
                    borderRadius: TurnaTheme.borderRadius,
                  ),
                  child: TurnaIcon(icon, color: accent, size: 18),
                ),
                const SizedBox(width: AppSpacing.sm + 2),
                Expanded(
                  child: Text(
                    title,
                    style: AppTextStyles.cardTitle(context)
                        .copyWith(fontWeight: FontWeight.w700),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.xs),
          child,
          if (onEnter != null) ...[
            const SizedBox(height: AppSpacing.sm + 2),
            InfoStaggeredRow(
              index: 9,
              child: _EnterButton(accentColor: accentColor, onTap: onEnter!),
            ),
          ],
        ],
      ),
    );
  }
}

class _EnterButton extends StatelessWidget {
  final Color accentColor;
  final VoidCallback onTap;

  const _EnterButton({required this.accentColor, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: TurnaTheme.borderRadius,
        child: Ink(
          decoration: TurnaTheme.primaryCtaDecoration(
            borderRadius: TurnaTheme.borderRadius,
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.lg,
              vertical: AppSpacing.sm + 2,
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  AppStrings.playPopupEnter,
                  style: AppTextStyles.buttonLabel,
                ),
                const SizedBox(width: AppSpacing.xs),
                const TurnaIcon(
                  TurnaIconId.arrowForward,
                  color: TurnaTheme.textOnPrimary,
                  size: 16,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// 「标签 …… 数值」统计行。数值右对齐加粗，可选 leading 彩点。
class InfoStatRow extends StatelessWidget {
  final String label;
  final String value;
  final Color? dotColor;

  const InfoStatRow({
    required this.label,
    required this.value,
    this.dotColor,
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.xs - 2,
        vertical: AppSpacing.sm - 1,
      ),
      child: Row(
        children: [
          if (dotColor != null) ...[
            Container(
              width: 8,
              height: 8,
              decoration: BoxDecoration(
                color: dotColor,
                shape: BoxShape.circle,
              ),
            ),
            const SizedBox(width: AppSpacing.sm),
          ],
          Expanded(child: Text(label, style: AppTextStyles.captionSm(context))),
          Text(
            value,
            style: AppTextStyles.cardTitle(context).copyWith(
              fontWeight: FontWeight.w700,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
        ],
      ),
    );
  }
}

/// 面板内的小节标题。
class InfoGroupLabel extends StatelessWidget {
  final String text;

  const InfoGroupLabel(this.text, {super.key});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: AppSpacing.sm + 2, bottom: 2),
      child: Text(text, style: AppTextStyles.caption(context)),
    );
  }
}

String _relativeDayLabel(DateTime time) {
  final now = DateTime.now();
  final today = DateTime(now.year, now.month, now.day);
  final day = DateTime(time.year, time.month, time.day);
  final diff = today.difference(day).inDays;
  if (diff <= 0) return AppStrings.playPopupToday;
  if (diff == 1) return AppStrings.playPopupYesterday;
  return AppStrings.playPopupDaysAgo(diff);
}

// ────────────────────────────────────────────────────────────────────
// 各入口面板
// ────────────────────────────────────────────────────────────────────

/// 今日复习 Hero 长按：语言三队列一览 + 高亮「下一个」。
/// （记忆卡到期走记忆卡行的专属长按浮窗 `AnkiPanelBody`，不混入本表。）
class TodayOverviewPanelBody extends StatelessWidget {
  final VoidCallback? onEnter;

  final PlayQueueSnapshot snapshot;
  final String nextLabel;

  const TodayOverviewPanelBody({
    required this.snapshot,
    required this.nextLabel,
    super.key,
    this.onEnter,
  });

  @override
  Widget build(BuildContext context) {
    // 同步失败时显示「—」，与记忆卡行的计数口径一致。
    final ankiValue = snapshot.ankiUnavailable
        ? '—'
        : '${snapshot.ankiDueCount}';
    return InfoPanelShell(
      title: AppStrings.playTodayHeroTitle,
      icon: TurnaIconId.play,
      accentColor: TurnaTheme.brandTeal,
      onEnter: onEnter,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          InfoGroupLabel(AppStrings.playPopupNextQueueLabel),
          InfoStaggeredRow(
            index: 1,
            child: InfoStatRow(
              label: nextLabel,
              value: '${snapshot.totalDue}',
              dotColor: TurnaTheme.brandTeal,
            ),
          ),
          if (!snapshot.ankiCourse) ...[
            InfoStaggeredRow(
              index: 2,
              child: InfoStatRow(
                label: AppStrings.playMistakeReviewTitle,
                value: '${snapshot.mistakeCount}',
                dotColor: TurnaTheme.errorLight,
              ),
            ),
            InfoStaggeredRow(
              index: 3,
              child: InfoStatRow(
                label: AppStrings.playReviewTitle,
                value: '${snapshot.srsDue}',
                dotColor: TurnaTheme.success,
              ),
            ),
            InfoStaggeredRow(
              index: 4,
              child: InfoStatRow(
                label: AppStrings.playGrammarReviewTitle,
                value: '${snapshot.grammarDue}',
                dotColor: TurnaTheme.brandTeal,
              ),
            ),
          ],
          if (snapshot.ankiCourse)
            InfoStaggeredRow(
              index: 2,
              child: InfoStatRow(
                label: AppStrings.playAnkiReviewTitle,
                value: ankiValue,
                dotColor: TurnaTheme.brandSky,
              ),
            ),
        ],
      ),
    );
  }
}

/// 错题复习长按：错题构成 + 最近错题预览。
class MistakePanelBody extends StatelessWidget {
  final VoidCallback? onEnter;

  final PlayQueueSnapshot snapshot;

  const MistakePanelBody({required this.snapshot, super.key, this.onEnter});

  @override
  Widget build(BuildContext context) {
    return InfoPanelShell(
      title: AppStrings.playMistakeReviewTitle,
      icon: TurnaIconId.warning,
      accentColor: TurnaTheme.errorLight,
      onEnter: onEnter,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          InfoStaggeredRow(
            index: 1,
            child: InfoStatRow(
              label: AppStrings.playPopupMistakePending,
              value: '${snapshot.mistakeCount}',
              dotColor: TurnaTheme.errorLight,
            ),
          ),
          InfoStaggeredRow(
            index: 2,
            child: InfoStatRow(
              label: AppStrings.playPopupMistakeGrammar,
              value: '${snapshot.mistakeGrammarCount}',
            ),
          ),
          InfoStaggeredRow(
            index: 3,
            child: InfoStatRow(
              label: AppStrings.playPopupMistakeRewrite,
              value: '${snapshot.mistakeRewriteCount}',
            ),
          ),
          if (snapshot.recentMistakes.isNotEmpty) ...[
            InfoGroupLabel(AppStrings.playPopupRecentMistakes),
            for (var i = 0; i < snapshot.recentMistakes.length; i++)
              InfoStaggeredRow(
                index: 4 + i,
                child: _MistakePreviewTile(entry: snapshot.recentMistakes[i]),
              ),
          ],
        ],
      ),
    );
  }
}

class _MistakePreviewTile extends StatelessWidget {
  final MistakeEntry entry;

  const _MistakePreviewTile({required this.entry});

  @override
  Widget build(BuildContext context) {
    final answer = entry.correctAnswer.trim().isEmpty
        ? '—'
        : entry.correctAnswer.trim();
    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.xs - 2,
        vertical: AppSpacing.sm - 2,
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(
              answer,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: AppTextStyles.bodyText(context)
                  .copyWith(fontWeight: FontWeight.w600),
            ),
          ),
          const SizedBox(width: AppSpacing.sm),
          Text(
            _relativeDayLabel(entry.timestamp),
            style: AppTextStyles.captionSm(context)
                .copyWith(color: TurnaTheme.textHintColor(context)),
          ),
        ],
      ),
    );
  }
}

/// 单词复习长按：FSRS 队列规模一览。
class SrsPanelBody extends StatelessWidget {
  final VoidCallback? onEnter;

  final PlayQueueSnapshot snapshot;

  const SrsPanelBody({required this.snapshot, super.key, this.onEnter});

  @override
  Widget build(BuildContext context) {
    return InfoPanelShell(
      title: AppStrings.playReviewTitle,
      icon: TurnaIconId.repeat,
      accentColor: TurnaTheme.success,
      onEnter: onEnter,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          InfoStaggeredRow(
            index: 1,
            child: InfoStatRow(
              label: AppStrings.playPopupSrsWords,
              value: '${snapshot.srsDue}',
              dotColor: TurnaTheme.success,
            ),
          ),
          InfoStaggeredRow(
            index: 2,
            child: InfoStatRow(
              label: AppStrings.playPopupSrsExpressions,
              value: '${snapshot.srsExpressionDue}',
            ),
          ),
          InfoStaggeredRow(
            index: 3,
            child: InfoStatRow(
              label: AppStrings.playPopupSrsSeen,
              value: '${snapshot.srsSeen}',
            ),
          ),
          InfoStaggeredRow(
            index: 4,
            child: InfoStatRow(
              label: AppStrings.playPopupSrsRegistered,
              value: '${snapshot.srsRegistered}',
            ),
          ),
          InfoStaggeredRow(
            index: 5,
            child: InfoStatRow(
              label: AppStrings.playPopupSrsLapse,
              value: '${snapshot.srsLapse}',
            ),
          ),
        ],
      ),
    );
  }
}

/// 语法复习长按。
class GrammarPanelBody extends StatelessWidget {
  final VoidCallback? onEnter;

  final PlayQueueSnapshot snapshot;

  const GrammarPanelBody({required this.snapshot, super.key, this.onEnter});

  @override
  Widget build(BuildContext context) {
    return InfoPanelShell(
      title: AppStrings.playGrammarReviewTitle,
      icon: TurnaIconId.book,
      accentColor: TurnaTheme.brandTeal,
      onEnter: onEnter,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          InfoStaggeredRow(
            index: 1,
            child: InfoStatRow(
              label: AppStrings.playPopupGrammarDue,
              value: '${snapshot.grammarDue}',
              dotColor: TurnaTheme.brandTeal,
            ),
          ),
          InfoStaggeredRow(
            index: 2,
            child: InfoStatRow(
              label: AppStrings.playPopupGrammarSeen,
              value: '${snapshot.grammarSeen}',
            ),
          ),
          InfoStaggeredRow(
            index: 3,
            child: InfoStatRow(
              label: AppStrings.playPopupGrammarRegistered,
              value: '${snapshot.grammarRegistered}',
            ),
          ),
        ],
      ),
    );
  }
}

/// 记忆卡复习长按：导入牌组 + 正式牌组拆分。
class AnkiPanelBody extends StatelessWidget {
  final VoidCallback? onEnter;

  final PlayQueueSnapshot snapshot;

  const AnkiPanelBody({required this.snapshot, super.key, this.onEnter});

  @override
  Widget build(BuildContext context) {
    return InfoPanelShell(
      title: AppStrings.playAnkiReviewTitle,
      icon: TurnaIconId.cards,
      accentColor: TurnaTheme.brandSky,
      onEnter: onEnter,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (snapshot.ankiUnavailable)
            InfoStaggeredRow(
              index: 1,
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
                child: Row(
                  children: [
                    const TurnaIcon(
                      TurnaIconId.cloudOff,
                      size: 16,
                      color: TurnaTheme.warning,
                    ),
                    const SizedBox(width: AppSpacing.sm),
                    Expanded(
                      child: Text(
                        AppStrings.playPopupAnkiUnavailable,
                        style: AppTextStyles.captionSm(context).copyWith(
                          color: TurnaTheme.warning,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          InfoStaggeredRow(
            index: 2,
            child: InfoStatRow(
              label: AppStrings.playPopupAnkiTotal,
              value: snapshot.ankiUnavailable
                  ? '—'
                  : '${(snapshot.officialAnkiDue ?? 0) + snapshot.legacyAnkiDue}',
              dotColor: TurnaTheme.brandSky,
            ),
          ),
          InfoStaggeredRow(
            index: 3,
            child: InfoStatRow(
              label: AppStrings.playPopupAnkiLegacy,
              value: '${snapshot.legacyAnkiDue}',
            ),
          ),
          InfoStaggeredRow(
            index: 4,
            child: InfoStatRow(
              label: AppStrings.playPopupAnkiOfficial,
              value: snapshot.officialAnkiDue == null
                  ? '—'
                  : '${snapshot.officialAnkiDue}',
            ),
          ),
        ],
      ),
    );
  }
}

/// 薄弱单词长按：Top 薄弱词预览。
class WeakWordsPanelBody extends StatelessWidget {
  final VoidCallback? onEnter;

  final PlayQueueSnapshot snapshot;

  const WeakWordsPanelBody({required this.snapshot, super.key, this.onEnter});

  @override
  Widget build(BuildContext context) {
    final words = snapshot.weakWords.take(3).toList();

    return InfoPanelShell(
      title: AppStrings.playWeakWordsTitle,
      icon: TurnaIconId.target,
      accentColor: TurnaTheme.anatolianClay,
      onEnter: onEnter,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          InfoStaggeredRow(
            index: 1,
            child: InfoStatRow(
              label: AppStrings.playWeakWordsTitle,
              value: '${snapshot.weakWords.length}',
              dotColor: TurnaTheme.anatolianClay,
            ),
          ),
          if (words.isNotEmpty) ...[
            for (var i = 0; i < words.length; i++)
              InfoStaggeredRow(
                index: 2 + i,
                child: _WeakWordPreviewTile(word: words[i]),
              ),
            InfoGroupLabel(AppStrings.playPopupWeakSourceHint),
          ],
        ],
      ),
    );
  }
}

class _WeakWordPreviewTile extends StatelessWidget {
  final WeakWord word;

  const _WeakWordPreviewTile({required this.word});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.xs - 2,
        vertical: AppSpacing.sm - 2,
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  word.displayText,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppTextStyles.bodyText(context)
                      .copyWith(fontWeight: FontWeight.w600),
                ),
                if (word.translation != null &&
                    word.translation!.trim().isNotEmpty)
                  Text(
                    word.translation!,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppTextStyles.captionSm(context),
                  ),
              ],
            ),
          ),
          const SizedBox(width: AppSpacing.sm),
          Container(
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.sm,
              vertical: AppSpacing.xs,
            ),
            decoration: const BoxDecoration(
              color: TurnaTheme.anatolianClay,
              borderRadius: TurnaTheme.borderRadius,
            ),
            child: Text(
              AppStrings.playPopupWeakTimes(word.mistakeCount),
              style: AppTextStyles.caption(context).copyWith(
                color: TurnaTheme.textOnPrimary,
                fontWeight: FontWeight.w700,
                letterSpacing: 0,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// 复习进度长按：近 7 天复习柱状图 + 累计。7 日数据是异步聚合，由调用方
/// 注入 [stats] 实例——浮窗挂根 Overlay（页面 Provider 树之上），面板内
/// 不能做 inherited provider 查找。
class ReviewProgressPanelBody extends StatelessWidget {
  final StudyStatsProvider stats;
  final VoidCallback? onEnter;

  const ReviewProgressPanelBody({super.key, required this.stats, this.onEnter});

  @override
  Widget build(BuildContext context) {
    return InfoPanelShell(
      title: AppStrings.playReviewProgressTitle,
      icon: TurnaIconId.insights,
      accentColor: TurnaTheme.brandTeal,
      onEnter: onEnter,
      child: FutureBuilder<List<Object>>(
        future: Future.wait<Object>([
          stats.getLastNDays(7),
          stats.getTotalRecordedReviews(),
          stats.getTotalStudyMinutes(),
        ]),
        builder: (context, snapshot) {
          final data = snapshot.data;
          if (data == null) {
            return Padding(
              padding: const EdgeInsets.symmetric(vertical: AppSpacing.md),
              child: Center(child: TurnaLoader.inline()),
            );
          }
          final days = data[0] as List<DailyStudyStats>;
          final totalReviews = data[1] as int;
          final totalMinutes = data[2] as int;
          final hasData =
              totalReviews > 0 || days.any((d) => d.reviewCount > 0);

          if (!hasData) {
            return Padding(
              padding: const EdgeInsets.symmetric(vertical: AppSpacing.md + 2),
              child: Text(
                AppStrings.playPopupNoStatsYet,
                style: AppTextStyles.captionSm(context)
                    .copyWith(color: TurnaTheme.textHintColor(context)),
              ),
            );
          }

          return Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              InfoGroupLabel(AppStrings.playPopupRecent7Days),
              InfoStaggeredRow(index: 1, child: _WeeklyBars(days: days)),
              InfoStaggeredRow(
                index: 2,
                child: InfoStatRow(
                  label: AppStrings.playPopupTotalReviews,
                  value: '$totalReviews',
                ),
              ),
              InfoStaggeredRow(
                index: 3,
                child: InfoStatRow(
                  label: AppStrings.playPopupStudyMinutes,
                  value: AppStrings.playPopupMinutesValue(totalMinutes),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

/// 简易 7 日柱状图：柱高按峰值归一，柱内标数值（峰值日）。
class _WeeklyBars extends StatelessWidget {
  final List<DailyStudyStats> days;

  const _WeeklyBars({required this.days});

  @override
  Widget build(BuildContext context) {
    final values = days.map((d) => d.reviewCount);
    final peak = values.fold<int>(0, (m, v) => v > m ? v : m);
    const barHeight = 64.0;

    return SizedBox(
      height: barHeight + 28,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          for (final day in days)
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xs),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    Text(
                      '${day.reviewCount}',
                      style: AppTextStyles.caption(context).copyWith(
                        letterSpacing: 0,
                        fontWeight: FontWeight.w700,
                        fontFeatures: const [FontFeature.tabularFigures()],
                        color: day.reviewCount == peak && peak > 0
                            ? TurnaTheme.brandTeal
                            : TurnaTheme.textHintColor(context),
                      ),
                    ),
                    const SizedBox(height: AppSpacing.xs),
                    Container(
                      height: peak == 0
                          ? 4.0
                          : (day.reviewCount / peak) * barHeight,
                      decoration: BoxDecoration(
                        color: day.reviewCount > 0
                            ? TurnaTheme.brandTeal
                            : TurnaTheme.dividerBg(context),
                        borderRadius: TurnaTheme.borderRadius,
                      ),
                    ),
                    const SizedBox(height: AppSpacing.xs),
                    Text(
                      '${day.date.month}/${day.date.day}',
                      style: AppTextStyles.caption(context)
                          .copyWith(letterSpacing: 0),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// 智能练习长按：引擎配置状态。[config] 由调用方在弹窗前读取注入——
/// 浮窗挂根 Overlay（页面 Provider 树之上），面板内不能做 provider 查找。
class AiPanelBody extends StatelessWidget {
  final AiEngineConfig config;
  final VoidCallback? onEnter;

  const AiPanelBody({super.key, required this.config, this.onEnter});

  @override
  Widget build(BuildContext context) {
    final ready = config.isComplete;

    return InfoPanelShell(
      title: AppStrings.playSmartPracticeTitle,
      icon: TurnaIconId.spark,
      accentColor: TurnaTheme.brandTeal,
      onEnter: onEnter,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          InfoStaggeredRow(
            index: 1,
            child: InfoStatRow(
              label: AppStrings.playPopupAiEngine,
              value: ready
                  ? AppStrings.playAiEngineReady
                  : AppStrings.playAiEngineNotConfigured,
              dotColor: ready ? TurnaTheme.success : TurnaTheme.warning,
            ),
          ),
          InfoStaggeredRow(
            index: 2,
            child: InfoStatRow(
              label: AppStrings.playPopupAiProvider,
              value: config.preset.label,
            ),
          ),
          InfoStaggeredRow(
            index: 3,
            child: InfoStatRow(
              label: AppStrings.playPopupAiModel,
              value: config.modelChat,
            ),
          ),
          if (!ready)
            InfoStaggeredRow(
              index: 4,
              child: Padding(
                padding: const EdgeInsets.only(top: AppSpacing.sm - 2),
                child: Text(
                  AppStrings.playPopupAiNotReadyHint,
                  style: AppTextStyles.captionSm(context),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
