// Flutter imports:
import 'package:flutter/material.dart';

// Package imports:
import 'package:auto_route/auto_route.dart';
import 'package:provider/provider.dart';

// Project imports:
import 'package:turna/application/mistake_provider.dart';
import 'package:turna/courses/languages/grammar_points.dart';
import 'package:turna/courses/languages/vocab.dart';
import 'package:turna/domain/course/mistake_entry.dart';
import 'package:turna/l10n/app_strings.dart';
import 'package:turna/core/spacing.dart';
import 'package:turna/core/theme.dart';
import 'package:turna/views/widgets/practice_empty_state.dart';
import 'package:turna/views/widgets/report_kit.dart';

/// 错题仪表盘 ——「湿地雾光」R09/R10 学习报告构图。
///
/// 一个核心指标开篇（活跃错题）→ 主图独立段落（近 14 天错题柱状）→ 辅助
/// 指标按解释顺序（类型构成、高频错题、最久未攻克）。数据全部来自
/// [MistakeProvider]（活跃日志 + 持久化聚合），页面无 DAO 查询。
@RoutePage()
class MistakeDashboardPage extends StatelessWidget {
  const MistakeDashboardPage({super.key});

  @override
  Widget build(BuildContext context) {
    final entries = context.select((MistakeProvider p) => p.entries);
    final dailyCounts = context.select((MistakeProvider p) => p.dailyCounts);
    final masteredTotal =
        context.select((MistakeProvider p) => p.masteredTotal);

    final hasAnyData =
        entries.isNotEmpty || dailyCounts.isNotEmpty || masteredTotal > 0;

    return Scaffold(
      backgroundColor: TurnaTheme.scaffoldBg(context),
      appBar: AppBar(title: Text(AppStrings.mistakeDashboardTitle)),
      body: !hasAnyData
          ? PracticeEmptyState(
              title: AppStrings.mistakeDashboardEmptyTitle,
              message: AppStrings.mistakeDashboardEmptyMessage,
            )
          : RefreshIndicator(
              color: TurnaTheme.brandTeal,
              onRefresh: () =>
                  context.read<MistakeProvider>().reloadFromPrefs(),
              child: ListView(
                physics: const AlwaysScrollableScrollPhysics(
                  parent: BouncingScrollPhysics(),
                ),
                padding: const EdgeInsets.fromLTRB(
                  AppSpacing.pageMargin,
                  AppSpacing.md,
                  AppSpacing.pageMargin,
                  AppSpacing.xxl,
                ),
                children: [
                  _MetricOpening(entries: entries, masteredTotal: masteredTotal),
                  const SizedBox(height: AppSpacing.xl),
                  _TrendSection(dailyCounts: dailyCounts),
                  const SizedBox(height: AppSpacing.xl),
                  _DistributionSection(entries: entries),
                  if (_frequentMistakes(entries).isNotEmpty) ...[
                    const SizedBox(height: AppSpacing.xl),
                    _FrequentSection(entries: entries),
                  ],
                  if (entries.isNotEmpty) ...[
                    const SizedBox(height: AppSpacing.xl),
                    _OldestSection(entries: entries),
                  ],
                ],
              ),
            ),
    );
  }
}

// ── 核心指标开篇 ───────────────────────────────────────────────────────────

class _MetricOpening extends StatelessWidget {
  const _MetricOpening({required this.entries, required this.masteredTotal});

  final List<MistakeEntry> entries;
  final int masteredTotal;

  @override
  Widget build(BuildContext context) {
    final toConsolidate = entries
        .where(
          (e) =>
              e.rewriteCount > 0 &&
              e.rewriteCount < MistakeProvider.rewriteGoal,
        )
        .length;
    return ReportMetricHeader(
      label: AppStrings.mistakeDashboardActiveLabel,
      value: '${entries.length}',
      caption:
          '${AppStrings.mistakeDashboardMasteredLabel} $masteredTotal · '
          '${AppStrings.mistakeDashboardConsolidateLabel} $toConsolidate',
    );
  }
}

// ── 近 14 天趋势（主图） ───────────────────────────────────────────────────

class _TrendSection extends StatelessWidget {
  const _TrendSection({required this.dailyCounts});

  final Map<String, int> dailyCounts;

  @override
  Widget build(BuildContext context) {
    final buckets = _buildBuckets(dailyCounts);
    final activeDays = buckets.where((c) => c > 0).length;
    final total = buckets.fold<int>(0, (a, b) => a + b);
    final today = DateTime.now();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ReportSectionHeading(title: AppStrings.mistakeDashboardTrendTitle),
        if (total == 0)
          Text(
            AppStrings.mistakeDashboardTrendEmpty,
            style: TextStyle(
              fontSize: 13,
              color: TurnaTheme.textHintColor(context),
            ),
          )
        else ...[
          ReportBarChart(
            semanticsLabel: AppStrings.reviewMistakeTrendChartSemantics(total),
            height: 150,
            bars: [
              for (var i = 0; i < buckets.length; i++)
                ReportBar(
                  // 只给首 / 中 / 尾三根柱标签，14 列不挤字（沿用旧图节奏）。
                  label: _isEdge(i, buckets.length)
                      ? _dayLabel(today, buckets.length, i)
                      : '',
                  value: buckets[i].toDouble(),
                  highlight: i == buckets.length - 1,
                ),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          // 文本语义摘要（无障碍：图表不只用颜色表达）。
          Text(
            AppStrings.mistakeDashboardTrendSummary(activeDays, total),
            style: TextStyle(
              fontSize: 13,
              color: TurnaTheme.textHintColor(context),
            ),
          ),
        ],
      ],
    );
  }

