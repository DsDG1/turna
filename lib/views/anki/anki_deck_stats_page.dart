// Flutter imports:
import 'package:flutter/material.dart';

// Package imports:
import 'package:auto_route/auto_route.dart';
import 'package:provider/provider.dart';

// Project imports:
import 'package:turna/application/anki_official/official_anki_catalog_service.dart';
import 'package:turna/application/anki_official/stats/official_anki_source_aware_stats.dart';
import 'package:turna/application/memory_curve_provider.dart';
import 'package:turna/l10n/app_strings.dart';
import 'package:turna/views/review/components/retention_curve_chart.dart';
import 'package:turna/core/theme.dart';

@RoutePage()
class AnkiDeckStatsPage extends StatefulWidget {
  final String importId;
  final String title;

  const AnkiDeckStatsPage({
    super.key,
    required this.importId,
    required this.title,
  });

  @override
  State<AnkiDeckStatsPage> createState() => _AnkiDeckStatsPageState();
}

class _AnkiDeckStatsPageState extends State<AnkiDeckStatsPage> {
  // crash-hunt PR1: the source lookup is a sync sqlite read and used to run
  // inside build(); the stats future was also re-created per rebuild. Both
  // are resolved once per page lifetime now (PR2 makes the catalog async).
  // A non-null future means importId is an Official source (catalog service
  // resolves catalog + source probe in one call).
  late final Future<OfficialAnkiSourceAwareStatsSnapshot>? _officialStats =
      const OfficialAnkiCatalogService().statsForSource(widget.importId);
  Future<MemoryCurveSnapshot>? _legacyStats;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar:
          AppBar(title: Text(AppStrings.ankiDeckStatsPageTitle(widget.title))),
      body: _officialStats != null
          ? FutureBuilder(
              future: _officialStats,
              builder: (context, snapshot) {
                if (!snapshot.hasData) {
                  return const Center(child: CircularProgressIndicator());
                }
                final officialSnap = snapshot.data!;
                return ListView(
                  padding: const EdgeInsets.all(20),
                  children: [
                    _MetricCard(
                      title: AppStrings.ankiStatsTotalCards,
                      value: '${officialSnap.totalCards}',
                      icon: Icons.style_outlined,
                    ),
                    if (officialSnap.metricsProven) ...[
                      const SizedBox(height: 12),
                      _MetricCard(
                        title: AppStrings.ankiStatsCardStates,
                        value: '${officialSnap.newCount ?? 0} / '
                            '${officialSnap.learningCount ?? 0} / '
                            '${officialSnap.reviewCount ?? 0}',
                        icon: Icons.layers_outlined,
                      ),
                      const SizedBox(height: 12),
                      _MetricCard(
                        title: AppStrings.ankiStatsCardFlags,
                        value: officialSnap.unintroducedCount > 0
                            ? AppStrings.ankiStatsFlagsValue(
                                officialSnap.unintroducedCount,
                                officialSnap.userSuspendedCount,
                                officialSnap.buriedCount ?? 0,
                              )
                            : '${officialSnap.suspendedCount ?? 0} / ${officialSnap.buriedCount ?? 0}',
                        icon: Icons.pause_circle_outline,
                      ),
                      const SizedBox(height: 12),
                      _MetricCard(
                        title: AppStrings.ankiStatsTodayAnswers,
                        value: AppStrings.ankiStatsTodayValue(
                          officialSnap.todayAnswerCount ?? 0,
                          officialSnap.todayLearnCount ?? 0,
                          officialSnap.todayReviewCount ?? 0,
                          officialSnap.todayRelearnCount ?? 0,
                        ),
                        icon: Icons.today_outlined,
                      ),
                      const SizedBox(height: 12),
                      _ForecastCard(
                        forecast: Forecast(
                          dueToday: officialSnap.forecastDueToday ?? 0,
                          due7Days: officialSnap.forecastDue7Days ?? 0,
                          due30Days: officialSnap.forecastDue30Days ?? 0,
                        ),
                      ),
                      const SizedBox(height: 12),
                      _MetricCard(
                        title: AppStrings.ankiStatsRevlogTitle,
                        value: officialSnap.retentionSample == 0
                            ? AppStrings.ankiStatsRevlogNoSample(
                                officialSnap.revlogCount ?? 0)
                            : AppStrings.ankiStatsRevlogValue(
                                officialSnap.revlogCount ?? 0,
                                ((officialSnap.retention ?? 0) * 100).round(),
                                officialSnap.retentionPassed ?? 0,
                                officialSnap.retentionSample ?? 0,
                              ),
                        icon: Icons.track_changes,
                      ),
                      if (officialSnap.retentionByInterval.isNotEmpty) ...[
                        const SizedBox(height: 12),
                        Card(
                          child: Padding(
                            padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(AppStrings.ankiStatsRetentionByInterval,
                                    style: const TextStyle(
                                        fontWeight: FontWeight.w700)),
                                const SizedBox(height: 12),
                                RetentionCurveChart(
                                    curve: officialSnap.retentionByInterval),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ],
                    const SizedBox(height: 12),
                    Card(
                      child: ListTile(
                        leading: Icon(Icons.info_outline,
                            color: TurnaTheme.brandTeal),
                        title: Text(AppStrings.ankiStatsOfficialSemantics),
                        subtitle: Text(
                          officialSnap.metricsProven
                              ? AppStrings.ankiStatsSemanticsProven
                              : AppStrings.ankiStatsSemanticsUnavailable(
                                  officialSnap.note),
                          style: TextStyle(
                            color: TurnaTheme.textHintColor(context),
                          ),
                        ),
                      ),
                    ),
                  ],
                );
              },
            )
          : FutureBuilder<MemoryCurveSnapshot>(
              future: _legacyStats ??= context
                  .read<MemoryCurveProvider>()
                  .snapshotForImportId(widget.importId),
              builder: (context, snapshot) {
                if (snapshot.connectionState != ConnectionState.done) {
                  return const Center(child: CircularProgressIndicator());
                }
                if (snapshot.hasError) {
                  return Center(
                      child: Text(
                          AppStrings.ankiStatsLoadFailed(snapshot.error!)));
                }
                final data = snapshot.data;
                if (data == null || data.totalCards == 0) {
                  return Center(child: Text(AppStrings.ankiStatsEmpty));
                }
                return ListView(
                  padding: const EdgeInsets.all(20),
                  children: [
                    _MetricCard(
                      title: AppStrings.ankiStatsCurrentRetention,
                      value: '${(data.currentRetention * 100).round()}%',
                      icon: Icons.track_changes,
                    ),
                    const SizedBox(height: 12),
                    _ForecastCard(forecast: data.forecast),
                    const SizedBox(height: 12),
                    _MetricCard(
                      title: AppStrings.ankiStatsRevlogLabel,
                      value: AppStrings.ankiStatsRevlogSummary(
                          data.totalReviews,
                          data.trackedCards,
                          data.totalCards),
                      icon: Icons.history,
                    ),
                    if (data.retentionByInterval.isNotEmpty) ...[
                      const SizedBox(height: 12),
                      Card(
                        child: Padding(
                          padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(AppStrings.ankiStatsRetentionTitle,
                                  style: const TextStyle(
                                      fontWeight: FontWeight.w700)),
                              const SizedBox(height: 12),
                              RetentionCurveChart(
                                  curve: data.retentionByInterval),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ],
                );
              },
            ),
    );
  }
}

class _MetricCard extends StatelessWidget {
  final String title;
  final String value;
  final IconData icon;

  const _MetricCard(
      {required this.title, required this.value, required this.icon});

  @override
  Widget build(BuildContext context) => Card(
        child: ListTile(
          leading: Icon(icon, color: TurnaTheme.brandTeal),
          title: Text(title),
          subtitle: Text(value,
              style: Theme.of(context)
                  .textTheme
                  .titleMedium
                  ?.copyWith(fontWeight: FontWeight.w700)),
        ),
      );
}

class _ForecastCard extends StatelessWidget {
  final Forecast forecast;
  const _ForecastCard({required this.forecast});

  @override
  Widget build(BuildContext context) => Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(AppStrings.ankiStatsForecast,
                  style: const TextStyle(fontWeight: FontWeight.w700)),
              const SizedBox(height: 12),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceAround,
                children: [
                  _ForecastValue(
                      AppStrings.ankiStatsDueToday, forecast.dueToday),
                  _ForecastValue(
                      AppStrings.ankiStatsDue7Days, forecast.due7Days),
                  _ForecastValue(
                      AppStrings.ankiStatsDue30Days, forecast.due30Days),
                ],
              ),
            ],
          ),
        ),
      );
}

class _ForecastValue extends StatelessWidget {
  final String label;
  final int value;
  const _ForecastValue(this.label, this.value);

  @override
  Widget build(BuildContext context) => Column(
        children: [
          Text('$value',
              style: Theme.of(context)
                  .textTheme
                  .headlineSmall
                  ?.copyWith(fontWeight: FontWeight.w800)),
          Text(label),
        ],
      );
}
