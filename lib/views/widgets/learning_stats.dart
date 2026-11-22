// Dart imports:
import 'dart:async';

// Flutter imports:
import 'package:flutter/material.dart';

// Package imports:
import 'package:provider/provider.dart';

// Project imports:
import 'package:turna/application/study_stats_provider.dart';
import 'package:turna/core/logger.dart';
import 'package:turna/core/spacing.dart';
import 'package:turna/core/text_styles.dart';
import 'package:turna/core/theme.dart';
import 'package:turna/core/turna_icon_id.dart';
import 'package:turna/views/widgets/turna_icon.dart';
import 'package:turna/domain/study/daily_stats.dart';
import 'package:turna/l10n/app_strings.dart';

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
  Object? _lastTodayError;
  Object? _lastWeekError;
  Object? _lastOverallError;

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

  void _retryFutures() {
    if (!mounted) return;
    setState(_refreshFutures);
  }

  void _logTodayError(Object? error, StackTrace? stackTrace) {
    if (identical(_lastTodayError, error)) return;
    _lastTodayError = error;
    logger.w(
      'LearningStats: today stats load failed',
      error: error,
      stackTrace: stackTrace,
    );
  }

  void _logWeekError(Object? error, StackTrace? stackTrace) {
    if (identical(_lastWeekError, error)) return;
    _lastWeekError = error;
    logger.w(
      'LearningStats: weekly stats load failed',
      error: error,
      stackTrace: stackTrace,
    );
  }

  void _logOverallError(Object? error, StackTrace? stackTrace) {
    if (identical(_lastOverallError, error)) return;
    _lastOverallError = error;
    logger.w(
      'LearningStats: overall stats load failed',
      error: error,
      stackTrace: stackTrace,
    );
  }

  void _refreshFutures() {
    final studyStats = _provider!;
    _lastTodayError = null;
    _lastWeekError = null;
    _lastOverallError = null;
    _todayFuture = studyStats.getTodayStats()..ignore();
    _weekFuture = studyStats.getLastNDays(7)..ignore();
    _overallFuture = _loadOverallStats(studyStats)..ignore();
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
      padding: AppSpacing.pageGutterMist,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _sectionTitle(
            context,
            AppStrings.profileTodayTitle,
            TurnaIconId.insights,
          ),
          const SizedBox(height: 10),
          FutureBuilder<DailyStudyStats>(
            future: _todayFuture,
            builder: (context, snapshot) {
              if (snapshot.hasError) {
                _logTodayError(snapshot.error, snapshot.stackTrace);
                return _StatsErrorBanner(onRetry: _retryFutures);
              }
              if (snapshot.connectionState != ConnectionState.done) {
                return const _TodaySummary(waiting: true);
              }
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
    return FutureBuilder<List<DailyStudyStats>>(
      future: _weekFuture,
      builder: (context, weekSnapshot) {
        if (weekSnapshot.hasError) {
          _logWeekError(weekSnapshot.error, weekSnapshot.stackTrace);
          return _StatsErrorBanner(onRetry: _retryFutures);
        }
        final days = weekSnapshot.data ?? const <DailyStudyStats>[];
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _WeeklyXpBars(days: days),
            const SizedBox(height: 16),
            FutureBuilder<Map<String, dynamic>>(
              future: _overallFuture,
              builder: (context, overallSnapshot) {
                if (overallSnapshot.hasError) {
                  _logOverallError(
                    overallSnapshot.error,
                    overallSnapshot.stackTrace,
                  );
                  return _StatsErrorBanner(onRetry: _retryFutures);
                }
                final data = overallSnapshot.data ?? const <String, dynamic>{};
                final ankiLessons = (data['ankiLessons'] as num?)?.toInt() ?? 0;
                final ankiReviews = (data['ankiReviews'] as num?)?.toInt() ?? 0;
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _OverallStatsGrid(data: data),
                    if (ankiLessons != 0 || ankiReviews != 0) ...[
                      const SizedBox(height: 16),
                      _AnkiStatsCard(
                        ankiLessons: ankiLessons,
                        ankiReviews: ankiReviews,
                      ),
                    ],
                  ],
                );
              },
            ),
          ],
        );
      },
    );
  }
}

