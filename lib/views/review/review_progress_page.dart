// Flutter imports:
import 'package:flutter/material.dart';

// Package imports:
import 'package:auto_route/auto_route.dart';
import 'package:provider/provider.dart';

// Project imports:
import 'package:turna/application/review_dashboard/review_dashboard_models.dart';
import 'package:turna/application/review_dashboard/review_dashboard_repository.dart';
import 'package:turna/application/accessibility_capabilities.dart';
import 'package:turna/l10n/app_strings.dart';
import 'package:turna/routing/routing.gr.dart';
import 'package:turna/views/theme.dart';

/// Review-overview home (Plan 3 §15.1): a fast, actionable "today" dashboard.
///
/// Information order: today hero (progress + CTA) → due/new/overdue →
/// streak + light 7-day chart → today quality → course/deck sources →
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
      body: _error != null && snap == null
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
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
                    children: [
                      if (_error != null)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 8),
                          child: _InlineErrorBanner(
                            onRetry: () => _reload(forceRefresh: true),
                          ),
                        ),
                      _TodayHero(snapshot: snap),
                      const SizedBox(height: 12),
                      _DueRow(snapshot: snap),
                      const SizedBox(height: 12),
                      if (!focusMode) ...[
                        _StreakCard(snapshot: snap),
                        const SizedBox(height: 12),
                        _TodayQualityCard(snapshot: snap),
                        const SizedBox(height: 12),
                        _SourceList(snapshot: snap),
                        const SizedBox(height: 16),
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
    );
  }
}

// ── Today hero ─────────────────────────────────────────────────────────────

class _TodayHero extends StatelessWidget {
  const _TodayHero({required this.snapshot});

  final ReviewDashboardSnapshot snapshot;

  @override
  Widget build(BuildContext context) {
    final today = snapshot.today;
    final due = snapshot.due;
    final hasGoal = today.hasGoal;
    final progress = hasGoal && today.todayXp != null
        ? (today.todayXp! / today.xpGoal!).clamp(0.0, 1.0)
        : 0.0;

    final canReview = due.actionableTotal > 0;
    final dateLabel = _formatDate(snapshot.generatedAt);

    final largeText = MediaQuery.textScalerOf(context).scale(1) >= 1.5;
    final progressBlock = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          hasGoal && today.todayXp != null
              ? AppStrings.reviewTodayGoalProgress(
                  today.todayXp!, today.xpGoal!)
              : AppStrings.reviewTodayReviewed(today.reviewedToday),
          style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                fontWeight: FontWeight.w800,
                color: TurnaTheme.brandTeal,
              ),
        ),
        const SizedBox(height: 8),
        ClipRRect(
          borderRadius: BorderRadius.circular(4),
          child: LinearProgressIndicator(
            value: progress,
            minHeight: 8,
            backgroundColor: TurnaTheme.dividerBg(context),
            color: TurnaTheme.brandTeal,
          ),
        ),
      ],
    );
    final cta = FilledButton.icon(
      onPressed:
          canReview ? () => context.router.push(const SrsReviewRoute()) : null,
      icon: const Icon(Icons.play_arrow_rounded, size: 20),
      label: Text(
        canReview
            ? AppStrings.reviewContinueCta
            : AppStrings.reviewTodayDoneCta,
        style: const TextStyle(fontWeight: FontWeight.w700),
      ),
    );
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: TurnaTheme.cardBg(context),
        borderRadius: BorderRadius.circular(TurnaTheme.radiusLarge),
        border: Border.all(color: TurnaTheme.statCardBorder(context)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            alignment: WrapAlignment.spaceBetween,
            spacing: 12,
            runSpacing: 4,
            children: [
              Text(
                AppStrings.reviewTodayTitle,
                style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
              ),
              Text(
                dateLabel,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: TurnaTheme.textHintColor(context),
                    ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          if (largeText) ...[
            progressBlock,
            const SizedBox(height: 12),
            SizedBox(width: double.infinity, child: cta),
          ] else
            Row(
              children: [
                Expanded(child: progressBlock),
                const SizedBox(width: 14),
                cta,
              ],
            ),
        ],
      ),
    );
  }

  String _formatDate(DateTime d) =>
      '${d.month} ${AppStrings.reviewMonthDay(d.day)}';
}

// ── Due / new / overdue ────────────────────────────────────────────────────

