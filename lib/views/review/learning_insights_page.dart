// Flutter imports:
import 'package:flutter/material.dart';

// Package imports:
import 'package:auto_route/auto_route.dart';
import 'package:provider/provider.dart';

// Project imports:
import 'package:turna/application/review_progress_provider.dart';
import 'package:turna/l10n/app_strings.dart';
import 'package:turna/views/profile/widgets/learning_stats.dart';
import 'package:turna/views/review/components/retention_curve_chart.dart';
import 'package:turna/views/theme.dart';
import 'package:turna/views/widgets/turna_select.dart';

/// 学习洞察 — the second-level analytics page (Plan 3 §15.2).
///
/// Hosts the heavy statistics the former progress home carried: filters,
/// retention/maturity KPIs, the memory curve, StudyStatsSection and the full
/// per-source breakdown. The overview home intentionally shows none of this.
///
/// Filter changes keep the previous snapshot visible (no full-page spinner);
/// when no tracked cards match, retention/mastery KPIs render "—" instead of
/// a fake 100% (Plan 3 §14.5).
@RoutePage()
class LearningInsightsPage extends StatefulWidget {
  const LearningInsightsPage({super.key});

  @override
  State<LearningInsightsPage> createState() => _LearningInsightsPageState();
}

class _LearningInsightsPageState extends State<LearningInsightsPage> {
  ReviewProgressFilter _filter = const ReviewProgressFilter();
  Future<ReviewProgressSnapshot>? _future;
  ReviewProgressSnapshot? _lastData;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _reload();
    });
  }

  void _reload() {
    final provider = context.read<ReviewProgressProvider>();
    setState(() {
      _future = provider.snapshot(_filter);
    });
  }

  void _setFilter(ReviewProgressFilter next) {
    _filter = next;
    _reload();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: TurnaTheme.scaffoldBg(context),
      appBar: AppBar(
        title: Text(AppStrings.reviewInsightsTitle),
        backgroundColor: TurnaTheme.scaffoldBg(context),
      ),
      body: FutureBuilder<ReviewProgressSnapshot>(
        future: _future,
        builder: (context, snap) {
          // Keep the previous snapshot visible while a new filter loads —
          // only the very first load shows a centered spinner.
          final data = snap.data ?? _lastData;
          if (data != null) _lastData = data;
          if (data == null) {
            return const Center(child: CircularProgressIndicator());
          }
          final refreshing =
              snap.connectionState == ConnectionState.waiting;
          return RefreshIndicator(
            color: TurnaTheme.brandTeal,
            onRefresh: () async {
              final provider = context.read<ReviewProgressProvider>();
              final next = await provider.snapshot(_filter);
              if (mounted) {
                setState(() {
                  _lastData = next;
                  _future = Future.value(next);
                });
              }
            },
            child: ListView(
              physics: const AlwaysScrollableScrollPhysics(
                parent: BouncingScrollPhysics(),
              ),
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
              children: [
                if (refreshing)
                  const LinearProgressIndicator(minHeight: 2),
                _FilterPanel(
                  filter: _filter,
                  sources: data.availableSources,
                  onChanged: _setFilter,
                ),
                const SizedBox(height: 16),
                _KpiCard(snapshot: data),
                const SizedBox(height: 16),
                _CurveCard(
                  snapshot: data,
                  eventRange: _filter.eventRange,
                  onRangeChanged: (r) =>
                      _setFilter(_filter.copyWith(eventRange: r)),
                ),
                const SizedBox(height: 24),
                StudyStatsSection(),
                const SizedBox(height: 16),
                _SourceList(
                  rows: data.bySource,
                  selected: _filter.source,
                  onSelect: (src) =>
                      _setFilter(_filter.copyWith(source: src)),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

// ── Filters ──────────────────────────────────────────────────────────────

class _FilterPanel extends StatelessWidget {
  final ReviewProgressFilter filter;
  final List<ReviewSource> sources;
  final ValueChanged<ReviewProgressFilter> onChanged;

  const _FilterPanel({
    required this.filter,
    required this.sources,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: TurnaTheme.cardBg(context),
        borderRadius: BorderRadius.circular(TurnaTheme.radiusLarge),
        border: Border.all(color: TurnaTheme.statCardBorder(context)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _chipRow(
            children: [
              for (final s in sources)
                TurnaFilterChip(
                  label: s.kind == ReviewSourceKind.all
                      ? AppStrings.reviewProgressSourceAll
                      : s.label,
                  selected: filter.source.id == s.id,
                  onSelected: (_) => onChanged(filter.copyWith(source: s)),
                ),
            ],
          ),
          const SizedBox(height: 10),
          TurnaSegmented<ProgressTypeFilter>(
            selected: filter.type,
            onChanged: (t) => onChanged(filter.copyWith(type: t)),
            segments: [
              for (final t in ProgressTypeFilter.values)
                ButtonSegment(value: t, label: Text(_typeLabel(t))),
            ],
          ),
          const SizedBox(height: 10),
          TurnaSegmented<DueFilter>(
            selected: filter.due,
            onChanged: (d) => onChanged(filter.copyWith(due: d)),
            segments: [
              ButtonSegment(
                value: DueFilter.any,
                label: Text(AppStrings.reviewProgressDueAny),
              ),
              ButtonSegment(
                value: DueFilter.overdue,
                label: Text(AppStrings.reviewProgressDueOverdue),
              ),
              ButtonSegment(
                value: DueFilter.due7,
                label: Text(AppStrings.reviewProgressDue7),
              ),
              ButtonSegment(
                value: DueFilter.due30,
                label: Text(AppStrings.reviewProgressDue30),
              ),
            ],
          ),
        ],
      ),
    );
  }

  String _typeLabel(ProgressTypeFilter t) {
    switch (t) {
      case ProgressTypeFilter.all:
        return AppStrings.reviewProgressTypeAll;
      case ProgressTypeFilter.word:
        return AppStrings.reviewProgressTypeWord;
      case ProgressTypeFilter.expression:
        return AppStrings.reviewProgressTypeExpression;
      case ProgressTypeFilter.grammar:
        return AppStrings.reviewProgressTypeGrammar;
    }
  }

  Widget _chipRow({required List<Widget> children}) {
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(children: [
        for (var i = 0; i < children.length; i++) ...[
          if (i > 0) const SizedBox(width: 8),
          children[i],
        ],
      ]),
    );
  }
}

// ── KPI ──────────────────────────────────────────────────────────────────

class _KpiCard extends StatelessWidget {
  final ReviewProgressSnapshot snapshot;

  const _KpiCard({required this.snapshot});

  @override
  Widget build(BuildContext context) {
    final a = snapshot.aggregate;
    // No tracked cards → no retention/mastery claim: render "—" instead of
    // the mathematically-default 100% (Plan 3 §14.5).
    final hasTracked = a.trackedCards > 0;
    final ret = hasTracked ? '${(a.currentRetention * 100).round()}%' : '—';
    final mas = hasTracked ? '${(a.meanMastery * 100).round()}%' : '—';

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: TurnaTheme.cardBg(context),
        borderRadius: BorderRadius.circular(TurnaTheme.radiusLarge),
        border: Border.all(color: TurnaTheme.statCardBorder(context)),
      ),
      child: Column(
        children: [
          Row(
            children: [
              _kpi(context, ret, AppStrings.reviewProgressKpiRetention,
                  TurnaTheme.brandTeal),
              _kpi(context, mas, AppStrings.reviewProgressKpiMastery,
                  TurnaTheme.primaryLight),
              _kpi(
                  context,
                  '${a.totalCards}',
                  AppStrings.reviewProgressKpiCards,
                  TurnaTheme.textSecondaryColor(context)),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              _kpi(context, '${a.forecast.dueToday}',
                  AppStrings.profileDueToday, TurnaTheme.error),
              _kpi(context, '${a.forecast.due7Days}',
                  AppStrings.profileDue7Days, TurnaTheme.warning),
              _kpi(context, '${a.totalReviews}',
                  AppStrings.reviewProgressKpiReviews, TurnaTheme.brandSky),
            ],
          ),
        ],
      ),
    );
  }

  Widget _kpi(BuildContext context, String value, String label, Color accent) {
    return Expanded(
      child: Column(
        children: [
          Text(
            value,
            style: Theme.of(context).textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.w800,
                  color: accent,
                ),
          ),
          const SizedBox(height: 2),
          Text(
            label,
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  color: TurnaTheme.textHintColor(context),
                ),
          ),
        ],
      ),
    );
  }
}

// ── Curve ────────────────────────────────────────────────────────────────

class _CurveCard extends StatelessWidget {
  final ReviewProgressSnapshot snapshot;
  final EventRange eventRange;
  final ValueChanged<EventRange> onRangeChanged;

  const _CurveCard({
    required this.snapshot,
    required this.eventRange,
    required this.onRangeChanged,
  });

  @override
  Widget build(BuildContext context) {
    final curve = snapshot.aggregate.retentionByInterval;
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
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  Icon(Icons.show_chart_rounded,
                      color: TurnaTheme.brandTeal, size: 20),
                  const SizedBox(width: 8),
                  Text(
                    AppStrings.profileMemoryCurveTitle,
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w700,
                        ),
                  ),
                ],
              ),
              Text(
                AppStrings.profileReviewsCount(snapshot.aggregate.totalReviews),
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      color: TurnaTheme.textHintColor(context),
                    ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          TurnaSegmented<EventRange>(
            selected: eventRange,
            onChanged: onRangeChanged,
            segments: [
              for (final r in EventRange.values)
                ButtonSegment(
                  value: r,
                  label: Text(
                    _rangeLabel(r),
                    maxLines: 1,
                    style: const TextStyle(fontSize: 12),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 12),
          if (curve.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 28),
              child: Center(
                child: Text(
                  snapshot.aggregate.totalCards == 0
                      ? AppStrings.reviewProgressEmpty
                      : AppStrings.profileMemoryCurveEmpty,
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: TurnaTheme.textHintColor(context),
                      ),
                ),
              ),
            )
          else
            RetentionCurveChart(curve: curve, height: 160),
        ],
      ),
    );
  }

  String _rangeLabel(EventRange r) {
    switch (r) {
      case EventRange.all:
        return AppStrings.reviewProgressRangeAll;
      case EventRange.d7:
        return AppStrings.reviewProgressRange7;
      case EventRange.d30:
        return AppStrings.reviewProgressRange30;
      case EventRange.d90:
        return AppStrings.reviewProgressRange90;
    }
  }
}