class _StatsErrorBanner extends StatelessWidget {
  const _StatsErrorBanner({required this.onRetry});

  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.lg,
        vertical: AppSpacing.md,
      ),
      decoration: TurnaTheme.flatPaperDecoration(context),
      child: Row(
        children: [
          const TurnaIcon(TurnaIconId.error, color: TurnaTheme.error, size: 20),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Text(
              AppStrings.learningStatsLoadFailed,
              style: AppTextStyles.captionSm(context)
                  .copyWith(color: TurnaTheme.textPrimaryColor(context)),
            ),
          ),
          TextButton(onPressed: onRetry, child: Text(AppStrings.commonRetry)),
        ],
      ),
    );
  }
}

Widget _sectionTitle(BuildContext context, String text, TurnaIconId icon) {
  return Row(
    children: [
      TurnaIcon(icon, color: TurnaTheme.brandTeal, size: 20),
      const SizedBox(width: AppSpacing.sm),
      Expanded(child: Text(text, style: AppTextStyles.cardTitle(context))),
    ],
  );
}

/// 今日一行（湿地雾光 R15）：XP / 分钟 / 正确率收进一行纸面摘要。
class _TodaySummary extends StatelessWidget {
  final DailyStudyStats? stats;
  final bool waiting;

  const _TodaySummary({this.stats, this.waiting = false});

