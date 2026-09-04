// Widget tests for achievement grid cards: Fun Lab preview must not
// overflow a two-column cell (the long disclaimer belongs on the page
// banner, not the badge row).

// Flutter imports:
import 'package:flutter/material.dart';

// Package imports:
import 'package:flutter_test/flutter_test.dart';

// Project imports:
import 'package:turna/domain/achievements/achievement_catalog.dart';
import 'package:turna/domain/achievements/achievement_state.dart';
import 'package:turna/l10n/app_strings.dart';
import 'package:turna/views/profile/achievements/achievement_badge_card.dart';
import 'package:turna/views/theme.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final series = AchievementCatalog.allSeries.first;
  const progress = AchievementSeriesProgress(
    seriesId: AchievementCatalog.courseJourneyId,
    currentProgress: 0,
    completedTierCount: 0,
    totalTierCount: 8,
    nextTier: null,
    hasUnseenUnlock: false,
  );

  testWidgets('fun-preview badge fits a 158px two-column cell', (tester) async {
    tester.view.physicalSize = const Size(360, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      MaterialApp(
        theme: TurnaTheme.lightTheme,
        home: Scaffold(
          body: Center(
            child: SizedBox(
              width: 158,
              height: 168,
              child: AchievementBadgeCard(
                series: series,
                progress: progress,
                funPreview: true,
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.text(AppStrings.achievementsFunPreviewTag), findsOneWidget);
    expect(find.text(AppStrings.achievementsFunPreviewBanner), findsNothing);
  });
}