// ── Sources ──────────────────────────────────────────────────────────────

class _SourceList extends StatelessWidget {
  final List<SourceProgressRow> rows;
  final ReviewSource selected;
  final ValueChanged<ReviewSource> onSelect;

  const _SourceList({
    required this.rows,
    required this.selected,
    required this.onSelect,
  });

  @override
  Widget build(BuildContext context) {
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
            AppStrings.reviewProgressSourcesTitle,
            style: Theme.of(context).textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
          ),
          const SizedBox(height: 8),
          if (rows.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 16),
              child: Text(
                AppStrings.reviewProgressEmptyFiltered,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: TurnaTheme.textHintColor(context),
                    ),
              ),
            )
          else
            for (var i = 0; i < rows.length; i++) ...[
              if (i > 0) Divider(color: TurnaTheme.dividerBg(context)),
              _SourceTile(
                row: rows[i],
                selected: selected.id == rows[i].source.id,
                onTap: () => onSelect(rows[i].source),
              ),
            ],
        ],
      ),
    );
  }
}

class _SourceTile extends StatelessWidget {
  final SourceProgressRow row;
  final bool selected;
  final VoidCallback onTap;

  const _SourceTile({
    required this.row,
    required this.selected,
    required this.onTap,
  });

  IconData get _icon {
    switch (row.source.kind) {
      case ReviewSourceKind.course:
        return Icons.school_rounded;
      case ReviewSourceKind.grammar:
        return Icons.menu_book_rounded;
      case ReviewSourceKind.ankiDeck:
        return Icons.style_rounded;
      case ReviewSourceKind.all:
        return Icons.layers_rounded;
    }
  }

