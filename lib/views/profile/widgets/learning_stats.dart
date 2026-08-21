// Flutter imports:
import 'package:flutter/material.dart';

// Package imports:
import 'package:provider/provider.dart';

// Project imports:
import 'package:turna/application/study_stats_provider.dart';
import 'package:turna/domain/study/daily_stats.dart';
import 'package:turna/l10n/app_strings.dart';
import 'package:turna/views/theme.dart';

/// Data-loading contract shared by [TodaySummaryCard] and [StudyStatsSection].
///
/// Futures are cached on the [State] so rebuilding (e.g. tab switches) does
/// not re-issue prefs/repository reads. When [StudyStatsProvider] notifies,
/// futures are refreshed once.
abstract class _StudyFuturesState<T extends StatefulWidget> extends State<T> {
  StudyStatsProvider? _provider;
  Future<DailyStudyStats>? _todayFuture;
  Future<List<DailyStudyStats>>? _weekFuture;
  Future<Map<String, dynamic>>? _overallFuture;

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
}

/// Today's one-glance summary (XP / minutes / accuracy) on the profile page.
class TodaySummaryCard extends StatefulWidget {
  const TodaySummaryCard({super.key});

  @override
  State<TodaySummaryCard> createState() => _TodaySummaryCardState();
}

class _TodaySummaryCardState extends _StudyFuturesState<TodaySummaryCard> {
  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _sectionTitle(context, AppStrings.profileTodayTitle,
              Icons.insights_rounded),
          const SizedBox(height: 10),
          FutureBuilder<DailyStudyStats>(
            future: _todayFuture,
            builder: (context, snapshot) {
              return _TodaySummary(stats: snapshot.data);
            },
          ),
        ],
      ),
    );
  }
}

/// Detailed study stats (weekly XP, overall grid, Anki breakdown) hosted by
/// the review-progress page; the profile page only links to it.
class StudyStatsSection extends StatefulWidget {
  const StudyStatsSection({super.key});

  @override
  State<StudyStatsSection> createState() => _StudyStatsSectionState();
}

class _StudyStatsSectionState extends _StudyFuturesState<StudyStatsSection> {
  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        FutureBuilder<List<DailyStudyStats>>(
          future: _weekFuture,
          builder: (context, snapshot) {
            final days = snapshot.data ?? [];
            return _WeeklyXpBars(days: days);
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
    );
  }
}

Widget _sectionTitle(BuildContext context, String text, IconData icon) {
  return Row(
    children: [
      Icon(icon, color: TurnaTheme.brandTeal, size: 20),
      const SizedBox(width: 8),
      Expanded(
        child: Text(
          text,
          style: Theme.of(context).textTheme.titleMedium?.copyWith(
                fontWeight: FontWeight.w700,
              ),
        ),
      ),
    ],
  );
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
            // Achievement-facing XP: clay icon on sand/soft badge (visibility).
            iconColor: TurnaTheme.anatolianClay,
            value: xp.toString(),
            label: AppStrings.profileXpToday,
            warmBadge: true,
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
  final bool warmBadge;

  const _TodayItem({
    required this.icon,
    required this.iconColor,
    required this.value,
    required this.label,
    this.warmBadge = false,
  });

  @override
  Widget build(BuildContext context) {
    final iconWidget = warmBadge
        ? Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: TurnaTheme.clayOnSandFill(context),
              shape: BoxShape.circle,
            ),
            child: Icon(icon, color: iconColor, size: 20),
          )
        : Icon(icon, color: iconColor, size: 22);

    return Column(
      children: [
        iconWidget,
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
      padding: EdgeInsets.zero,
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
