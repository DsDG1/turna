// Flutter imports:
import 'package:flutter/material.dart';

// Package imports:
import 'package:auto_route/auto_route.dart';
import 'package:provider/provider.dart';

// Project imports:
import 'package:turna/application/review_dashboard/review_dashboard_models.dart';
import 'package:turna/application/review_dashboard/review_dashboard_repository.dart';
import 'package:turna/application/review_progress_provider.dart';
import 'package:turna/application/accessibility_capabilities.dart';
import 'package:turna/l10n/app_strings.dart';
import 'package:turna/routing/routing.gr.dart';
import 'package:turna/core/spacing.dart';
import 'package:turna/core/theme.dart';
import 'package:turna/views/widgets/directory_rows.dart';
import 'package:turna/views/widgets/report_kit.dart';
import 'package:turna/views/widgets/session_shell.dart';
import 'package:turna/views/widgets/turna_page_content.dart';

/// Review-overview home (Plan 3 §15.1) ——「湿地雾光」R10 学习报告构图.
///
/// Information order: 一个核心指标开篇（今日待复习 + 单一主行动）→ 到期
/// 构成 → 连续与近 7 天柱状（主图）→ 今日质量 → 来源行（真实下钻）→
/// link to the full 学习洞察 page. Heavy analytics (heatmap, memory curve,
/// maturity) live on [LearningInsightsPage].
///
/// Loading semantics (§17.3): first open without cache shows a matching
/// skeleton; refreshes keep the old content visible with a thin progress
/// indicator. Pull-to-refresh awaits the *actual* repository future (§14.7)
/// and filter-free reloads never flash a full-page spinner.
@RoutePage()
class ReviewProgressPage extends StatefulWidget {
  const ReviewProgressPage({super.key});

  @override
  State<ReviewProgressPage> createState() => _ReviewProgressPageState();
}

class _ReviewProgressPageState extends State<ReviewProgressPage> {
  ReviewDashboardSnapshot? _snapshot;
  Future<ReviewDashboardSnapshot>? _load;
  Object? _error;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _reload();
    });
  }

  void _reload({bool forceRefresh = false}) {
    final repo = context.read<ReviewDashboardRepository>();
    // Show cached snapshot instantly (stale-while-revalidate).
    final cached = repo.cachedSnapshot;
    if (cached != null) {
      setState(() {
        _snapshot = cached;
        _error = null;
      });
    }
    setState(() {
      _load = repo.loadDashboard(forceRefresh: forceRefresh);
    });
    _load!.then((snap) {
      if (!mounted) return;
      setState(() {
        _snapshot = snap;
        _error = null;
      });
    }).catchError((Object error) {
      if (!mounted) return;
      setState(() => _error = error);
    });
  }

  /// The Future the RefreshIndicator awaits: the actual repository load, so
  /// the spinner only dismisses when data has really arrived (Plan 3 §14.7).
  Future<void> _refresh() {
    final repo = context.read<ReviewDashboardRepository>();
    return repo.loadDashboard(forceRefresh: true).then((snap) {
      if (!mounted) return;
      setState(() {
        _snapshot = snap;
        _error = null;
      });
    }).catchError((Object error) {
      if (mounted) setState(() => _error = error);
    });
  }

  @override
  Widget build(BuildContext context) {
    final snap = _snapshot;
    final focusMode = accessibilityOf(context).focusMode;
    return Scaffold(
      backgroundColor: TurnaTheme.scaffoldBg(context),
      appBar: AppBar(
        title: Text(AppStrings.reviewDashboardTitle),
        backgroundColor: TurnaTheme.scaffoldBg(context),
        actions: [
          IconButton(
            tooltip: AppStrings.reviewInsightsTitle,
            icon: const Icon(Icons.insights_rounded),
            onPressed: () => context.router.push(const LearningInsightsRoute()),
          ),
        ],
      ),
      body: TurnaPageContent(
        maxWidth: 840,
        child: _error != null && snap == null
            ? _ErrorState(
                message: '$_error', onRetry: () => _reload(forceRefresh: true))
            : snap == null
                ? const _DashboardSkeleton()
                : RefreshIndicator(
                    color: TurnaTheme.brandTeal,
                    onRefresh: _refresh,
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
                        if (_error != null)
                          Padding(
                            padding: const EdgeInsets.only(bottom: 8),
                            child: _InlineErrorBanner(
                              onRetry: () => _reload(forceRefresh: true),
                            ),
                          ),
                        _MetricOpening(snapshot: snap),
                        const SizedBox(height: AppSpacing.xl),
                        SessionPrimaryAction(
                          label: snap.due.actionableTotal > 0
                              ? AppStrings.reviewContinueCta
                              : AppStrings.reviewTodayDoneCta,
                          onPressed: snap.due.actionableTotal > 0
                              ? () =>
                                  context.router.push(const SrsReviewRoute())
                              : null,
                          trailingIcon: Icons.play_arrow_rounded,
                        ),
                        const SizedBox(height: AppSpacing.xl),
                        _DueDefinitionList(snapshot: snap),
                        if (!focusMode) ...[
                          const SizedBox(height: AppSpacing.xl),
                          _WeeklyChartSection(snapshot: snap),
                          const SizedBox(height: AppSpacing.xl),
                          _TodayQualitySection(snapshot: snap),
                          const SizedBox(height: AppSpacing.xl),
                          _SourceList(snapshot: snap),
                          const SizedBox(height: AppSpacing.lg),
                          OutlinedButton.icon(
                            onPressed: () => context.router
                                .push(const LearningInsightsRoute()),
                            icon: const Icon(Icons.insights_rounded, size: 18),
                            label: Text(AppStrings.reviewOpenInsights),
                          ),
                        ],
                      ],
                    ),
                  ),
      ),
    );
  }
}

