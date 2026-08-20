// Flutter imports:
import 'package:flutter/material.dart';

// Package imports:
import 'package:auto_route/auto_route.dart';
import 'package:provider/provider.dart';

// Project imports:
import 'package:turna/application/memory_curve_provider.dart';
import 'package:turna/views/review/components/retention_curve_chart.dart';
import 'package:turna/views/theme.dart';

@RoutePage()
class AnkiDeckStatsPage extends StatelessWidget {
  final String importId;
  final String title;

  const AnkiDeckStatsPage({
    super.key,
    required this.importId,
    required this.title,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text('$title · 统计')),
      body: FutureBuilder<MemoryCurveSnapshot>(
        future:
            context.read<MemoryCurveProvider>().snapshotForImportId(importId),
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
                            style: TextStyle(fontWeight: FontWeight.w700)),
                        const SizedBox(height: 12),
                        RetentionCurveChart(curve: data.retentionByInterval),
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
