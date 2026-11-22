// Flutter imports:
import 'package:flutter/material.dart';

// Package imports:
import 'package:auto_route/auto_route.dart';

// Project imports:
import 'package:turna/application/anki_official/official_anki_catalog_service.dart';
import 'package:turna/application/anki_official/stats/official_anki_source_aware_stats.dart';
import 'package:turna/core/logger.dart';
import 'package:turna/core/spacing.dart';
import 'package:turna/core/text_styles.dart';
import 'package:turna/core/theme.dart';
import 'package:turna/core/turna_icon_id.dart';
import 'package:turna/l10n/app_strings.dart';
import 'package:turna/views/widgets/practice_empty_state.dart';
import 'package:turna/views/widgets/report_kit.dart';
import 'package:turna/views/widgets/turna_icon.dart';
import 'package:turna/views/widgets/turna_loader.dart';
import 'package:turna/views/widgets/turna_page_content.dart';
import 'package:turna/views/widgets/turna_top_bar.dart';

@RoutePage()
class AnkiDeckStatsPage extends StatefulWidget {
  final String importId;
  final String title;
  final Future<OfficialAnkiSourceAwareStatsSnapshot>? Function(String importId)?
  statsLoader;

  const AnkiDeckStatsPage({
    super.key,
    required this.importId,
    required this.title,
    this.statsLoader,
  });

  @override
  State<AnkiDeckStatsPage> createState() => _AnkiDeckStatsPageState();
}

class _AnkiDeckStatsPageState extends State<AnkiDeckStatsPage> {
  Future<OfficialAnkiSourceAwareStatsSnapshot>? _officialStats;
  Object? _lastLoggedError;

  @override
  void initState() {
    super.initState();
    _officialStats = _loadStats();
  }

  @override
  void didUpdateWidget(covariant AnkiDeckStatsPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.importId != widget.importId ||
        oldWidget.statsLoader != widget.statsLoader) {
      _lastLoggedError = null;
      _officialStats = _loadStats();
    }
  }

  Future<OfficialAnkiSourceAwareStatsSnapshot>? _loadStats() {
    final loader = widget.statsLoader;
    if (loader != null) {
      return loader(widget.importId);
    }
    return const OfficialAnkiCatalogService().statsForSource(widget.importId);
  }

  void _retry() {
    setState(() {
      _lastLoggedError = null;
      _officialStats = _loadStats();
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: TurnaTheme.scaffoldBg(context),
      appBar: TurnaTopBar(
        title: AppStrings.ankiDeckStatsPageTitle(widget.title),
        showDivider: true,
      ),
      body: TurnaPageContent(
        maxWidth: AppSpacing.formColumnMaxWidth,
        child: _officialStats != null
            ? FutureBuilder<OfficialAnkiSourceAwareStatsSnapshot>(
                future: _officialStats,
                builder: (context, snapshot) {
                  if (snapshot.hasError) {
                    if (!identical(_lastLoggedError, snapshot.error)) {
                      _lastLoggedError = snapshot.error;
                      logger.w(
                        'AnkiDeckStatsPage: load failed',
                        error: snapshot.error,
                        stackTrace: snapshot.stackTrace,
                      );
                    }
                    return PracticeEmptyState(
                      title: AppStrings.deckStatsLoadFailed,
                      actionLabel: AppStrings.commonRetry,
                      onAction: _retry,
                    );
                  }
                  if (!snapshot.hasData) {
                    return Center(child: TurnaLoader.page());
                  }
                  return _StatsReportBody(officialSnap: snapshot.data!);
                },
              )
            : PracticeEmptyState(
                title: AppStrings.ankiBrowserOfficialUnavailable(
                  'legacy_note_store_retired',
                ),
              ),
      ),
    );
  }
}

class _StatsReportBody extends StatelessWidget {
  const _StatsReportBody({required this.officialSnap});

  final OfficialAnkiSourceAwareStatsSnapshot officialSnap;

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.pageMargin,
        AppSpacing.md,
        AppSpacing.pageMargin,
        AppSpacing.xxl,
      ),
      children: [
        ReportMetricHeader(
          label: AppStrings.ankiStatsTotalCards,
          value: '${officialSnap.totalCards}',
          unit: AppStrings.ankiDeckStatsCardsUnit,
        ),
        if (officialSnap.metricsProven) ...[
          const SizedBox(height: AppSpacing.xl),
          _DistributionSection(officialSnap: officialSnap),
          const SizedBox(height: AppSpacing.xl),
          _SummaryMetricsSection(officialSnap: officialSnap),
          const SizedBox(height: AppSpacing.xl),
          _ForecastSection(officialSnap: officialSnap),
          if (officialSnap.retentionByInterval.length >= 2) ...[
            const SizedBox(height: AppSpacing.xl),
            ReportSectionHeading(
              title: AppStrings.ankiStatsRetentionByInterval,
            ),
            ReportLineChart(
              semanticsLabel: AppStrings.ankiDeckStatsRetentionChartLabel,
              maxValue: 100,
              points: [
                for (final p in officialSnap.retentionByInterval)
                  ReportPoint(
                    label: AppStrings.reviewIntervalDays(p.intervalBucketDays),
                    value: p.retention * 100,
                  ),
              ],
            ),
          ],
        ],
        const SizedBox(height: AppSpacing.xl),
        _SemanticsNoteCard(officialSnap: officialSnap),
      ],
    );
  }
}

