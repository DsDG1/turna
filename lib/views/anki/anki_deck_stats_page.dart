// Flutter imports:
import 'package:flutter/material.dart';

// Package imports:
import 'package:auto_route/auto_route.dart';
import 'package:provider/provider.dart';

// Project imports:
import 'package:turna/application/anki_official/official_anki_composition.dart';
import 'package:turna/application/anki_official/stats/official_anki_source_aware_stats.dart';
import 'package:turna/application/anki_official/storage/official_anki_database.dart';
import 'package:turna/application/anki_official/storage/official_anki_source_dao.dart';
import 'package:turna/application/memory_curve_provider.dart';
import 'package:turna/views/review/components/retention_curve_chart.dart';
import 'package:turna/views/theme.dart';

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
  late final OfficialAnkiDatabase? _officialCatalog = _resolveCatalog();
  late final Future<OfficialAnkiSourceAwareStatsSnapshot>? _officialStats =
      _officialCatalog == null
          ? null
          : OfficialAnkiSourceAwareStats(
              sources: OfficialAnkiSourceDao(_officialCatalog),
              engine: OfficialAnkiCompositionRoot.engine,
            ).forOfficialSource(widget.importId);
  Future<MemoryCurveSnapshot>? _legacyStats;

  OfficialAnkiDatabase? _resolveCatalog() {
    final catalog = OfficialAnkiCompositionRoot.readOnlyCatalog;
    if (catalog == null) return null;
    return OfficialAnkiSourceDao(catalog).findById(widget.importId) != null
        ? catalog
        : null;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('${widget.title} · 统计')),
      body: _officialCatalog != null
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
                      title: '卡片总数（Official catalog）',
                      value: '${officialSnap.totalCards}',
                      icon: Icons.style_outlined,
                    ),
                    if (officialSnap.metricsProven) ...[
                      const SizedBox(height: 12),
                      _MetricCard(
                        title: '卡片状态（新卡 / 学习 / 复习）',
                        value: '${officialSnap.newCount ?? 0} / '
                            '${officialSnap.learningCount ?? 0} / '
                            '${officialSnap.reviewCount ?? 0}',
                        icon: Icons.layers_outlined,
                      ),
                      const SizedBox(height: 12),
                      _MetricCard(
                        title: '卡片门控（未解锁 / 暂停 / 埋藏）',
                        value: officialSnap.unintroducedCount > 0
                            ? '${officialSnap.unintroducedCount} 待学 · ${officialSnap.userSuspendedCount} 暂停 / ${officialSnap.buriedCount ?? 0} 埋藏'
                            : '${officialSnap.suspendedCount ?? 0} / ${officialSnap.buriedCount ?? 0}',
                        icon: Icons.pause_circle_outline,
                      ),
                      const SizedBox(height: 12),
                      _MetricCard(
                        title: '今日作答（学习 / 复习 / 重学）',
                        value: '${officialSnap.todayAnswerCount ?? 0} 次 · '
                            '${officialSnap.todayLearnCount ?? 0} / '
                            '${officialSnap.todayReviewCount ?? 0} / '
                            '${officialSnap.todayRelearnCount ?? 0}',
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
                        title: '复习记录 / True retention',
                        value: officialSnap.retentionSample == 0
                            ? '${officialSnap.revlogCount ?? 0} 次 · 暂无有效保持率样本'
                            : '${officialSnap.revlogCount ?? 0} 次 · '
                                '${((officialSnap.retention ?? 0) * 100).round()}% '
                                '(${officialSnap.retentionPassed}/'
                                '${officialSnap.retentionSample})',
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
                                const Text('按间隔保持率（记忆曲线）',
                                    style:
                                        TextStyle(fontWeight: FontWeight.w700)),
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
                        title: const Text('Official 统计语义'),
                        subtitle: Text(
                          officialSnap.metricsProven
                              ? '状态、预报和保持率来自 Official collection 的精确 source card 集合。'
                              : 'Official 指标不可用（${officialSnap.note}）；仅 catalog 卡片总数可信，未把失败显示成 0。',
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
                  return Center(child: Text('统计加载失败：${snapshot.error}'));
                }
                final data = snapshot.data;
                if (data == null || data.totalCards == 0) {
                  return const Center(child: Text('这个牌组还没有可用统计数据'));
                }
                return ListView(
                  padding: const EdgeInsets.all(20),
                  children: [
                    _MetricCard(
                      title: '当前保持率',
                      value: '${(data.currentRetention * 100).round()}%',
                      icon: Icons.track_changes,
                    ),
                    const SizedBox(height: 12),
                    _ForecastCard(forecast: data.forecast),
                    const SizedBox(height: 12),
                    _MetricCard(
                      title: '复习记录',
                      value:
                          '${data.totalReviews} 次 · ${data.trackedCards}/${data.totalCards} 张已复习',
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
                              const Text('按间隔保持率',
                                  style:
                                      TextStyle(fontWeight: FontWeight.w700)),
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
              const Text('预测到期', style: TextStyle(fontWeight: FontWeight.w700)),
              const SizedBox(height: 12),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceAround,
                children: [
                  _ForecastValue('今天', forecast.dueToday),
                  _ForecastValue('7 天', forecast.due7Days),
                  _ForecastValue('30 天', forecast.due30Days),
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