class _DueRow extends StatelessWidget {
  const _DueRow({required this.snapshot});

  final ReviewDashboardSnapshot snapshot;

  @override
  Widget build(BuildContext context) {
    final due = snapshot.due;
    final largeText = MediaQuery.textScalerOf(context).scale(1) >= 1.5;
    final cards = <Widget>[
      _DueCard(
        icon: Icons.schedule_rounded,
        value: due.due,
        label: AppStrings.reviewDueCard,
        accent: due.due > 0 ? TurnaTheme.warning : TurnaTheme.textHint,
      ),
      _DueCard(
        icon: Icons.fiber_new_rounded,
        value: due.newCards,
        label: AppStrings.reviewNewCard,
        accent: TurnaTheme.brandSky,
      ),
      _DueCard(
        icon: Icons.warning_amber_rounded,
        value: due.overdue,
        label: AppStrings.reviewOverdueCard,
        accent: due.overdue > 0 ? TurnaTheme.error : TurnaTheme.textHint,
      ),
    ];
    if (largeText) {
      return Column(
        children: [
          for (var i = 0; i < cards.length; i++) ...[
            if (i > 0) const SizedBox(height: 8),
            SizedBox(width: double.infinity, child: cards[i]),
          ],
        ],
      );
    }
    return Row(
      children: [
        for (var i = 0; i < cards.length; i++) ...[
          if (i > 0) const SizedBox(width: 10),
          Expanded(child: cards[i]),
        ],
      ],
    );
  }
}

class _DueCard extends StatelessWidget {
  const _DueCard({
    required this.icon,
    required this.value,
    required this.label,
    required this.accent,
  });

  final IconData icon;
  final int value;
  final String label;
  final Color accent;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 14),
      decoration: BoxDecoration(
        color: TurnaTheme.cardBg(context),
        borderRadius: BorderRadius.circular(TurnaTheme.radiusLarge),
        border: Border.all(color: TurnaTheme.statCardBorder(context)),
      ),
      child: Column(
        children: [
          Icon(icon, size: 18, color: accent),
          const SizedBox(height: 4),
          Text(
            '$value',
            style: Theme.of(context).textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.w800,
                  color: accent,
                ),
          ),
          Text(
            label,
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  color: TurnaTheme.textHintColor(context),
                ),
          ),
        ],
      ),
    );
  }
}

// ── Streak + 7-day ────────────────────────────────────────────────────────

class _StreakCard extends StatelessWidget {
  const _StreakCard({required this.snapshot});

  final ReviewDashboardSnapshot snapshot;

  @override
  Widget build(BuildContext context) {
    final streak = snapshot.streak;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: TurnaTheme.cardBg(context),
        borderRadius: BorderRadius.circular(TurnaTheme.radiusLarge),
        border: Border.all(color: TurnaTheme.statCardBorder(context)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.local_fire_department_rounded,
                  color: TurnaTheme.anatolianClay, size: 20),
              const SizedBox(width: 8),
              Text(
                AppStrings.reviewStreakDays(streak.currentStreakDays),
                style: Theme.of(context).textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
              ),
              if (streak.protectedByVoucher) ...[
                const SizedBox(width: 8),
                const Tooltip(
                  message: '本次连续记录由保护券保留；学习统计未修改',
                  child: Chip(
                    avatar: Icon(Icons.shield_rounded, size: 15),
                    label: Text('已保护'),
                    visualDensity: VisualDensity.compact,
                  ),
                ),
              ],
              const Spacer(),
              Text(
                AppStrings.reviewThisWeek(streak.activeDaysThisWeek),
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: TurnaTheme.textSecondaryColor(context),
                    ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          SizedBox(
            height: 56,
            child: _SevenDayChart(points: snapshot.last7Days),
          ),
          const SizedBox(height: 6),
          // 文本语义摘要（无障碍：图表不只用颜色表达，§17.2）。
          Text(
            _summaryText(),
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: TurnaTheme.textHintColor(context),
                ),
          ),
        ],
      ),
    );
  }

  String _summaryText() {
    final active = snapshot.last7Days.where((d) => d.reviewedCount > 0).length;
    final total =
        snapshot.last7Days.fold<int>(0, (a, b) => a + b.reviewedCount);
    return AppStrings.reviewSevenDaySummary(active, total);
  }
}

