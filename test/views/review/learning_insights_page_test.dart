import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:provider/provider.dart';
import 'package:turna/application/memory_curve_provider.dart';
import 'package:turna/application/review_dashboard/review_data_revision.dart';
import 'package:turna/application/review_progress_provider.dart';
import 'package:turna/application/study_stats_provider.dart';
import 'package:turna/l10n/app_strings.dart';
import 'package:turna/views/review/learning_insights_page.dart';
import 'package:turna/views/widgets/report_kit.dart';

import '../../helpers/fake_study_stats.dart';

class _FlakyReviewProgressProvider implements ReviewProgressProvider {
  bool shouldFail = true;

  @override
  Future<ReviewProgressSnapshot> computeSnapshot([
    ReviewProgressFilter filter = const ReviewProgressFilter(),
  ]) async {
    if (shouldFail) {
      throw StateError('insights load failed');
    }
    return ReviewProgressSnapshot(
      aggregate: const MemoryCurveSnapshot(
        currentRetention: 0.85,
        meanMastery: 0.72,
        trackedCards: 4,
        totalCards: 5,
        forecast: Forecast(dueToday: 1, due7Days: 2, due30Days: 3),
        maturity: MaturityBreakdown(
          newCards: 1,
          young: 1,
          mature: 2,
          leech: 0,
        ),
        retentionByInterval: [
          RetentionPoint(intervalBucketDays: 1, retention: 0.9, sampleSize: 5),
          RetentionPoint(intervalBucketDays: 7, retention: 0.8, sampleSize: 4),
        ],
        totalReviews: 9,
      ),
      bySource: const [],
      filter: filter,
      availableSources: const [ReviewSource.all],
    );
  }

  @override
  noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  setUp(() async {
    await GetIt.instance.reset();
    GetIt.instance.registerSingleton<ReviewDataRevision>(ReviewDataRevision());
  });

  tearDown(() async {
    await GetIt.instance.reset();
  });

  testWidgets('initial load failure shows retry UI and recovers on retry',
      (tester) async {
    final progress = _FlakyReviewProgressProvider();
    await tester.binding.setSurfaceSize(const Size(800, 1800));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          Provider<ReviewProgressProvider>.value(value: progress),
          ChangeNotifierProvider<StudyStatsProvider>.value(
            value: FakeStudyStatsProvider(),
          ),
        ],
        child: const MaterialApp(home: LearningInsightsPage()),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text(AppStrings.insightsLoadFailed), findsOneWidget);
    expect(find.text(AppStrings.commonRetry), findsOneWidget);

    progress.shouldFail = false;
    await tester.tap(find.text(AppStrings.commonRetry));
    await tester.pumpAndSettle();

    expect(find.text(AppStrings.insightsLoadFailed), findsNothing);
    expect(find.text(AppStrings.reviewProgressKpiRetention), findsOneWidget);
    expect(find.byType(ReportLineChart), findsOneWidget);
  });
}
