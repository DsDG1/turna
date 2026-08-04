// Flutter imports:
import 'package:flutter/material.dart';

// Package imports:
import 'package:auto_route/auto_route.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:provider/provider.dart';

// Project imports:
import 'package:turna/application/memory_curve_provider.dart';
import 'package:turna/application/study_stats_provider.dart';
import 'package:turna/domain/study/daily_stats.dart';
import 'package:turna/l10n/app_strings.dart';
import 'package:turna/routing/routing.gr.dart';
import 'package:turna/views/theme.dart';

/// Displays today's learning summary and recent activity trends.
///
/// Futures are cached on the [State] so rebuilding this widget (e.g. tab
/// switches) does not re-issue prefs/repository reads. When
/// [StudyStatsProvider] notifies, futures are refreshed once.
class LearningStats extends StatefulWidget {
  const LearningStats({super.key});

  @override
  State<LearningStats> createState() => _LearningStatsState();
}

class _LearningStatsState extends State<LearningStats> {
  StudyStatsProvider? _provider;
  Future<DailyStudyStats>? _todayFuture;
  Future<List<DailyStudyStats>>? _weekFuture;
  Future<Map<String, dynamic>>? _overallFuture;
  Future<MemoryCurveSnapshot>? _curveFuture;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // read (not watch): tab rebuilds must not re-create futures. Refresh only
    // when StudyStatsProvider notifies via the listener below.
    final provider = context.read<StudyStatsProvider>();
    if (!identical(_provider, provider)) {
      _provider?.removeListener(_onStatsChanged);
      _provider = provider;
      _provider!.addListener(_onStatsChanged);
      _refreshFutures();
    }
  }

  @override
  void dispose() {
    _provider?.removeListener(_onStatsChanged);
    super.dispose();
  }

  void _onStatsChanged() {
    if (!mounted) return;
    setState(_refreshFutures);
  }

  void _refreshFutures() {
    final studyStats = _provider!;
    _todayFuture = studyStats.getTodayStats();
    _weekFuture = studyStats.getLastNDays(7);
    _overallFuture = _loadOverallStats(studyStats);
    // The memory-curve card is a non-critical enhancement; skip it silently
    // when no MemoryCurveProvider is in scope (e.g. focused unit tests).
    try {
      _curveFuture = context.read<MemoryCurveProvider>().snapshot();
    } catch (_) {
      _curveFuture = null;
    }
  }

  Future<Map<String, dynamic>> _loadOverallStats(
    StudyStatsProvider provider,
  ) async {
    final totalMinutes = await provider.getTotalStudyMinutes();
    final accuracy = await provider.getOverallAccuracy();
    final totalLessons = await provider.getTotalRecordedLessons();
    final totalReviews = await provider.getTotalRecordedReviews();
    final anki = await provider.getAnkiActivityCounts();

    return {
      'totalMinutes': totalMinutes,
      'accuracy': accuracy,
      'totalLessons': totalLessons,
      'totalReviews': totalReviews,
      'ankiLessons': anki['ankiLessons'] ?? 0,
      'ankiReviews': anki['ankiReviews'] ?? 0,
    };
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _sectionTitle(context, AppStrings.profileLearningStatsTitle,
              Icons.bar_chart_rounded),
          const SizedBox(height: 8),
          FutureBuilder<DailyStudyStats>(
            future: _todayFuture,
            builder: (context, snapshot) {
              return _TodaySummary(stats: snapshot.data);
            },
          ),
          const SizedBox(height: 16),
          FutureBuilder<List<DailyStudyStats>>(
            future: _weekFuture,
            builder: (context, snapshot) {
              final days = snapshot.data ?? [];
              return _WeeklyXpBars(days: days);
            },
          ),
          const SizedBox(height: 16),
          FutureBuilder<MemoryCurveSnapshot>(
            future: _curveFuture,
            builder: (context, snapshot) {
              final data = snapshot.data;
              if (data == null) return const SizedBox.shrink();
              return _MemoryCurveCard(snapshot: data);
            },
          ),
          const SizedBox(height: 16),
          FutureBuilder<Map<String, dynamic>>(
            future: _overallFuture,
            builder: (context, snapshot) {
              final data = snapshot.data ?? {};
              return _OverallStatsGrid(data: data);
            },
          ),
          const SizedBox(height: 16),
          FutureBuilder<Map<String, dynamic>>(
            future: _overallFuture,
            builder: (context, snapshot) {
              final data = snapshot.data ?? {};
              final ankiLessons = (data['ankiLessons'] as num?)?.toInt() ?? 0;
              final ankiReviews = (data['ankiReviews'] as num?)?.toInt() ?? 0;
              if (ankiLessons == 0 && ankiReviews == 0) {
                return const SizedBox.shrink();
              }
              return _AnkiStatsCard(
                ankiLessons: ankiLessons,
                ankiReviews: ankiReviews,
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _sectionTitle(BuildContext context, String text, IconData icon) {
    return Padding(
      padding: const EdgeInsets.only(top: 20, bottom: 8),
      child: Row(
        children: [
          Icon(icon, color: TurnaTheme.brandTeal, size: 22),
          const SizedBox(width: 8),
          Text(
            text,
            style: Theme.of(context).textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
          ),
        ],
      ),
    );
  }
}

class _TodaySummary extends StatelessWidget {
  final DailyStudyStats? stats;

  const _TodaySummary({this.stats});

  @override
  Widget build(BuildContext context) {
    final s = stats;
    final xp = s?.totalXp ?? 0;
    final minutes = ((s?.totalDurationSeconds ?? 0) / 60).ceil();
    final accuracy =
        s != null ? int.parse((s.accuracy * 100).toStringAsFixed(0)) : 0;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: TurnaTheme.cardBg(context),
        borderRadius: BorderRadius.circular(TurnaTheme.radiusLarge),
        border: Border.all(color: TurnaTheme.statCardBorder(context)),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: [
          _TodayItem(
            icon: Icons.bolt_rounded,
            iconColor: TurnaTheme.brandReed,
            value: xp.toString(),
            label: AppStrings.profileXpToday,
          ),
          Container(width: 1, height: 40, color: TurnaTheme.dividerBg(context)),
          _TodayItem(
            icon: Icons.timer_rounded,
            iconColor: TurnaTheme.leagueAmethyst,
            value: AppStrings.profileStudyTimeValue(minutes),
            label: AppStrings.profileStudyTime,
          ),
          Container(width: 1, height: 40, color: TurnaTheme.dividerBg(context)),
          _TodayItem(
            icon: Icons.percent_rounded,
            iconColor: TurnaTheme.successDark,
            value: AppStrings.profileAccuracyValue(accuracy),
            label: AppStrings.profileAccuracy,
          ),
        ],
      ),
    );
  }
}

class _TodayItem extends StatelessWidget {
  final IconData icon;
  final Color iconColor;
  final String value;
  final String label;

  const _TodayItem({
    required this.icon,
    required this.iconColor,
    required this.value,
    required this.label,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Icon(icon, color: iconColor, size: 22),
        const SizedBox(height: 6),
        Text(
          value,
          style: Theme.of(context).textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w800,
              ),
        ),
        const SizedBox(height: 2),
        Text(
          label,
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: TurnaTheme.textHintColor(context),
                fontWeight: FontWeight.w500,
              ),
        ),
      ],
    );
  }
}