// ── 核心指标开篇 + 单一主行动 ─────────────────────────────────────────────

class _MetricOpening extends StatelessWidget {
  const _MetricOpening({required this.snapshot});

  final ReviewDashboardSnapshot snapshot;

  @override
  Widget build(BuildContext context) {
    final due = snapshot.due;
    final today = snapshot.today;
    final dateLabel =
        '${snapshot.generatedAt.month} ${AppStrings.reviewMonthDay(snapshot.generatedAt.day)}';
    final goalCaption = today.hasGoal && today.todayXp != null
        ? '${AppStrings.reviewTodayGoalProgress(today.todayXp!, today.xpGoal!)} · $dateLabel'
        : '${AppStrings.reviewTodayReviewed(today.reviewedToday)} · $dateLabel';

    return ReportMetricHeader(
      label: AppStrings.reviewMetricDueToday,
      value: '${due.actionableTotal}',
      caption: goalCaption,
      accentColor: due.actionableTotal > 0
          ? TurnaTheme.brandTealDark
          : TurnaTheme.textHintColor(context),
    );
  }
}

// ── 到期构成（辅助指标 · 定义列表） ────────────────────────────────────────

class _DueDefinitionList extends StatelessWidget {
  const _DueDefinitionList({required this.snapshot});

  final ReviewDashboardSnapshot snapshot;

  @override
  Widget build(BuildContext context) {
    final due = snapshot.due;
    return ReportDefinitionList(
      rows: [
        ReportDefinitionRow(
          label: AppStrings.reviewDueCard,
          value: '${due.due}',
          valueColor: due.due > 0 ? TurnaTheme.warning : null,
        ),
        ReportDefinitionRow(
          label: AppStrings.reviewNewCard,
          value: '${due.newCards}',
        ),
        ReportDefinitionRow(
          label: AppStrings.reviewOverdueCard,
          value: '${due.overdue}',
          valueColor: due.overdue > 0 ? TurnaTheme.error : null,
        ),
      ],
    );
  }
}

// ── 近 7 天（主图 · 柱状） ────────────────────────────────────────────────

class _WeeklyChartSection extends StatelessWidget {
  const _WeeklyChartSection({required this.snapshot});

  final ReviewDashboardSnapshot snapshot;