  @override
  Widget build(BuildContext context) {
    final hasTracked = row.tracked > 0;
    final ret = hasTracked
        ? AppStrings.reviewProgressRetentionPct(
            (row.meanRetention * 100).round())
        : '—';
    final progress = row.totalCards == 0
        ? 0.0
        : (1.0 - row.dueToday / row.totalCards).clamp(0.0, 1.0);

    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(TurnaTheme.radiusMedium),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(_icon,
                    size: 22,
                    color: selected
                        ? TurnaTheme.brandTeal
                        : TurnaTheme.textSecondaryColor(context)),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        row.source.label,
                        style: Theme.of(context).textTheme.titleSmall?.copyWith(
                              fontWeight: FontWeight.w700,
                              color: selected ? TurnaTheme.brandTeal : null,
                            ),
                      ),
                      Text(
                        AppStrings.reviewProgressCardsDue(
                            row.totalCards, row.dueToday),
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                              color: TurnaTheme.textHintColor(context),
                            ),
                      ),
                    ],
                  ),
                ),
                Text(
                  ret,
                  style: Theme.of(context).textTheme.labelLarge?.copyWith(
                        fontWeight: FontWeight.w800,
                        color: TurnaTheme.brandTeal,
                      ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(
                value: progress,
                minHeight: 6,
                backgroundColor: TurnaTheme.dividerBg(context),
                color: TurnaTheme.brandTeal,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