  @override
  Widget build(BuildContext context) {
    final s = stats;
    final xp = s?.totalXp ?? 0;
    final minutes = ((s?.totalDurationSeconds ?? 0) / 60).ceil();
    final accuracy = s != null
        ? int.parse((s.accuracy * 100).toStringAsFixed(0))
        : 0;

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.lg,
        vertical: AppSpacing.md + 2,
      ),
      decoration: TurnaTheme.flatPaperDecoration(context),
      child: Row(
        children: [
          const TurnaIcon(
            TurnaIconId.bolt,
            color: TurnaTheme.anatolianClay,
            size: 20,
          ),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Text(
              waiting
                  ? AppStrings.profileTodaySummaryLine(0, 0, 0)
                  : AppStrings.profileTodaySummaryLine(xp, minutes, accuracy),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: AppTextStyles.bodyText(context).copyWith(
                fontWeight: FontWeight.w600,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _TodayItem extends StatelessWidget {
  final TurnaIconId icon;
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
        TurnaIcon(icon, color: iconColor, size: 22),
        const SizedBox(height: AppSpacing.xs + 2),
        Text(
          value,
          style: AppTextStyles.cardTitle(context)
              .copyWith(fontWeight: FontWeight.w800),
        ),
        const SizedBox(height: 2),
        Text(
          label,
          style: AppTextStyles.caption(context)
              .copyWith(letterSpacing: 0, fontWeight: FontWeight.w500),
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

    final maxXp = days
        .map((d) => d.totalXp)
        .fold<int>(1, (a, b) => a > b ? a : b);

    return Container(
      padding: const EdgeInsets.all(AppSpacing.lg),
      decoration: TurnaTheme.glassDecoration(
        context,
        TurnaTheme.glassNeutral,
        level: GlassLevel.l1Subtle,
        borderRadius: TurnaTheme.borderRadius,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            AppStrings.profileLast7Days,
            style: AppTextStyles.cardTitle(context),
          ),
          const SizedBox(height: AppSpacing.md),
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
                    style: AppTextStyles.caption(context)
                        .copyWith(letterSpacing: 0),
                  ),
                  const SizedBox(height: AppSpacing.xs),
                  Container(
                    width: 22,
                    height: barHeight,
                    decoration: BoxDecoration(
                      color: day.totalXp > 0
                          ? TurnaTheme.brandTeal
                          : TurnaTheme.dividerBg(context),
                      borderRadius: TurnaTheme.borderRadius,
                    ),
                  ),
                  const SizedBox(height: AppSpacing.xs + 2),
                  Text(
                    AppStrings.weekdayShortLabel(day.date.weekday),
                    style: AppTextStyles.caption(context)
                        .copyWith(letterSpacing: 0),
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
      (((data['accuracy'] as num?) ?? 0.0).toDouble() * 100).toStringAsFixed(0),
    );
    final totalLessons = (data['totalLessons'] as num?)?.toInt() ?? 0;
    final totalReviews = (data['totalReviews'] as num?)?.toInt() ?? 0;

    return GridView.count(
      padding: EdgeInsets.zero,
      primary: false,
      shrinkWrap: true,
      crossAxisCount: 2,
      crossAxisSpacing: AppSpacing.sm + 2,
      mainAxisSpacing: AppSpacing.sm + 2,
      childAspectRatio: 2.2,
      children: [
        _StatCard(
          icon: TurnaIconId.timer,
          iconColor: TurnaTheme.anatolianClay,
          value: AppStrings.profileTotalStudyTimeValue(totalMinutes),
          label: AppStrings.profileTotalStudyTime,
        ),
        _StatCard(
          icon: TurnaIconId.percent,
          iconColor: TurnaTheme.successDark,
          value: AppStrings.profileOverallAccuracyValue(accuracy),
          label: AppStrings.profileOverallAccuracy,
        ),
        _StatCard(
          icon: TurnaIconId.school,
          iconColor: TurnaTheme.brandSky,
          value: totalLessons.toString(),
          label: AppStrings.profileLessonsDone,
        ),
        _StatCard(
          icon: TurnaIconId.repeat,
          iconColor: TurnaTheme.achievementGold,
          value: totalReviews.toString(),
          label: AppStrings.profileReviewsDone,
        ),
      ],
    );
  }
}

/// Breakdown card showing memory-card activity separately from language-course
/// lessons. Only renders when there is non-zero activity.
class _AnkiStatsCard extends StatelessWidget {
  final int ankiLessons;
  final int ankiReviews;

  const _AnkiStatsCard({required this.ankiLessons, required this.ankiReviews});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(AppSpacing.lg),
      decoration: TurnaTheme.glassDecoration(
        context,
        TurnaTheme.glassNeutral,
        level: GlassLevel.l1Subtle,
        borderRadius: TurnaTheme.borderRadius,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const TurnaIcon(
                TurnaIconId.layers,
                color: TurnaTheme.brandTeal,
                size: 20,
              ),
              const SizedBox(width: AppSpacing.sm),
              Text(
                AppStrings.profileAnkiDecks,
                style: AppTextStyles.cardTitle(context),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.md),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              _TodayItem(
                icon: TurnaIconId.school,
                iconColor: TurnaTheme.brandSky,
                value: ankiLessons.toString(),
                label: AppStrings.profileAnkiLessons,
              ),
              Container(
                width: 1,
                height: 40,
                color: TurnaTheme.dividerBg(context),
              ),
              _TodayItem(
                icon: TurnaIconId.repeat,
                iconColor: TurnaTheme.achievementGold,
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
  final TurnaIconId icon;
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
      padding: const EdgeInsets.all(AppSpacing.md),
      decoration: TurnaTheme.glassDecoration(
        context,
        TurnaTheme.glassNeutral,
        level: GlassLevel.l1Subtle,
        borderRadius: TurnaTheme.borderRadius,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Row(
            children: [
              TurnaIcon(icon, color: iconColor, size: 20),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Text(
                  value,
                  style: AppTextStyles.cardTitle(context)
                      .copyWith(fontWeight: FontWeight.w700),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.xs),
          Padding(
            padding: const EdgeInsets.only(left: 28),
            child: Text(
              label,
              style: AppTextStyles.caption(context)
                  .copyWith(letterSpacing: 0, fontWeight: FontWeight.w500),
            ),
          ),
        ],
      ),
    );
  }
}
