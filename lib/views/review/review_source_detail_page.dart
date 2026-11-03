import 'package:auto_route/auto_route.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:turna/application/review_dashboard/insights_repository.dart';
import 'package:turna/application/review_dashboard/review_data_revision.dart';
import 'package:turna/application/review_progress_provider.dart';
import 'package:turna/di/injection.dart';
import 'package:turna/domain/review/review_activity.dart';
import 'package:turna/l10n/app_strings.dart';
import 'package:turna/routing/routing.gr.dart';
import 'package:turna/core/spacing.dart';
import 'package:turna/views/widgets/report_kit.dart';
import 'package:turna/views/widgets/session_shell.dart';
import 'package:turna/core/theme.dart';

/// 来源详情 ——「湿地雾光」R10 学习报告构图：核心指标开篇（今日到期）→
/// 近 14 天活动柱状（主图）→ 辅助指标定义列表 → 单一主行动（开始该来源
/// 复习）。查询窗口与数据接缝不变（[InsightsRepository] d30 + 按来源过滤）。
@RoutePage()
class ReviewSourceDetailPage extends StatefulWidget {
  const ReviewSourceDetailPage({super.key, required this.source});

  final ReviewSource source;

  @override
  State<ReviewSourceDetailPage> createState() => _ReviewSourceDetailPageState();
}

class _ReviewSourceDetailPageState extends State<ReviewSourceDetailPage> {
  late final ReviewProgressProvider _progress;
  late final InsightsRepository _insights;
  late Future<_SourceDetailData> _future;

  @override
  void initState() {
    super.initState();
    _progress = context.read<ReviewProgressProvider>();
    _insights = InsightsRepository(_progress, getIt<ReviewDataRevision>());
    _future = _load();
  }

  Future<_SourceDetailData> _load() async {
    final active = widget.source.active;
    final snapshot = await _insights.load(InsightsQuery(
      range: EventRange.d30,
      source: widget.source,
      type: ProgressTypeFilter.all,
    ));
    return _SourceDetailData(active: active, snapshot: snapshot);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(widget.source.label)),
      body: FutureBuilder<_SourceDetailData>(
        future: _future,
        builder: (context, state) {
          final data = state.data;
          if (data == null) {
            if (state.hasError) {
              return Center(
                child: FilledButton.icon(
                  onPressed: () => setState(() => _future = _load()),
                  icon: const Icon(Icons.refresh_rounded),
                  label: Text(AppStrings.reviewSourceReload),
                ),
              );
            }
            return const Center(child: CircularProgressIndicator());
          }
          final summary = data.snapshot.aggregate;
          final activity = data.snapshot.activity;
          final todayCompleted =
              activity.isEmpty ? 0 : activity.last.reviewedCount;
          final reviews7 = activity
              .skip(activity.length > 7 ? activity.length - 7 : 0)
              .fold<int>(0, (sum, row) => sum + row.reviewedCount);
          final reviews30 = activity
              .skip(activity.length > 30 ? activity.length - 30 : 0)
              .fold<int>(0, (sum, row) => sum + row.reviewedCount);
          final trendWindow = activity.length > 14
              ? activity.sublist(activity.length - 14)
              : activity;

          return Center(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.pageMargin,
                AppSpacing.md,
                AppSpacing.pageMargin,
                AppSpacing.xxl,
              ),
              children: [
                if (!data.active)
                  const ReviewSourceAvailabilityBanner(active: false),
                ReportMetricHeader(
                  label: AppStrings.reviewSourceMetricDueToday,
                  value: '${summary.forecast.dueToday}',
                  caption: AppStrings.reviewSourceMetricNewCards(
                      summary.maturity.newCards),
                ),
                const SizedBox(height: AppSpacing.xl),
                _TrendSection(
                  window: trendWindow,
                  reviews7: reviews7,
                  reviews30: reviews30,
                ),
                const SizedBox(height: AppSpacing.xl),
                ReportDefinitionList(
                  rows: [
                    ReportDefinitionRow(
                      label: AppStrings.reviewSourceMetricDoneToday,
                      value: '$todayCompleted',
                    ),
                    ReportDefinitionRow(
                      label: AppStrings.reviewProgressKpiReviews,
                      value: '${summary.totalReviews}',
                    ),
                  ],
                ),
                if (data.active) ...[
                  const SizedBox(height: AppSpacing.xl),
                  SessionPrimaryAction(
                    label: AppStrings.reviewSourceStartReview,
                    onPressed: _startReview,
                    trailingIcon: Icons.play_arrow_rounded,
                  ),
                ],
              ],
            ),
          );
        },
      ),
    );
  }

  void _startReview() {
    switch (widget.source.kind) {
      case ReviewSourceKind.course:
        context.router.push(const SrsReviewRoute());
        return;
      case ReviewSourceKind.grammar:
        context.router.push(const GrammarReviewRoute());
        return;
      case ReviewSourceKind.ankiDeck:
      case ReviewSourceKind.ankiOfficial:
        context.router.push(const AnkiReviewRoute());
        return;
      case ReviewSourceKind.all:
        context.router.push(const SrsReviewRoute());
        return;
    }
  }
}

/// 近 14 天活动（主图 · 柱状）+ 7 / 30 日趋势摘要。
class _TrendSection extends StatelessWidget {
  const _TrendSection({
    required this.window,
    required this.reviews7,
    required this.reviews30,
  });

  final List<ActivityBucketRow> window;
  final int reviews7;
  final int reviews30;

  @override
  Widget build(BuildContext context) {
    final windowTotal = window.fold<int>(0, (sum, row) => sum + row.reviewedCount);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ReportSectionHeading(title: AppStrings.reviewSourceTrendTitle),
        if (windowTotal == 0)
          Text(
            AppStrings.reviewProgressEmpty,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: TurnaTheme.textHintColor(context),
                ),
          )
        else ...[
          ReportBarChart(
            semanticsLabel:
                AppStrings.reviewSevenDayChartSemantics(windowTotal),
            height: 150,
            bars: [
              for (var i = 0; i < window.length; i++)
                ReportBar(
                  // 首尾两天给日期标签，中间不挤字。
                  label: (i == 0 || i == window.length - 1)
                      ? _dayLabel(window[i].bucket)
                      : '',
                  value: window[i].reviewedCount.toDouble(),
                  highlight: i == window.length - 1,
                ),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          Text(
            AppStrings.reviewSourceTrendSummary(reviews7, reviews30),
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: TurnaTheme.textHintColor(context),
                ),
          ),
        ],
      ],
    );
  }

  /// bucket 是「YYYY-MM-DD」格式的日期键，只取「日」作标签。
  static String _dayLabel(String bucket) {
    final parts = bucket.split('-');
    return parts.length == 3 ? '${int.tryParse(parts[2]) ?? ''}' : '';
  }
}

class ReviewSourceAvailabilityBanner extends StatelessWidget {
  const ReviewSourceAvailabilityBanner({super.key, required this.active});

  final bool active;

  @override
  Widget build(BuildContext context) {
    if (active) return const SizedBox.shrink();
    return Card(
      color: TurnaTheme.warning.withValues(alpha: 0.12),
      child: ListTile(
        leading: const Icon(Icons.inventory_2_outlined),
        title: Text(AppStrings.reviewSourceDeletedTitle),
        subtitle: Text(AppStrings.reviewSourceDeletedSubtitle),
      ),
    );
  }
}

class _SourceDetailData {
  const _SourceDetailData({required this.active, required this.snapshot});
  final bool active;
  final ReviewProgressSnapshot snapshot;
}
