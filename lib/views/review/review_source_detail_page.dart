import 'package:auto_route/auto_route.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:turna/application/review_dashboard/insights_repository.dart';
import 'package:turna/application/review_dashboard/review_data_revision.dart';
import 'package:turna/application/review_progress_provider.dart';
import 'package:turna/di/injection.dart';
import 'package:turna/routing/routing.gr.dart';
import 'package:turna/views/theme.dart';

@RoutePage()
class ReviewSourceDetailPage extends StatefulWidget {
  const ReviewSourceDetailPage({super.key, required this.source});

  final ReviewSource source;

  @override
  State<ReviewSourceDetailPage> createState() => _ReviewSourceDetailPageState();
}

class _ReviewSourceDetailPageState extends State<ReviewSourceDetailPage> {
  late final ReviewProgressProvider _progress;
  late final InsightsRepository _insights;
  late Future<_SourceDetailData> _future;

  @override
  void initState() {
    super.initState();
    _progress = context.read<ReviewProgressProvider>();
    _insights = InsightsRepository(_progress, getIt<ReviewDataRevision>());
    _future = _load();
  }

  Future<_SourceDetailData> _load() async {
    final active = widget.source.active;
    final snapshot = await _insights.load(InsightsQuery(
      range: EventRange.d30,
      source: widget.source,
      type: ProgressTypeFilter.all,
    ));
    return _SourceDetailData(active: active, snapshot: snapshot);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(widget.source.label)),
      body: FutureBuilder<_SourceDetailData>(
        future: _future,
        builder: (context, state) {
          final data = state.data;
          if (data == null) {
            if (state.hasError) {
              return Center(
                child: FilledButton.icon(
                  onPressed: () => setState(() => _future = _load()),
                  icon: const Icon(Icons.refresh_rounded),
                  label: const Text('重新加载'),
                ),
              );
            }
            return const Center(child: CircularProgressIndicator());
          }
          final summary = data.snapshot.aggregate;
          final activity = data.snapshot.activity;
          final todayCompleted =
              activity.isEmpty ? 0 : activity.last.reviewedCount;
          final reviews7 = activity
              .skip(activity.length > 7 ? activity.length - 7 : 0)
              .fold<int>(0, (sum, row) => sum + row.reviewedCount);
          final reviews30 = activity
              .skip(activity.length > 30 ? activity.length - 30 : 0)
              .fold<int>(0, (sum, row) => sum + row.reviewedCount);
          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              if (!data.active)
                const ReviewSourceAvailabilityBanner(active: false),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Row(
                    children: [
                      _Metric(label: '今日到期', value: summary.forecast.dueToday),
                      _Metric(label: '新卡', value: summary.maturity.newCards),
                      _Metric(label: '今日完成', value: todayCompleted),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 12),
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '7 / 30 日趋势',
                        style: Theme.of(context)
                            .textTheme
                            .titleMedium
                            ?.copyWith(fontWeight: FontWeight.w700),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        '过去 7 日 $reviews7 次，30 日 $reviews30 次；'
                        '图表数据使用固定桶聚合，不加载历史事件正文。',
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 20),
              if (data.active)
                FilledButton.icon(
                  onPressed: _startReview,
                  icon: const Icon(Icons.play_arrow_rounded),
                  label: const Text('开始该来源复习'),
                ),
            ],
          );
        },
      ),
    );
  }

  void _startReview() {
    switch (widget.source.kind) {
      case ReviewSourceKind.course:
        context.router.push(const SrsReviewRoute());
        return;
      case ReviewSourceKind.grammar:
        context.router.push(const GrammarReviewRoute());
        return;
      case ReviewSourceKind.ankiDeck:
      case ReviewSourceKind.ankiOfficial:
        context.router.push(const AnkiReviewRoute());
        return;
      case ReviewSourceKind.all:
        context.router.push(const SrsReviewRoute());
        return;
    }
  }
}

class ReviewSourceAvailabilityBanner extends StatelessWidget {
  const ReviewSourceAvailabilityBanner({super.key, required this.active});

  final bool active;

  @override
  Widget build(BuildContext context) {
    if (active) return const SizedBox.shrink();
    return Card(
      color: TurnaTheme.warning.withValues(alpha: 0.12),
      child: const ListTile(
        leading: Icon(Icons.inventory_2_outlined),
        title: Text('已删除来源'),
        subtitle: Text('来源当前不可复习，但历史统计仍会保留。'),
      ),
    );
  }
}

class _Metric extends StatelessWidget {
  const _Metric({required this.label, required this.value});
  final String label;
  final int value;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Column(
        children: [
          Text(
            '$value',
            style: Theme.of(context)
                .textTheme
                .headlineSmall
                ?.copyWith(fontWeight: FontWeight.w800),
          ),
          Text(label, textAlign: TextAlign.center),
        ],
      ),
    );
  }
}

class _SourceDetailData {
  const _SourceDetailData({required this.active, required this.snapshot});
  final bool active;
  final ReviewProgressSnapshot snapshot;
}