class _WeeklyXpBars extends StatelessWidget {
  final List<DailyStudyStats> days;

  const _WeeklyXpBars({required this.days});

  @override
  Widget build(BuildContext context) {
    if (days.isEmpty) return const SizedBox.shrink();

    final maxXp =
        days.map((d) => d.totalXp).fold<int>(1, (a, b) => a > b ? a : b);
    final dayLabels = [
      AppStrings.dayMon,
      AppStrings.dayTue,
      AppStrings.dayWed,
      AppStrings.dayThu,
      AppStrings.dayFri,
      AppStrings.daySat,
      AppStrings.daySun,
    ];

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
            AppStrings.profileLast7Days,
            style: Theme.of(context).textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
          ),
          const SizedBox(height: 12),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            crossAxisAlignment: CrossAxisAlignment.end,
            children: List.generate(days.length, (i) {
              final day = days[i];
              final heightFactor = day.totalXp / maxXp;
              final barHeight = 4 + (heightFactor * 60).clamp(4.0, 60.0);

              return Column(
                children: [
                  Text(
                    day.totalXp.toString(),
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          fontSize: 10,
                          fontWeight: FontWeight.w600,
                          color: TurnaTheme.textHintColor(context),
                        ),
                  ),
                  const SizedBox(height: 4),
                  Container(
                    width: 22,
                    height: barHeight,
                    decoration: BoxDecoration(
                      color: day.totalXp > 0
                          ? TurnaTheme.brandTeal
                          : TurnaTheme.dividerBg(context),
                      borderRadius: BorderRadius.circular(4),
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    dayLabels[i % 7],
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          color: TurnaTheme.textHintColor(context),
                        ),
                  ),
                ],
              );
            }),
          ),
        ],
      ),
    );
  }
}

