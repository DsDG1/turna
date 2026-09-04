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
import 'package:turna/views/theme.dart';
import 'package:turna/views/widgets/practice_empty_state.dart';

/// Single-page mistake dashboard: KPI row, 14-day new-mistake trend, type
/// distribution, repeated mistakes and the oldest unconquered entries.
///
/// All data comes from [MistakeProvider] (active log + persisted aggregates);
/// the page itself stays stateless and cheap — no DAO / allEvents queries.
@RoutePage()
class MistakeDashboardPage extends StatelessWidget {
  const MistakeDashboardPage({super.key});

  @override
  Widget build(BuildContext context) {
    final entries = context.select((MistakeProvider p) => p.entries);
    final dailyCounts = context.select((MistakeProvider p) => p.dailyCounts);
    final masteredTotal = context.select((MistakeProvider p) => p.masteredTotal);

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
              onRefresh: () async {
                context.read<MistakeProvider>().reloadFromPrefs();
                // Keep the spinner visible briefly so the gesture reads back.
                await Future<void>.delayed(const Duration(milliseconds: 400));
              },
              child: ListView(
                physics: const AlwaysScrollableScrollPhysics(
                  parent: BouncingScrollPhysics(),
                ),
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
                children: [
                  _KpiRow(
                    entries: entries,
                    masteredTotal: masteredTotal,
                  ),
                  const SizedBox(height: 12),
                  _TrendCard(dailyCounts: dailyCounts),
                  const SizedBox(height: 12),
                  _DistributionCard(entries: entries),
                  if (_frequentMistakes(entries).isNotEmpty) ...[
                    const SizedBox(height: 12),
                    _FrequentCard(entries: entries),
                  ],
                  if (entries.isNotEmpty) ...[
                    const SizedBox(height: 12),
                    _OldestCard(entries: entries),
                  ],
                ],
              ),
            ),
    );
  }
}

// ─── KPI row ───────────────────────────────────────────────────────────────

class _KpiRow extends StatelessWidget {
  const _KpiRow({required this.entries, required this.masteredTotal});

  final List<MistakeEntry> entries;
  final int masteredTotal;

  @override
  Widget build(BuildContext context) {
    final toConsolidate = entries
        .where(
          (e) => e.rewriteCount > 0 && e.rewriteCount < MistakeProvider.rewriteGoal,
        )
        .length;
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 20),
      decoration: _cardDecoration(context),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Flexible 防止多语言长 label 在窄屏上把整行挤爆（同错题列表头部）。
          Flexible(
            child: _KpiItem(
              icon: Icons.error_outline_rounded,
              iconColor: TurnaTheme.error,
              value: entries.length.toString(),
              label: AppStrings.mistakeDashboardActiveLabel,
            ),
          ),
          _kpiDivider(context),
          Flexible(
            child: _KpiItem(
              icon: Icons.verified_outlined,
              iconColor: TurnaTheme.brandTeal,
              value: masteredTotal.toString(),
              label: AppStrings.mistakeDashboardMasteredLabel,
            ),
          ),
          _kpiDivider(context),
          Flexible(
            child: _KpiItem(
              icon: Icons.refresh_rounded,
              iconColor: TurnaTheme.warning,
              value: toConsolidate.toString(),
              label: AppStrings.mistakeDashboardConsolidateLabel,
            ),
          ),
        ],
      ),
    );
  }

  Widget _kpiDivider(BuildContext context) => Container(
        width: 1,
        height: 40,
        margin: const EdgeInsets.symmetric(horizontal: 4),
        color: TurnaTheme.dividerBg(context),
      );
}

class _KpiItem extends StatelessWidget {
  const _KpiItem({
    required this.icon,
    required this.iconColor,
    required this.value,
    required this.label,
  });

  final IconData icon;
  final Color iconColor;
  final String value;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, color: iconColor, size: 22),
        const SizedBox(height: 6),
        Text(
          value,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: Theme.of(context).textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w800,
              ),
        ),
        const SizedBox(height: 2),
        Text(
          label,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: TurnaTheme.textHintColor(context),
                fontWeight: FontWeight.w500,
              ),
        ),
      ],
    );
  }
}

// ─── 14-day trend ──────────────────────────────────────────────────────────

class _TrendCard extends StatelessWidget {
  const _TrendCard({required this.dailyCounts});

  final Map<String, int> dailyCounts;