  @override
  Widget build(BuildContext context) {
    final streak = snapshot.streak;
    final points = snapshot.last7Days;
    final total = points.fold<int>(0, (a, b) => a + b.reviewedCount);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ReportSectionHeading(
          title: AppStrings.reviewStreakDays(streak.currentStreakDays),
          trailing: streak.protectedByVoucher
              ? Tooltip(
                  message: AppStrings.reviewProtectedTooltip,
                  child: Chip(
                    avatar: const Icon(Icons.shield_rounded, size: 15),
                    label: Text(AppStrings.reviewProtectedChip),
                    visualDensity: VisualDensity.compact,
                  ),
                )
              : Text(
                  AppStrings.reviewThisWeek(streak.activeDaysThisWeek),
                  style: TextStyle(
                    fontSize: 13,
                    color: TurnaTheme.textSecondaryColor(context),
                  ),
                ),
        ),
        if (total == 0)
          Text(
            AppStrings.reviewNoDataYet,
            style: TextStyle(
              fontSize: 13,
              color: TurnaTheme.textHintColor(context),
            ),
          )
        else ...[
          ReportBarChart(
            semanticsLabel: AppStrings.reviewSevenDayChartSemantics(total),
            height: 150,
            bars: [
              for (var i = 0; i < points.length; i++)
                ReportBar(
                  label: '${points[i].localDay.day}',
                  value: points[i].reviewedCount.toDouble(),
                  highlight: i == points.length - 1,
                ),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          // 文本语义摘要（无障碍：图表不只用颜色表达，§17.2）。
          Text(
            _summaryText(),
            style: TextStyle(
              fontSize: 13,
              color: TurnaTheme.textHintColor(context),
            ),
          ),
        ],
      ],
    );
  }

  String _summaryText() {
    final active =
        snapshot.last7Days.where((d) => d.reviewedCount > 0).length;
    final total =
        snapshot.last7Days.fold<int>(0, (a, b) => a + b.reviewedCount);
    return AppStrings.reviewSevenDaySummary(active, total);
  }
}

// ── 今日质量（辅助指标 · 定义列表） ────────────────────────────────────────

class _TodayQualitySection extends StatelessWidget {
  const _TodayQualitySection({required this.snapshot});

  final ReviewDashboardSnapshot snapshot;

  @override
  Widget build(BuildContext context) {
    final q = snapshot.todayQuality;
    final accuracyLabel = q.firstAnswerAccuracy == null
        ? AppStrings.reviewNoDataYet
        : AppStrings.reviewAccuracyPct((q.firstAnswerAccuracy! * 100).round());
    return ReportDefinitionList(
      rows: [
        ReportDefinitionRow(
          label: AppStrings.reviewMetricWindow7,
          value: AppStrings.reviewTodayMinutes(q.studyMinutes),
        ),
        ReportDefinitionRow(
          label: AppStrings.reviewAccuracyShort,
          value: accuracyLabel,
        ),
      ],
    );
  }
}

// ── Sources ────────────────────────────────────────────────────────────────

class _SourceList extends StatelessWidget {
  const _SourceList({required this.snapshot});

  final ReviewDashboardSnapshot snapshot;

  static const _maxShown = 5;

  @override
  Widget build(BuildContext context) {
    final sources = snapshot.sources;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ReportSectionHeading(title: AppStrings.reviewSourcesTitle),
        if (sources.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 12),
            child: Text(
              AppStrings.reviewEmptyHint,
              style: TextStyle(
                fontSize: 14,
                color: TurnaTheme.textHintColor(context),
              ),
            ),
          )
        else
          for (var i = 0; i < sources.length && i < _maxShown; i++)
            _SourceRow(row: sources[i]),
      ],
    );
  }
}

/// 来源行（R10 真实下钻）：整行点进来源详情页——不再有「带 chevron 却不可
/// 点」的假行。
class _SourceRow extends StatelessWidget {
  const _SourceRow({required this.row});

  final ReviewSourceSummary row;

