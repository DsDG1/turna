// Flutter imports:
import 'package:flutter/material.dart';

// Package imports:
import 'package:auto_route/auto_route.dart';
import 'package:provider/provider.dart';

// Project imports:
import 'package:turna/application/review_progress_provider.dart';
import 'package:turna/l10n/app_strings.dart';
import 'package:turna/views/review/components/retention_curve_chart.dart';
import 'package:turna/views/theme.dart';

@RoutePage()
class ReviewProgressPage extends StatefulWidget {
  const ReviewProgressPage({super.key});

  @override
  State<ReviewProgressPage> createState() => _ReviewProgressPageState();
}

class _ReviewProgressPageState extends State<ReviewProgressPage> {
  ReviewProgressFilter _filter = const ReviewProgressFilter();
  Future<ReviewProgressSnapshot>? _future;

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
        title: Text(AppStrings.reviewProgressTitle),
        backgroundColor: TurnaTheme.scaffoldBg(context),
      ),
      body: FutureBuilder<ReviewProgressSnapshot>(
        future: _future,
        builder: (context, snap) {
          if (snap.connectionState == ConnectionState.waiting &&
              !snap.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          if (snap.hasError) {
            return Center(child: Text('${snap.error}'));
          }
          final data = snap.data;
          if (data == null) {
            return Center(child: Text(AppStrings.reviewProgressEmpty));
          }
          return RefreshIndicator(
            color: TurnaTheme.brandTeal,
            onRefresh: () async => _reload(),
            child: CustomScrollView(
              physics: const AlwaysScrollableScrollPhysics(
                parent: BouncingScrollPhysics(),
              ),
              slivers: [
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                    child: _FilterPanel(
                      filter: _filter,
                      sources: data.availableSources,
                      onChanged: _setFilter,
                    ),
                  ),
                ),
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
                    child: _KpiCard(snapshot: data),
                  ),
                ),
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
                    child: _CurveCard(snapshot: data),
                  ),
                ),
                if (data.aggregate.totalCards > 0)
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
                      child: _MaturityCard(snapshot: data),
                    ),
                  ),
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
                    child: _SourceList(
                      rows: data.bySource,
                      selected: _filter.source,
                      onSelect: (src) =>
                          _setFilter(_filter.copyWith(source: src)),
                    ),
                  ),
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
            context,
            children: [
              for (final s in sources)
                _chip(
                  context,
                  label: s.kind == ReviewSourceKind.all
                      ? AppStrings.reviewProgressSourceAll
                      : s.label,
                  selected: filter.source.id == s.id,
                  onTap: () => onChanged(filter.copyWith(source: s)),
                ),
            ],
          ),
          const SizedBox(height: 8),
          _chipRow(
            context,
            children: [
              for (final t in ProgressTypeFilter.values)
                _chip(
                  context,
                  label: _typeLabel(t),
                  selected: filter.type == t,
                  onTap: () => onChanged(filter.copyWith(type: t)),
                ),
            ],
          ),
          const SizedBox(height: 8),
          _chipRow(
            context,
            children: [
              _chip(
                context,
                label: AppStrings.reviewProgressDueAny,
                selected: filter.due == DueFilter.any,
                onTap: () => onChanged(filter.copyWith(due: DueFilter.any)),
              ),
              _chip(
                context,
                label: AppStrings.reviewProgressDueOverdue,
                selected: filter.due == DueFilter.overdue,
                onTap: () => onChanged(filter.copyWith(due: DueFilter.overdue)),
              ),
              _chip(
                context,
                label: AppStrings.reviewProgressDue7,
                selected: filter.due == DueFilter.due7,
                onTap: () => onChanged(filter.copyWith(due: DueFilter.due7)),
              ),
              _chip(
                context,
                label: AppStrings.reviewProgressDue30,
                selected: filter.due == DueFilter.due30,
                onTap: () => onChanged(filter.copyWith(due: DueFilter.due30)),
              ),
            ],
          ),
          const SizedBox(height: 8),
          _chipRow(
            context,
            children: [
              for (final m in MaturityBucket.values)
                _chip(
                  context,
                  label: _maturityLabel(m),
                  selected: filter.maturity.contains(m),
                  onTap: () {
                    final next = Set<MaturityBucket>.from(filter.maturity);
                    if (next.contains(m)) {
                      next.remove(m);
                    } else {
                      next.add(m);
                    }
                    onChanged(filter.copyWith(maturity: next));
                  },
                ),
            ],
          ),
          const SizedBox(height: 8),
          _chipRow(
            context,
            children: [
              for (final r in EventRange.values)
                _chip(
                  context,
                  label: _rangeLabel(r),
                  selected: filter.eventRange == r,
                  onTap: () => onChanged(filter.copyWith(eventRange: r)),
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

  String _maturityLabel(MaturityBucket m) {
    switch (m) {
      case MaturityBucket.newCards:
        return AppStrings.profileMaturityNew;
      case MaturityBucket.young:
        return AppStrings.profileMaturityYoung;
      case MaturityBucket.mature:
        return AppStrings.profileMaturityMature;
      case MaturityBucket.leech:
        return AppStrings.profileMaturityLeech;
    }
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

  Widget _chipRow(BuildContext context, {required List<Widget> children}) {
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

  Widget _chip(
    BuildContext context, {
    required String label,
    required bool selected,
    required VoidCallback onTap,
  }) {
    return FilterChip(
      label: Text(label),
      selected: selected,
      onSelected: (_) => onTap(),
      selectedColor: TurnaTheme.brandTeal.withValues(alpha: 0.18),
      checkmarkColor: TurnaTheme.brandTeal,
      labelStyle: TextStyle(
        fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
        color: selected
            ? TurnaTheme.brandTeal
            : TurnaTheme.textSecondaryColor(context),
        fontSize: 13,
      ),
      side: BorderSide(
        color: selected
            ? TurnaTheme.brandTeal
            : TurnaTheme.statCardBorder(context),
      ),
      backgroundColor: TurnaTheme.cardBg(context),
      visualDensity: VisualDensity.compact,
      materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
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
    final ret = (a.currentRetention * 100).round();
    final mas = (a.meanMastery * 100).round();

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
              _kpi(context, '$ret%', AppStrings.reviewProgressKpiRetention,
                  TurnaTheme.brandTeal),
              _kpi(context, '$mas%', AppStrings.reviewProgressKpiMastery,
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

  const _CurveCard({required this.snapshot});

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
          const SizedBox(height: 4),
          Text(
            AppStrings.profileReviewsCount(snapshot.aggregate.totalReviews),
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: TurnaTheme.textHintColor(context),
                ),
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
}

// ── Maturity ─────────────────────────────────────────────────────────────

class _MaturityCard extends StatelessWidget {
  final ReviewProgressSnapshot snapshot;

  const _MaturityCard({required this.snapshot});

  @override
  Widget build(BuildContext context) {
    final m = snapshot.aggregate.maturity;
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
            AppStrings.profileMaturityTitle,
            style: Theme.of(context).textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _chip(context, AppStrings.profileMaturityNew, m.newCards,
                  TurnaTheme.textHintColor(context)),
              _chip(context, AppStrings.profileMaturityYoung, m.young,
                  TurnaTheme.primaryLight),
              _chip(context, AppStrings.profileMaturityMature, m.mature,
                  TurnaTheme.success),
              _chip(context, AppStrings.profileMaturityLeech, m.leech,
                  TurnaTheme.error),
            ],
          ),
        ],
      ),
    );
  }

  Widget _chip(BuildContext context, String label, int count, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(TurnaTheme.radiusRound),
      ),
      child: Text(
        '$label $count',
        style: TextStyle(
          color: color,
          fontWeight: FontWeight.w700,
          fontSize: 13,
        ),
      ),
    );
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
    final ret = (row.meanRetention * 100).round();
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
                  AppStrings.reviewProgressRetentionPct(ret),
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
