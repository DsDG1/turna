import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:turna/data/review_history_dao.dart';
import 'package:turna/views/review/learning_insights_page.dart';
import 'package:turna/views/review/review_source_detail_page.dart';

void main() {
  testWidgets('365-day heatmap exposes textual summary and per-day semantics',
      (tester) async {
    final semantics = tester.ensureSemantics();
    final rows = List<ActivityBucketRow>.generate(
      365,
      (index) => ActivityBucketRow(
        bucket: 'day-$index',
        reviewedCount: index == 364 ? 3 : 0,
      ),
    );
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: SingleChildScrollView(
          child: ReviewActivityHeatmap(rows: rows),
        ),
      ),
    ));

    expect(find.text('过去 365 天有 1 个活跃日，共完成 3 次复习'), findsOneWidget);
    expect(
      find.bySemanticsLabel(RegExp('过去 365 天有 1 个活跃日，共完成 3 次复习')),
      findsWidgets,
    );
    expect(find.bySemanticsLabel('day-364：3 次复习'), findsOneWidget);
    semantics.dispose();
  });

  testWidgets('deleted source state is explicit and hides when active',
      (tester) async {
    await tester.pumpWidget(const MaterialApp(
      home: Scaffold(
        body: ReviewSourceAvailabilityBanner(active: false),
      ),
    ));
    expect(find.text('已删除来源'), findsOneWidget);
    expect(find.text('来源当前不可复习，但历史统计仍会保留。'), findsOneWidget);

    await tester.pumpWidget(const MaterialApp(
      home: Scaffold(
        body: ReviewSourceAvailabilityBanner(active: true),
      ),
    ));
    expect(find.text('已删除来源'), findsNothing);
  });
}