  IconData get _icon {
    switch (row.source.kind) {
      case LearningSourceKind.course:
        return Icons.school_rounded;
      case LearningSourceKind.grammar:
        return Icons.menu_book_rounded;
      case LearningSourceKind.ankiLegacy:
      case LearningSourceKind.ankiOfficial:
        return Icons.style_rounded;
    }
  }

  Color get _accent {
    switch (row.source.kind) {
      case LearningSourceKind.course:
        return TurnaTheme.brandTeal;
      case LearningSourceKind.grammar:
        return TurnaTheme.brandSky;
      case LearningSourceKind.ankiLegacy:
      case LearningSourceKind.ankiOfficial:
        return TurnaTheme.brandReed;
    }
  }

  @override
  Widget build(BuildContext context) {
    return DirectoryTaskRow(
      icon: _icon,
      accent: _accent,
      title: row.source.displayName,
      countLabel:
          row.dueToday > 0 ? AppStrings.reviewSourceDue(row.dueToday) : null,
      onTap: () => context.router.push(
        ReviewSourceDetailRoute(source: reviewSourceFor(row.source)),
      ),
    );
  }
}

/// 仪表盘的来源引用 → 洞察/详情页的来源选择键。
///
/// id 口径与 `ReviewProgressProvider._listSources` 的生成规则一致：
/// course / grammar 是固定 id；导入牌组是 `anki:<importId>`；Official
/// 牌组是 `official:<sourceId>`。展示层换算，不动 application 模型。
ReviewSource reviewSourceFor(LearningSourceRef ref) {
  switch (ref.kind) {
    case LearningSourceKind.course:
      return const ReviewSource(
        kind: ReviewSourceKind.course,
        id: 'course',
        label: '课程',
      );
    case LearningSourceKind.grammar:
      return const ReviewSource(
        kind: ReviewSourceKind.grammar,
        id: 'grammar',
        label: '语法',
      );
    case LearningSourceKind.ankiLegacy:
      return ReviewSource(
        kind: ReviewSourceKind.ankiDeck,
        id: 'anki:${ref.sourceId}',
        label: ref.displayName,
        importId: ref.sourceId,
        active: ref.active,
      );
    case LearningSourceKind.ankiOfficial:
      return ReviewSource(
        kind: ReviewSourceKind.ankiOfficial,
        id: 'official:${ref.sourceId}',
        label: ref.displayName,
        importId: ref.sourceId,
        active: ref.active,
      );
  }
}

// ── States ────────────────────────────────────────────────────────────────

class _DashboardSkeleton extends StatelessWidget {
  const _DashboardSkeleton();

  @override
  Widget build(BuildContext context) {
    Widget block({double height = 80}) => Container(
          height: height,
          margin: const EdgeInsets.only(bottom: 12),
          decoration: TurnaTheme.flatPaperDecoration(
            context,
            borderRadius: BorderRadius.circular(TurnaTheme.radiusLarge),
          ),
        );
    return ListView(
      physics: const NeverScrollableScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
      children: [
        block(height: 120),
        block(height: 84),
        block(height: 110),
        block(height: 52),
        block(height: 160),
      ],
    );
  }
}

class _InlineErrorBanner extends StatelessWidget {
  const _InlineErrorBanner({required this.onRetry});

  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: TurnaTheme.error.withValues(alpha: 0.08),
      borderRadius: BorderRadius.circular(TurnaTheme.radiusMedium),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        child: Row(
          children: [
            const Icon(Icons.cloud_off_rounded,
                size: 16, color: TurnaTheme.error),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                AppStrings.reviewRefreshFailedKeptOld,
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ),
            TextButton(onPressed: onRetry, child: Text(AppStrings.commonRetry)),
          ],
        ),
      ),
    );
  }
}

class _ErrorState extends StatelessWidget {
  const _ErrorState({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(message, textAlign: TextAlign.center),
            const SizedBox(height: 12),
            FilledButton(
                onPressed: onRetry, child: Text(AppStrings.commonRetry)),
          ],
        ),
      ),
    );
  }
}