class _DistributionSection extends StatelessWidget {
  const _DistributionSection({required this.officialSnap});

  final OfficialAnkiSourceAwareStatsSnapshot officialSnap;

  @override
  Widget build(BuildContext context) {
    final newCount = officialSnap.newCount ?? 0;
    final learningCount = officialSnap.learningCount ?? 0;
    final reviewCount = officialSnap.reviewCount ?? 0;
    final total = newCount + learningCount + reviewCount;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ReportSectionHeading(title: AppStrings.ankiDeckStatsDistribution),
        if (total == 0)
          Text(
            '${AppStrings.reviewNewCard} 0 · '
            '${AppStrings.ankiDeckStatsLearningLabel} 0 · '
            '${AppStrings.ankiDeckStatsReviewLabel} 0',
            style: AppTextStyles.captionSm(context),
          )
        else
          ReportCompositionBar(
            segments: [
              ReportSegment(
                label: AppStrings.reviewNewCard,
                value: newCount.toDouble(),
                color: TurnaTheme.brandSky,
                valueLabel: '$newCount ${AppStrings.ankiDeckStatsCardsUnit}',
              ),
              ReportSegment(
                label: AppStrings.ankiDeckStatsLearningLabel,
                value: learningCount.toDouble(),
                color: TurnaTheme.anatolianClay,
                valueLabel:
                    '$learningCount ${AppStrings.ankiDeckStatsCardsUnit}',
              ),
              ReportSegment(
                label: AppStrings.ankiDeckStatsReviewLabel,
                value: reviewCount.toDouble(),
                color: TurnaTheme.brandTeal,
                valueLabel: '$reviewCount ${AppStrings.ankiDeckStatsCardsUnit}',
              ),
            ],
          ),
      ],
    );
  }
}

class _SummaryMetricsSection extends StatelessWidget {
  const _SummaryMetricsSection({required this.officialSnap});

  final OfficialAnkiSourceAwareStatsSnapshot officialSnap;

  @override
  Widget build(BuildContext context) {
    final flagsValue = officialSnap.unintroducedCount > 0
        ? AppStrings.ankiStatsFlagsValue(
            officialSnap.unintroducedCount,
            officialSnap.userSuspendedCount,
            officialSnap.buriedCount ?? 0,
          )
        : '${officialSnap.suspendedCount ?? 0} / '
              '${officialSnap.buriedCount ?? 0}';
    final todayValue = AppStrings.ankiStatsTodayValue(
      officialSnap.todayAnswerCount ?? 0,
      officialSnap.todayLearnCount ?? 0,
      officialSnap.todayReviewCount ?? 0,
      officialSnap.todayRelearnCount ?? 0,
    );
    final revlogValue = (officialSnap.retentionSample ?? 0) == 0
        ? AppStrings.ankiStatsRevlogNoSample(officialSnap.revlogCount ?? 0)
        : AppStrings.ankiStatsRevlogValue(
            officialSnap.revlogCount ?? 0,
            ((officialSnap.retention ?? 0) * 100).round(),
            officialSnap.retentionPassed ?? 0,
            officialSnap.retentionSample ?? 0,
          );

    return ReportDefinitionList(
      rows: [
        ReportDefinitionRow(
          label: AppStrings.ankiStatsCardFlags,
          value: flagsValue,
        ),
        ReportDefinitionRow(
          label: AppStrings.ankiStatsTodayAnswers,
          value: todayValue,
        ),
        ReportDefinitionRow(
          label: AppStrings.ankiStatsRevlogTitle,
          value: revlogValue,
        ),
      ],
    );
  }
}

class _ForecastSection extends StatelessWidget {
  const _ForecastSection({required this.officialSnap});

  final OfficialAnkiSourceAwareStatsSnapshot officialSnap;

  @override
  Widget build(BuildContext context) {
    final dueToday = officialSnap.forecastDueToday ?? 0;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ReportSectionHeading(title: AppStrings.ankiStatsForecast),
        ReportDefinitionList(
          rows: [
            ReportDefinitionRow(
              label: AppStrings.ankiStatsDueToday,
              value: '$dueToday',
              valueColor: dueToday > 0 ? TurnaTheme.warning : null,
            ),
            ReportDefinitionRow(
              label: AppStrings.ankiStatsDue7Days,
              value: '${officialSnap.forecastDue7Days ?? 0}',
            ),
            ReportDefinitionRow(
              label: AppStrings.ankiStatsDue30Days,
              value: '${officialSnap.forecastDue30Days ?? 0}',
            ),
          ],
        ),
      ],
    );
  }
}

class _SemanticsNoteCard extends StatelessWidget {
  const _SemanticsNoteCard({required this.officialSnap});

  final OfficialAnkiSourceAwareStatsSnapshot officialSnap;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(AppSpacing.lg),
      decoration: TurnaTheme.flatPaperDecoration(
        context,
        borderRadius: TurnaTheme.borderRadius,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const TurnaIcon(
            TurnaIconId.info,
            color: TurnaTheme.brandTeal,
            size: 20,
          ),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  AppStrings.ankiStatsOfficialSemantics,
                  style: AppTextStyles.cardTitle(context),
                ),
                const SizedBox(height: AppSpacing.xs),
                Text(
                  officialSnap.metricsProven
                      ? AppStrings.ankiStatsSemanticsProven
                      : AppStrings.ankiStatsSemanticsUnavailable(
                          officialSnap.note,
                        ),
                  style: AppTextStyles.captionSm(context),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