  @override
  Widget build(BuildContext context) {
    final buckets = _buildBuckets(dailyCounts);
    final activeDays = buckets.where((c) => c > 0).length;
    final total = buckets.fold<int>(0, (a, b) => a + b);

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: _cardDecoration(context),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _sectionHeader(
            context,
            icon: Icons.show_chart_rounded,
            title: AppStrings.mistakeDashboardTrendTitle,
          ),
          const SizedBox(height: 12),
          if (total == 0)
            Text(
              AppStrings.mistakeDashboardTrendEmpty,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: TurnaTheme.textHintColor(context),
                  ),
            )
          else ...[
            SizedBox(
              // 52px 柱高上限 + 4 间距 + 日标签行高，留余量防溢出。
              height: 72,
              child: _TrendChart(counts: buckets),
            ),
            const SizedBox(height: 6),
            // 文本语义摘要（无障碍：图表不只用颜色表达）。
            Text(
              AppStrings.mistakeDashboardTrendSummary(activeDays, total),
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: TurnaTheme.textHintColor(context),
                  ),
            ),
          ],
        ],
      ),
    );
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

/// Light 14-point bar chart painted once (same approach as the review
/// dashboard's 7-day chart; no per-frame animation).
class _TrendChart extends StatelessWidget {
  const _TrendChart({required this.counts});

  final List<int> counts;

  @override
  Widget build(BuildContext context) {
    final maxCount = counts.fold<int>(0, (a, b) => a > b ? a : b);
    final today = DateTime.now();
    return Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        for (var i = 0; i < counts.length; i++) ...[
          if (i > 0) const SizedBox(width: 4),
          Expanded(
            child: Column(
              children: [
                Expanded(
                  child: LayoutBuilder(
                    builder: (context, constraints) {
                      final maxH = constraints.maxHeight;
                      final count = counts[i];
                      final h = maxCount == 0 || count == 0
                          ? 4.0.clamp(0.0, maxH)
                          : (4.0 + (maxH - 4.0) * count / maxCount)
                              .clamp(4.0, maxH);
                      return Align(
                        alignment: Alignment.bottomCenter,
                        child: Container(
                          width: constraints.maxWidth,
                          height: h,
                          decoration: BoxDecoration(
                            color: count == 0
                                ? TurnaTheme.dividerBg(context)
                                : TurnaTheme.brandTeal.withValues(
                                    alpha: 0.45 + 0.55 * count / maxCount,
                                  ),
                            borderRadius: BorderRadius.circular(3),
                          ),
                        ),
                      );
                    },
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  _dayLabel(today, i),
                  maxLines: 1,
                  overflow: TextOverflow.clip,
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                        fontSize: 9,
                        height: 1.0,
                        color: TurnaTheme.textHintColor(context),
                      ),
                ),
              ],
            ),
          ),
        ],
      ],
    );
  }

  /// Day-of-month label for bucket [i]; only the first, middle and last bars
  /// get a label so 14 columns don't crowd.
  String _dayLabel(DateTime today, int i) {
    final isEdge = i == 0 || i == counts.length - 1 || i == counts.length ~/ 2;
    if (!isEdge) return '';
    final day = today.subtract(Duration(days: counts.length - 1 - i));
    return '${day.day}';
  }
}

// ─── Type distribution ─────────────────────────────────────────────────────

class _DistributionCard extends StatelessWidget {
  const _DistributionCard({required this.entries});

  final List<MistakeEntry> entries;

  @override
  Widget build(BuildContext context) {
    final wordCount = entries.where((e) => e.wordId != null).length;
    final grammarCount = entries.where((e) => e.grammarPointId != null).length;
    final otherCount = entries.length - wordCount - grammarCount;
    final total = entries.length;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: _cardDecoration(context),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _sectionHeader(
            context,
            icon: Icons.donut_small_rounded,
            title: AppStrings.mistakeDashboardDistributionTitle,
          ),
          const SizedBox(height: 12),
          if (total == 0)
            Text(
              AppStrings.mistakeDashboardTrendEmpty,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: TurnaTheme.textHintColor(context),
                  ),
            )
          else ...[
            _ProportionBar(
              wordCount: wordCount,
              grammarCount: grammarCount,
              otherCount: otherCount,
            ),
            const SizedBox(height: 12),
            _legendRow(
              context,
              color: TurnaTheme.brandTeal,
              label: AppStrings.reviewWordsLabel,
              count: wordCount,
              total: total,
            ),
            const SizedBox(height: 6),
            _legendRow(
              context,
              color: TurnaTheme.leagueAmethyst,
              label: AppStrings.reviewGrammarLabel,
              count: grammarCount,
              total: total,
            ),
            if (otherCount > 0) ...[
              const SizedBox(height: 6),
              _legendRow(
                context,
                color: TurnaTheme.textHint,
                label: AppStrings.mistakeDashboardOtherType,
                count: otherCount,
                total: total,
              ),
            ],
          ],
        ],
      ),
    );
  }

  Widget _legendRow(
    BuildContext context, {
    required Color color,
    required String label,
    required int count,
    required int total,
  }) {
    final percent = total == 0 ? 0 : (count * 100 / total).round();
    return Row(
      children: [
        Container(
          width: 10,
          height: 10,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            label,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
          ),
        ),
        Text(
          '$count · $percent%',
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: TurnaTheme.textSecondaryColor(context),
              ),
        ),
      ],
    );
  }
}

