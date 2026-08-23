import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:turna/data/review_history_dao.dart';
import 'package:turna/views/review/learning_insights_page.dart';
import 'package:turna/views/theme.dart';

void main() {
  Future<void> pumpFixture(WidgetTester tester, ThemeData theme) async {
    await tester.binding.setSurfaceSize(const Size(420, 760));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final rows = List<ActivityBucketRow>.generate(
      35,
      (index) => ActivityBucketRow(
        bucket: '2026-08-${(index % 28 + 1).toString().padLeft(2, '0')}',
        reviewedCount: index % 5,
      ),
    );
    await tester.pumpWidget(MaterialApp(
      theme: theme,
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context).copyWith(
          textScaler: const TextScaler.linear(2),
          highContrast: true,
          disableAnimations: true,
        ),
        child: child!,
      ),
      home: Scaffold(
        body: RepaintBoundary(
          key: const ValueKey('round2-insights-fixture'),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: SingleChildScrollView(
              child: ReviewActivityHeatmap(rows: rows),
            ),
          ),
        ),
      ),
    ));
    await tester.pumpAndSettle();
  }

  testWidgets('insights high contrast 200% light', (tester) async {
    await pumpFixture(tester, TurnaTheme.highContrastLightTheme);
    await expectLater(
      find.byKey(const ValueKey('round2-insights-fixture')),
      matchesGoldenFile('goldens/round2_insights_hc_200_light.png'),
    );
  });

  testWidgets('insights high contrast 200% dark', (tester) async {
    await pumpFixture(tester, TurnaTheme.highContrastDarkTheme);
    await expectLater(
      find.byKey(const ValueKey('round2-insights-fixture')),
      matchesGoldenFile('goldens/round2_insights_hc_200_dark.png'),
    );
  });
}