  static bool _isEdge(int i, int length) =>
      i == 0 || i == length - 1 || i == length ~/ 2;

  static String _dayLabel(DateTime today, int length, int i) {
    final day = today.subtract(Duration(days: length - 1 - i));
    return '${day.day}';
  }

  /// One count per local day, oldest first, covering the last 14 days.
  static List<int> _buildBuckets(Map<String, int> dailyCounts) {
    final today = DateTime.now();
    final todayMidnight = DateTime(today.year, today.month, today.day);
    return [
      for (var i = 13; i >= 0; i--)
        dailyCounts[MistakeProvider.dayKey(
              todayMidnight.subtract(Duration(days: i)),
            )] ??
            0,
    ];
  }
}

// ── 类型构成 ───────────────────────────────────────────────────────────────

class _DistributionSection extends StatelessWidget {
  const _DistributionSection({required this.entries});

  final List<MistakeEntry> entries;

  @override
  Widget build(BuildContext context) {
    final wordCount = entries.where((e) => e.wordId != null).length;
    final grammarCount = entries.where((e) => e.grammarPointId != null).length;
    final otherCount = entries.length - wordCount - grammarCount;
    final total = entries.length;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ReportSectionHeading(title: AppStrings.mistakeDashboardDistributionTitle),
        if (total == 0)
          Text(
            AppStrings.mistakeDashboardTrendEmpty,
            style: TextStyle(
              fontSize: 13,
              color: TurnaTheme.textHintColor(context),
            ),
          )
        else
          ReportCompositionBar(
            segments: [
              ReportSegment(
                label: AppStrings.reviewWordsLabel,
                value: wordCount.toDouble(),
                color: TurnaTheme.brandTeal,
                valueLabel: _legendValue(wordCount, total),
              ),
              ReportSegment(
                label: AppStrings.reviewGrammarLabel,
                value: grammarCount.toDouble(),
                color: TurnaTheme.leagueAmethyst,
                valueLabel: _legendValue(grammarCount, total),
              ),
              if (otherCount > 0)
                ReportSegment(
                  label: AppStrings.mistakeDashboardOtherType,
                  value: otherCount.toDouble(),
                  color: TurnaTheme.textHint,
                  valueLabel: _legendValue(otherCount, total),
                ),
            ],
          ),
      ],
    );
  }

  static String _legendValue(int count, int total) {
    final percent = total == 0 ? 0 : (count * 100 / total).round();
    return '$count · $percent%';
  }
}

// ── 高频错题 ───────────────────────────────────────────────────────────────

/// Entries grouped by word / grammar id that occurred 2+ times, most
/// repeated first, top 5. Empty when nothing repeats.
List<({String title, int count})> _frequentMistakes(
  List<MistakeEntry> entries,
) {
  final counts = <String, int>{};
  final representative = <String, MistakeEntry>{};
  for (final e in entries) {
    final key = e.wordId ?? e.grammarPointId;
    if (key == null) continue;
    counts[key] = (counts[key] ?? 0) + 1;
    representative[key] = e;
  }
  final repeated = counts.entries.where((c) => c.value >= 2).toList()
    ..sort((a, b) => b.value.compareTo(a.value));
  return [
    for (final c in repeated.take(5))
      (title: _entryTitle(representative[c.key]!), count: c.value),
  ];
}

/// Best-effort display title for an entry: word term, grammar point title or
/// the interaction id.
String _entryTitle(MistakeEntry entry) {
  if (entry.wordId != null) {
    return vocabById[entry.wordId!]?.term ?? entry.interactionId;
  }
  if (entry.grammarPointId != null) {
    return grammarPointById[entry.grammarPointId!]?.title ??
        entry.interactionId;
  }
  return entry.interactionId.isNotEmpty
      ? entry.interactionId
      : AppStrings.reviewUnknownQuestion;
}

class _FrequentSection extends StatelessWidget {
  const _FrequentSection({required this.entries});

  final List<MistakeEntry> entries;

  @override
  Widget build(BuildContext context) {
    final frequent = _frequentMistakes(entries);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ReportSectionHeading(title: AppStrings.mistakeDashboardFrequentTitle),
        ReportDefinitionList(
          rows: [
            for (final item in frequent)
              ReportDefinitionRow(
                label: item.title,
                value: AppStrings.mistakeDashboardTimes(item.count),
                valueColor: TurnaTheme.error,
              ),
          ],
        ),
      ],
    );
  }
}

// ── 最久未攻克 ─────────────────────────────────────────────────────────────

class _OldestSection extends StatelessWidget {
  const _OldestSection({required this.entries});

  final List<MistakeEntry> entries;

  @override
  Widget build(BuildContext context) {
    final oldest = [...entries]
      ..sort((a, b) => a.timestamp.compareTo(b.timestamp));
    final top = oldest.take(3).toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ReportSectionHeading(title: AppStrings.mistakeDashboardOldestTitle),
        ReportDefinitionList(
          rows: [
            for (final entry in top)
              ReportDefinitionRow(
                label: _entryTitle(entry),
                value: AppStrings.timeAgo(entry.timestamp),
              ),
          ],
        ),
      ],
    );
  }
}