class _ProportionBar extends StatelessWidget {
  const _ProportionBar({
    required this.wordCount,
    required this.grammarCount,
    required this.otherCount,
  });

  final int wordCount;
  final int grammarCount;
  final int otherCount;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(TurnaTheme.radiusRound),
      child: SizedBox(
        height: 10,
        child: Row(
          children: [
            if (wordCount > 0)
              Expanded(
                flex: wordCount,
                child: Container(color: TurnaTheme.brandTeal),
              ),
            if (grammarCount > 0)
              Expanded(
                flex: grammarCount,
                child: Container(color: TurnaTheme.leagueAmethyst),
              ),
            if (otherCount > 0)
              Expanded(
                flex: otherCount,
                child: Container(color: TurnaTheme.textHint),
              ),
          ],
        ),
      ),
    );
  }
}

// ─── Frequent mistakes ─────────────────────────────────────────────────────

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
    return grammarPointById[entry.grammarPointId!]?.title ?? entry.interactionId;
  }
  return entry.interactionId.isNotEmpty
      ? entry.interactionId
      : AppStrings.reviewUnknownQuestion;
}

class _FrequentCard extends StatelessWidget {
  const _FrequentCard({required this.entries});

  final List<MistakeEntry> entries;

  @override
  Widget build(BuildContext context) {
    final frequent = _frequentMistakes(entries);
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: _cardDecoration(context),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _sectionHeader(
            context,
            icon: Icons.repeat_rounded,
            title: AppStrings.mistakeDashboardFrequentTitle,
          ),
          const SizedBox(height: 8),
          for (var i = 0; i < frequent.length; i++) ...[
            if (i > 0) const SizedBox(height: 4),
            Row(
              children: [
                Expanded(
                  child: Text(
                    frequent[i].title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                  ),
                ),
                const SizedBox(width: 8),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  decoration: BoxDecoration(
                    color: TurnaTheme.error.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Text(
                    AppStrings.mistakeDashboardTimes(frequent[i].count),
                    style: Theme.of(context).textTheme.labelSmall?.copyWith(
                          color: TurnaTheme.error,
                          fontWeight: FontWeight.w700,
                        ),
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

// ─── Oldest unconquered ────────────────────────────────────────────────────

class _OldestCard extends StatelessWidget {
  const _OldestCard({required this.entries});

  final List<MistakeEntry> entries;

  @override
  Widget build(BuildContext context) {
    final oldest = [...entries]..sort((a, b) => a.timestamp.compareTo(b.timestamp));
    final top = oldest.take(3).toList();
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: _cardDecoration(context),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _sectionHeader(
            context,
            icon: Icons.hourglass_top_rounded,
            title: AppStrings.mistakeDashboardOldestTitle,
          ),
          const SizedBox(height: 8),
          for (var i = 0; i < top.length; i++) ...[
            if (i > 0) const SizedBox(height: 4),
            Row(
              children: [
                Expanded(
                  child: Text(
                    _entryTitle(top[i]),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  AppStrings.timeAgo(top[i].timestamp),
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                        color: TurnaTheme.textHintColor(context),
                      ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

// ─── Shared bits ───────────────────────────────────────────────────────────

BoxDecoration _cardDecoration(BuildContext context) => BoxDecoration(
      color: TurnaTheme.cardBg(context),
      borderRadius: BorderRadius.circular(TurnaTheme.radiusLarge),
      border: Border.all(color: TurnaTheme.statCardBorder(context)),
    );

Widget _sectionHeader(
  BuildContext context, {
  required IconData icon,
  required String title,
}) {
  return Row(
    children: [
      Icon(icon, color: TurnaTheme.brandTeal, size: 20),
      const SizedBox(width: 8),
      Text(
        title,
        style: Theme.of(context).textTheme.titleSmall?.copyWith(
              fontWeight: FontWeight.w700,
            ),
      ),
    ],
  );
}
