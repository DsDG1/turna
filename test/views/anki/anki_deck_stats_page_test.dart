import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:turna/application/anki_official/migration/official_anki_engine_kind.dart';
import 'package:turna/application/anki_official/stats/official_anki_source_aware_stats.dart';
import 'package:turna/application/memory_curve_provider.dart';
import 'package:turna/core/theme.dart';
import 'package:turna/l10n/app_strings.dart';
import 'package:turna/views/anki/anki_deck_stats_page.dart';
import 'package:turna/views/widgets/report_kit.dart';

void main() {
  OfficialAnkiSourceAwareStatsSnapshot buildSnapshot({
    List<RetentionPoint> curve = const [
      RetentionPoint(intervalBucketDays: 1, retention: 0.9, sampleSize: 10),
      RetentionPoint(intervalBucketDays: 7, retention: 0.82, sampleSize: 8),
    ],
  }) {
    return OfficialAnkiSourceAwareStatsSnapshot(
      sourceId: 'src-1',
      owner: AnkiEngineKind.official,
      totalCards: 42,
      availability: OfficialStatsAvailability.available,
      newCount: 10,
      learningCount: 12,
      reviewCount: 20,
      suspendedCount: 1,
      buriedCount: 2,
      todayAnswerCount: 15,
      todayLearnCount: 5,
      todayReviewCount: 8,
      todayRelearnCount: 2,
      forecastDueToday: 4,
      forecastDue7Days: 14,
      forecastDue30Days: 30,
      revlogCount: 100,
      retentionPassed: 85,
      retentionFailed: 15,
      retentionByInterval: curve,
    );
  }

  testWidgets('load failure renders retry UI and recovers with ReportKit',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(800, 1800));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    var attempts = 0;
    Future<OfficialAnkiSourceAwareStatsSnapshot> loader(String id) async {
      attempts++;
      if (attempts == 1) {
        throw StateError('deck stats load failed');
      }
      return buildSnapshot();
    }

    await tester.pumpWidget(
      MaterialApp(
        theme: TurnaTheme.lightTheme,
        home: AnkiDeckStatsPage(
          importId: 'src-1',
          title: 'Core Turkish',
          statsLoader: loader,
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text(AppStrings.deckStatsLoadFailed), findsOneWidget);
    expect(find.text(AppStrings.commonRetry), findsOneWidget);

    await tester.tap(find.text(AppStrings.commonRetry));
    await tester.pumpAndSettle();

    expect(find.text(AppStrings.deckStatsLoadFailed), findsNothing);
    expect(find.byType(ReportMetricHeader), findsOneWidget);
    expect(find.byType(ReportCompositionBar), findsOneWidget);
    expect(find.byType(ReportDefinitionList), findsNWidgets(2));
    expect(find.byType(ReportLineChart), findsOneWidget);
    expect(find.text('42'), findsOneWidget);
    expect(find.text(AppStrings.ankiDeckStatsCardsUnit), findsOneWidget);
    expect(find.text(AppStrings.ankiStatsOfficialSemantics), findsOneWidget);
    expect(find.byType(Card), findsNothing);
  });

  testWidgets('retention curve under 2 points omits ReportLineChart',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(800, 1800));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(
      MaterialApp(
        theme: TurnaTheme.lightTheme,
        home: AnkiDeckStatsPage(
          importId: 'src-1',
          title: 'Core Turkish',
          statsLoader: (_) async => buildSnapshot(
            curve: const [
              RetentionPoint(
                intervalBucketDays: 1,
                retention: 0.9,
                sampleSize: 5,
              ),
            ],
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byType(ReportMetricHeader), findsOneWidget);
    expect(find.byType(ReportLineChart), findsNothing);
    expect(find.text(AppStrings.ankiStatsRetentionByInterval), findsNothing);
  });
}
