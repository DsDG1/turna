// Widget test for the achievements grid card: the badge card must not overflow
// when the OS text scale is cranked up (real-device receipt 2026-10-20,
// `BOTTOM OVERFLOWED BY 33 PIXELS` from the old fixed childAspectRatio grid).

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:turna/core/theme.dart';
import 'package:turna/domain/achievements/achievement_catalog.dart';
import 'package:turna/domain/achievements/achievement_state.dart';
import 'package:turna/views/profile/achievements/achievement_badge_card.dart';
import 'package:turna/views/widgets/adaptive_card_grid.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('badge card survives 200% text scale on a narrow phone',
      (tester) async {
    await tester.binding.setSurfaceSize(const Size(360, 780));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final series =
        AchievementCatalog.seriesById(AchievementCatalog.courseJourneyId);
    expect(series, isNotNull, reason: 'catalog must publish 课程行者');
    final nextTier = series!.nextTierAfter(6);
    expect(nextTier, isNotNull, reason: '进度 6 应还有下一档');

    final progress = AchievementSeriesProgress(
      seriesId: series.id,
      currentProgress: 6,
      completedTierCount: series.completedTierCount(6),
      totalTierCount: series.tiers.length,
      nextTier: nextTier,
      hasUnseenUnlock: true,
    );

    await tester.pumpWidget(
      MaterialApp(
        theme: TurnaTheme.lightTheme,
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context).copyWith(
            textScaler: const TextScaler.linear(2),
          ),
          child: child!,
        ),
        home: Scaffold(
          body: Padding(
            padding: const EdgeInsets.all(16),
            child: AdaptiveCardGrid(
              columns: 2,
              spacing: 12,
              children: [
                AchievementBadgeCard(series: series, progress: progress),
                AchievementBadgeCard(series: series, progress: progress),
              ],
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.byType(AchievementBadgeCard), findsNWidgets(2));
  });
}