/// Light 7-point bar chart painted once (no per-frame animation, wrapped in
/// the parent card; respects reduce-motion by never tweening).
class _SevenDayChart extends StatelessWidget {
  const _SevenDayChart({required this.points});

  final List<DailyActivityPoint> points;

  @override
  Widget build(BuildContext context) {
    final maxCount = points.fold<int>(
        0, (a, b) => a > b.reviewedCount ? a : b.reviewedCount);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        for (var i = 0; i < points.length; i++) ...[
          if (i > 0) const SizedBox(width: 6),
          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                Container(
                  height: maxCount == 0
                      ? 4.0
                      : (points[i].reviewedCount == 0
                          ? 4.0
                          : 12.0 + 40.0 * points[i].reviewedCount / maxCount),
                  decoration: BoxDecoration(
                    color: points[i].reviewedCount == 0
                        ? TurnaTheme.dividerBg(context)
                        : TurnaTheme.brandTeal.withValues(
                            alpha: 0.45 +
                                0.55 * points[i].reviewedCount / maxCount),
                    borderRadius: BorderRadius.circular(3),
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  '${points[i].localDay.day}',
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                        fontSize: 9,
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
}

// ── Today quality ─────────────────────────────────────────────────────────

class _TodayQualityCard extends StatelessWidget {
  const _TodayQualityCard({required this.snapshot});

  final ReviewDashboardSnapshot snapshot;

  @override
  Widget build(BuildContext context) {
    final q = snapshot.todayQuality;
    final accuracyLabel = q.firstAnswerAccuracy == null
        ? AppStrings.reviewNoDataYet
        : AppStrings.reviewAccuracyPct((q.firstAnswerAccuracy! * 100).round());
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        color: TurnaTheme.cardBg(context),
        borderRadius: BorderRadius.circular(TurnaTheme.radiusLarge),
        border: Border.all(color: TurnaTheme.statCardBorder(context)),
      ),
      child: Row(
        children: [
          const Icon(Icons.timer_outlined,
              size: 18, color: TurnaTheme.brandTeal),
          const SizedBox(width: 8),
          Text(
            AppStrings.reviewTodayMinutes(q.studyMinutes),
            style: Theme.of(context).textTheme.bodyMedium,
          ),
          const SizedBox(width: 16),
          const Icon(Icons.check_circle_outline_rounded,
              size: 18, color: TurnaTheme.brandTeal),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              accuracyLabel,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: q.firstAnswerAccuracy == null
                        ? TurnaTheme.textHintColor(context)
                        : null,
                  ),
            ),
          ),
        ],
      ),
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
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: TurnaTheme.cardBg(context),
        borderRadius: BorderRadius.circular(TurnaTheme.radiusLarge),
        border: Border.all(color: TurnaTheme.statCardBorder(context)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            AppStrings.reviewSourcesTitle,
            style: Theme.of(context).textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
          ),
          const SizedBox(height: 4),
          if (sources.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 12),
              child: Text(
                AppStrings.reviewEmptyHint,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: TurnaTheme.textHintColor(context),
                    ),
              ),
            )
          else
            for (var i = 0; i < sources.length && i < _maxShown; i++) ...[
              if (i > 0) Divider(color: TurnaTheme.dividerBg(context)),
              _SourceTile(row: sources[i]),
            ],
        ],
      ),
    );
  }
}

class _SourceTile extends StatelessWidget {
  const _SourceTile({required this.row});

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

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Row(
        children: [
          Icon(_icon, size: 20, color: TurnaTheme.textSecondaryColor(context)),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              row.source.displayName,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
            ),
          ),
          Text(
            AppStrings.reviewSourceDue(row.dueToday),
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: row.dueToday > 0
                      ? TurnaTheme.warning
                      : TurnaTheme.textHintColor(context),
                  fontWeight: FontWeight.w700,
                ),
          ),
          const SizedBox(width: 4),
          Icon(Icons.chevron_right_rounded,
              size: 16, color: TurnaTheme.textHintColor(context)),
        ],
      ),
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
          decoration: BoxDecoration(
            color: TurnaTheme.cardBg(context),
            borderRadius: BorderRadius.circular(TurnaTheme.radiusLarge),
            border: Border.all(color: TurnaTheme.statCardBorder(context)),
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
