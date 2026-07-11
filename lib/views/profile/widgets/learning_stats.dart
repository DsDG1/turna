// Flutter imports:
import 'package:flutter/material.dart';

// Package imports:
import 'package:provider/provider.dart';

// Project imports:
import 'package:varnamala/application/study_stats_provider.dart';
import 'package:varnamala/domain/study/daily_stats.dart';
import 'package:varnamala/views/theme.dart';

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

    return {
      'totalMinutes': totalMinutes,
      'accuracy': accuracy,
      'totalLessons': totalLessons,
      'totalReviews': totalReviews,
    };
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _sectionTitle(context, 'Learning Stats', Icons.insights_rounded),
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
          FutureBuilder<Map<String, dynamic>>(
            future: _overallFuture,
            builder: (context, snapshot) {
              final data = snapshot.data ?? {};
              return _OverallStatsGrid(data: data);
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
          Icon(icon, color: VarnamalaTheme.peacockTeal, size: 22),
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
    final accuracy = s != null ? (s.accuracy * 100).toStringAsFixed(0) : '0';

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: VarnamalaTheme.cardBg(context),
        borderRadius: BorderRadius.circular(VarnamalaTheme.radiusLarge),
        border: Border.all(color: VarnamalaTheme.statCardBorder(context)),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceAround,
        children: [
          _TodayItem(
            icon: Icons.bolt_rounded,
            iconColor: VarnamalaTheme.peacockTurquoise,
            value: xp.toString(),
            label: 'XP Today',
          ),
          Container(width: 1, height: 40, color: VarnamalaTheme.dividerBg(context)),
          _TodayItem(
            icon: Icons.timer_rounded,
            iconColor: VarnamalaTheme.leagueAmethyst,
            value: '$minutes\'',
            label: 'Study Time',
          ),
          Container(width: 1, height: 40, color: VarnamalaTheme.dividerBg(context)),
          _TodayItem(
            icon: Icons.percent_rounded,
            iconColor: VarnamalaTheme.successDark,
            value: '$accuracy%',
            label: 'Accuracy',
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
                color: VarnamalaTheme.textHintColor(context),
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

    final maxXp = days.map((d) => d.totalXp).fold<int>(1, (a, b) => a > b ? a : b);
    final dayLabels = ['M', 'T', 'W', 'T', 'F', 'S', 'S'];

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: VarnamalaTheme.cardBg(context),
        borderRadius: BorderRadius.circular(VarnamalaTheme.radiusLarge),
        border: Border.all(color: VarnamalaTheme.statCardBorder(context)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Last 7 Days',
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
                          color: VarnamalaTheme.textHintColor(context),
                        ),
                  ),
                  const SizedBox(height: 4),
                  Container(
                    width: 22,
                    height: barHeight,
                    decoration: BoxDecoration(
                      color: day.totalXp > 0
                          ? VarnamalaTheme.peacockTeal
                          : VarnamalaTheme.dividerBg(context),
                      borderRadius: BorderRadius.circular(4),
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    dayLabels[i % 7],
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          color: VarnamalaTheme.textHintColor(context),
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
    final accuracy = (((data['accuracy'] as num?) ?? 0.0).toDouble() * 100)
        .toStringAsFixed(0);
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
          iconColor: VarnamalaTheme.leagueAmethyst,
          value: '${totalMinutes}m',
          label: 'Total Study Time',
        ),
        _StatCard(
          icon: Icons.percent_rounded,
          iconColor: VarnamalaTheme.successDark,
          value: '$accuracy%',
          label: 'Overall Accuracy',
        ),
        _StatCard(
          icon: Icons.school_rounded,
          iconColor: VarnamalaTheme.peacockCyan,
          value: totalLessons.toString(),
          label: 'Lessons Done',
        ),
        _StatCard(
          icon: Icons.repeat_rounded,
          iconColor: VarnamalaTheme.leagueGold,
          value: totalReviews.toString(),
          label: 'Reviews Done',
        ),
      ],
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
        color: VarnamalaTheme.cardBg(context),
        borderRadius: BorderRadius.circular(VarnamalaTheme.radiusMedium),
        border: Border.all(color: VarnamalaTheme.statCardBorder(context)),
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
                    color: VarnamalaTheme.textHintColor(context),
                    fontWeight: FontWeight.w500,
                  ),
            ),
          ),
        ],
      ),
    );
  }
}