class _OverallStatsGrid extends StatelessWidget {
  final Map<String, dynamic> data;

  const _OverallStatsGrid({required this.data});

  @override
  Widget build(BuildContext context) {
    final totalMinutes = (data['totalMinutes'] as num?)?.toInt() ?? 0;
    final accuracy = int.parse(
        (((data['accuracy'] as num?) ?? 0.0).toDouble() * 100)
            .toStringAsFixed(0));
    final totalLessons = (data['totalLessons'] as num?)?.toInt() ?? 0;
    final totalReviews = (data['totalReviews'] as num?)?.toInt() ?? 0;

    return GridView.count(
      primary: false,
      shrinkWrap: true,
      crossAxisCount: 2,
      crossAxisSpacing: 10,
      mainAxisSpacing: 10,
      childAspectRatio: 2.2,
      children: [
        _StatCard(
          icon: Icons.timer_rounded,
          iconColor: TurnaTheme.leagueAmethyst,
          value: AppStrings.profileTotalStudyTimeValue(totalMinutes),
          label: AppStrings.profileTotalStudyTime,
        ),
        _StatCard(
          icon: Icons.percent_rounded,
          iconColor: TurnaTheme.successDark,
          value: AppStrings.profileOverallAccuracyValue(accuracy),
          label: AppStrings.profileOverallAccuracy,
        ),
        _StatCard(
          icon: Icons.school_rounded,
          iconColor: TurnaTheme.brandSky,
          value: totalLessons.toString(),
          label: AppStrings.profileLessonsDone,
        ),
        _StatCard(
          icon: Icons.repeat_rounded,
          iconColor: TurnaTheme.leagueGold,
          value: totalReviews.toString(),
          label: AppStrings.profileReviewsDone,
        ),
      ],
    );
  }
}

/// Breakdown card showing Anki-deck activity separately from language-course
/// lessons. Only renders when there is non-zero Anki activity.
class _AnkiStatsCard extends StatelessWidget {
  final int ankiLessons;
  final int ankiReviews;

