// Flutter imports:
import 'package:flutter/material.dart';

// Project imports:
import 'package:turna/application/ai/engine/ai_engine_config.dart';
import 'package:turna/application/study_stats_provider.dart';
import 'package:turna/domain/course/mistake_entry.dart';
import 'package:turna/domain/study/daily_stats.dart';
import 'package:turna/l10n/app_strings.dart';
import 'package:turna/views/play/components/info_popup.dart';
import 'package:turna/views/play/components/play_tiles.dart';
import 'package:turna/views/theme.dart';

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

  /// ADR 0037: imported Anki scopes only count the Anki queue.
  final bool ankiCourse;

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

/// 浮窗统一外壳：accent 头部（icon chip + 标题）+ 内容 + 「进入」底栏。
/// `onEnter` 由调用方负责「先关浮窗再导航」。
class InfoPanelShell extends StatelessWidget {
  final String title;
  final IconData icon;
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
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          InfoStaggeredRow(
            index: 0,
            child: Row(
              children: [
                AccentIconChip(icon: icon, color: accent, size: 20, padding: 8),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    title,
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w800,
                          color: TurnaTheme.textPrimaryColor(context),
                        ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 4),
          child,
          if (onEnter != null) ...[
            const SizedBox(height: 10),
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
        borderRadius: BorderRadius.circular(TurnaTheme.radiusMedium),
        child: Ink(
          decoration: TurnaTheme.primaryCtaDecoration(
            borderRadius: BorderRadius.circular(TurnaTheme.radiusMedium),
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  AppStrings.playPopupEnter,
                  style: Theme.of(context).textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.w800,
                        color: TurnaTheme.textOnPrimary,
                      ),
                ),
                const SizedBox(width: 4),
                const Icon(
                  Icons.arrow_forward_rounded,
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
      padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 7),
      child: Row(
        children: [
          if (dotColor != null) ...[
            Container(
              width: 8,
              height: 8,
              decoration:
                  BoxDecoration(color: dotColor, shape: BoxShape.circle),
            ),
            const SizedBox(width: 8),
          ],
          Expanded(
            child: Text(
              label,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: TurnaTheme.textSecondaryColor(context),
                  ),
            ),
          ),
          Text(
            value,
            style: Theme.of(context).textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.w800,
                  color: TurnaTheme.textPrimaryColor(context),
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
      padding: const EdgeInsets.only(top: 10, bottom: 2),
      child: Text(
        text,
        style: Theme.of(context).textTheme.labelSmall?.copyWith(
              fontWeight: FontWeight.w700,
              color: TurnaTheme.textHintColor(context),
              letterSpacing: 0.4,
            ),
      ),
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

/// 今日复习 Hero 长按：四个队列一览 + 高亮「下一个」。
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
    final ankiValue = snapshot.ankiUnavailable
        ? '—'
        : '${snapshot.ankiDueCount}';

    return InfoPanelShell(
      title: AppStrings.playTodayHeroTitle,
      icon: Icons.play_circle_fill_rounded,
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
      icon: Icons.priority_high_rounded,
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
    final answer =
        entry.correctAnswer.trim().isEmpty ? '—' : entry.correctAnswer.trim();
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 6),
      child: Row(
        children: [
          Expanded(
            child: Text(
              answer,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                    color: TurnaTheme.textPrimaryColor(context),
                  ),
            ),
          ),
          const SizedBox(width: 8),
          Text(
            _relativeDayLabel(entry.timestamp),
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: TurnaTheme.textHintColor(context),
                ),
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
      icon: Icons.repeat_rounded,
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
      icon: Icons.menu_book_rounded,
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

/// Anki 复习长按：导入牌组 + Official 牌组拆分。
class AnkiPanelBody extends StatelessWidget {
  final VoidCallback? onEnter;

  final PlayQueueSnapshot snapshot;

  const AnkiPanelBody({required this.snapshot, super.key, this.onEnter});

  @override
  Widget build(BuildContext context) {
    return InfoPanelShell(
      title: AppStrings.playAnkiReviewTitle,
      icon: Icons.style_rounded,
      accentColor: TurnaTheme.brandSky,
        onEnter: onEnter,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (snapshot.ankiUnavailable)
            InfoStaggeredRow(
              index: 1,
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Row(
                  children: [
                    Icon(
                      Icons.cloud_off_outlined,
                      size: 16,
                      color: TurnaTheme.warning,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        AppStrings.playPopupAnkiUnavailable,
                        style:
                            Theme.of(context).textTheme.bodySmall?.copyWith(
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
      icon: Icons.fitness_center_rounded,
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
      padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 6),
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
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        fontWeight: FontWeight.w600,
                        color: TurnaTheme.textPrimaryColor(context),
                      ),
                ),
                if (word.translation != null &&
                    word.translation!.trim().isNotEmpty)
                  Text(
                    word.translation!,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: TurnaTheme.textSecondaryColor(context),
                        ),
                  ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          CountBadge(
            label: AppStrings.playPopupWeakTimes(word.mistakeCount),
            color: TurnaTheme.anatolianClay,
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
      icon: Icons.show_chart_rounded,
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
            return const Padding(
              padding: EdgeInsets.symmetric(vertical: 12),
              child: Center(
                child: SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2.4),
                ),
              ),
            );
          }
          final days = data[0] as List<DailyStudyStats>;
          final totalReviews = data[1] as int;
          final totalMinutes = data[2] as int;
          final hasData =
              totalReviews > 0 || days.any((d) => d.reviewCount > 0);

          if (!hasData) {
            return Padding(
              padding: const EdgeInsets.symmetric(vertical: 14),
              child: Text(
                AppStrings.playPopupNoStatsYet,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: TurnaTheme.textHintColor(context),
                    ),
              ),
            );
          }

          return Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              InfoGroupLabel(AppStrings.playPopupRecent7Days),
              InfoStaggeredRow(
                index: 1,
                child: _WeeklyBars(days: days),
              ),
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
      height: barHeight + 22,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          for (final day in days)
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    Text(
                      '${day.reviewCount}',
                      style:
                          Theme.of(context).textTheme.labelSmall?.copyWith(
                                fontWeight: FontWeight.w700,
                                color: day.reviewCount == peak && peak > 0
                                    ? TurnaTheme.brandTeal
                                    : TurnaTheme.textHintColor(context),
                              ),
                    ),
                    const SizedBox(height: 4),
                    Container(
                      height: peak == 0
                          ? 4.0
                          : (day.reviewCount / peak) * barHeight,
                      decoration: BoxDecoration(
                        color: day.reviewCount > 0
                            ? TurnaTheme.brandTeal
                            : TurnaTheme.dividerBg(context),
                        borderRadius: const BorderRadius.vertical(
                          top: Radius.circular(3),
                        ),
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '${day.date.month}/${day.date.day}',
                      style:
                          Theme.of(context).textTheme.labelSmall?.copyWith(
                                color: TurnaTheme.textHintColor(context),
                              ),
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

/// AI 助手长按：引擎配置状态。[config] 由调用方在弹窗前读取注入——
/// 浮窗挂根 Overlay（页面 Provider 树之上），面板内不能做 provider 查找。
class AiPanelBody extends StatelessWidget {
  final AiEngineConfig config;
  final VoidCallback? onEnter;

  const AiPanelBody({super.key, required this.config, this.onEnter});

  @override
  Widget build(BuildContext context) {
    final ready = config.isComplete;

    return InfoPanelShell(
      title: AppStrings.playAiAssistantTitle,
      icon: Icons.auto_awesome_rounded,
      accentColor: TurnaTheme.amethystLeague,
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
                padding: const EdgeInsets.only(top: 6),
                child: Text(
                  AppStrings.playPopupAiNotReadyHint,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: TurnaTheme.textSecondaryColor(context),
                      ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