  const _AnkiStatsCard({
    required this.ankiLessons,
    required this.ankiReviews,
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
          Row(
            children: [
              const Icon(Icons.layers_rounded,
                  color: TurnaTheme.brandTeal, size: 20),
              const SizedBox(width: 8),
              Text(
                AppStrings.profileAnkiDecks,
                style: Theme.of(context).textTheme.titleSmall?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              _TodayItem(
                icon: Icons.school_rounded,
                iconColor: TurnaTheme.brandSky,
                value: ankiLessons.toString(),
                label: AppStrings.profileAnkiLessons,
              ),
              Container(
                  width: 1, height: 40, color: TurnaTheme.dividerBg(context)),
              _TodayItem(
                icon: Icons.repeat_rounded,
                iconColor: TurnaTheme.leagueGold,
                value: ankiReviews.toString(),
                label: AppStrings.profileAnkiReviews,
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _StatCard extends StatelessWidget {
  final IconData icon;
  final Color iconColor;
  final String value;
  final String label;

  const _StatCard({
    required this.icon,
    required this.iconColor,
    required this.value,
    required this.label,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: TurnaTheme.cardBg(context),
        borderRadius: BorderRadius.circular(TurnaTheme.radiusMedium),
        border: Border.all(color: TurnaTheme.statCardBorder(context)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Row(
            children: [
              Icon(icon, color: iconColor, size: 20),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  value,
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Padding(
            padding: const EdgeInsets.only(left: 28),
            child: Text(
              label,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: TurnaTheme.textHintColor(context),
                    fontWeight: FontWeight.w500,
                  ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Memory-curve dashboard card: current retention %, an empirical
/// retention-by-interval line chart (from review history), an upcoming-review
/// forecast, and a card-maturity breakdown.
class _MemoryCurveCard extends StatelessWidget {
  final MemoryCurveSnapshot snapshot;

  const _MemoryCurveCard({required this.snapshot});

  @override
  Widget build(BuildContext context) {
    final retentionPct = (snapshot.currentRetention * 100).round();
    final curve = snapshot.retentionByInterval;
    final hasCurve = curve.isNotEmpty;

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
                style: Theme.of(context)
                    .textTheme
                    .titleMedium
                    ?.copyWith(fontWeight: FontWeight.w700),
              ),
              const Spacer(),
              TextButton(
                onPressed: () =>
                    context.router.push(const ReviewProgressRoute()),
                child: Text(AppStrings.reviewProgressSeeDetail),
              ),
              Text(
                AppStrings.profileRetentionValue(retentionPct),
                style: Theme.of(context).textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.w700,
                      color: TurnaTheme.brandTeal,
                    ),
              ),
            ],
          ),
          const SizedBox(height: 2),
          Text(
            '${AppStrings.profileRetention} · ${AppStrings.profileReviewsCount(snapshot.totalReviews)}',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: TurnaTheme.textHintColor(context),
                ),
          ),
          const SizedBox(height: 12),
          if (hasCurve)
            SizedBox(height: 140, child: _curveChart(context, curve))
          else
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 28),
              child: Center(
                child: Text(
                  AppStrings.profileMemoryCurveEmpty,
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: TurnaTheme.textHintColor(context),
                      ),
                ),
              ),
            ),
          const SizedBox(height: 12),
          Text(
            AppStrings.profileForecastTitle,
            style: Theme.of(context).textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              _miniStat(context, snapshot.forecast.dueToday,
                  AppStrings.profileDueToday),
              _miniStat(context, snapshot.forecast.due7Days,
                  AppStrings.profileDue7Days),
              _miniStat(context, snapshot.forecast.due30Days,
                  AppStrings.profileDue30Days),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            AppStrings.profileMasteryTitle,
            style: Theme.of(context).textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
          ),
          const SizedBox(height: 4),
          Text(
            AppStrings.profileMasteryValue(
              (snapshot.meanMastery * 100).round().clamp(0, 100),
            ),
            style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.w700,
                  color: TurnaTheme.primary,
                ),
          ),
          const SizedBox(height: 12),
          Text(
            AppStrings.profileMaturityTitle,
            style: Theme.of(context).textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _maturityChip(
                  context,
                  AppStrings.profileMaturityNew,
                  snapshot.maturity.newCards,
                  TurnaTheme.textHintColor(context)),
              _maturityChip(context, AppStrings.profileMaturityYoung,
                  snapshot.maturity.young, TurnaTheme.primaryLight),
              _maturityChip(context, AppStrings.profileMaturityMature,
                  snapshot.maturity.mature, TurnaTheme.success),
              _maturityChip(context, AppStrings.profileMaturityLeech,
                  snapshot.maturity.leech, TurnaTheme.error),
            ],
          ),
        ],
      ),
    );
  }

  Widget _curveChart(BuildContext context, List<RetentionPoint> curve) {
    final spots = [
      for (var i = 0; i < curve.length; i++)
        FlSpot(i.toDouble(), curve[i].retention),
    ];
    final lineColor = TurnaTheme.brandTeal;
    return LineChart(
      LineChartData(
        minY: 0,
        maxY: 1,
        minX: 0,
        maxX: (curve.length - 1).toDouble(),
        gridData: FlGridData(
          show: true,
          drawVerticalLine: false,
          horizontalInterval: 0.25,
          getDrawingHorizontalLine: (v) => FlLine(
            color: TurnaTheme.dividerBg(context),
            strokeWidth: 1,
          ),
        ),
        titlesData: FlTitlesData(
          topTitles:
              const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          rightTitles:
              const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          leftTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              interval: 0.25,
              reservedSize: 30,
              getTitlesWidget: (v, _) => Padding(
                padding: const EdgeInsets.only(right: 4),
                child: Text('${(v * 100).round()}%',
                    style: TextStyle(
                        fontSize: 10,
                        color: TurnaTheme.textHintColor(context))),
              ),
            ),
          ),
          bottomTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 22,
              interval: 1,
              getTitlesWidget: (i, _) {
                final idx = i.toInt();
                if (idx < 0 || idx >= curve.length) {
                  return const SizedBox.shrink();
                }
                return Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text('${curve[idx].intervalBucketDays}d',
                      style: TextStyle(
                          fontSize: 10,
                          color: TurnaTheme.textHintColor(context))),
                );
              },
            ),
          ),
        ),
        borderData: FlBorderData(show: false),
        lineBarsData: [
          LineChartBarData(
            spots: spots,
            isCurved: true,
            gradient: LinearGradient(
              colors: [lineColor, lineColor],
            ),
            barWidth: 3,
            dotData: FlDotData(show: curve.length <= 6),
            belowBarData: BarAreaData(
              show: true,
              gradient: LinearGradient(
                colors: [
                  lineColor.withOpacity(0.12),
                  lineColor.withOpacity(0.02),
                ],
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
              ),
            ),
          ),
        ],
        lineTouchData: LineTouchData(
          touchTooltipData: LineTouchTooltipData(
            getTooltipItems: (touchedSpots) {
              return [
                for (final s in touchedSpots)
                  if (s.spotIndex >= 0 && s.spotIndex < curve.length)
                    LineTooltipItem(
                      '${(curve[s.spotIndex].retention * 100).round()}%',
                      TextStyle(color: lineColor, fontWeight: FontWeight.w700),
                    ),
              ];
            },
          ),
        ),
      ),
    );
  }

  Widget _miniStat(BuildContext context, int value, String label) {
    return Expanded(
      child: Container(
        margin: const EdgeInsets.only(right: 8),
        padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 6),
        decoration: BoxDecoration(
          color: TurnaTheme.inputFillColor(context),
          borderRadius: BorderRadius.circular(TurnaTheme.radiusMedium),
        ),
        child: Column(
          children: [
            Text(
              '$value',
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
            ),
            const SizedBox(height: 2),
            Text(
              label,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: TurnaTheme.textHintColor(context),
                  ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _maturityChip(
      BuildContext context, String label, int count, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: color.withOpacity(0.12),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withOpacity(0.4)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            label,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: color,
                  fontWeight: FontWeight.w600,
                ),
          ),
          const SizedBox(width: 4),
          Text(
            '$count',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: color,
                  fontWeight: FontWeight.w700,
                ),
          ),
        ],
      ),
    );
  }
}
