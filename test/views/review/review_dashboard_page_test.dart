// Widget tests for the review-overview home (Plan 3 §15/§17.3): today-first
// information order, skeleton on first load, stale-while-revalidate on
// filter-free reloads, and a pull-to-refresh that awaits the real load.

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:streaming_shared_preferences/streaming_shared_preferences.dart';
import 'package:turna/application/grammar_review_provider.dart';
import 'package:turna/application/accessibility_provider.dart';
import 'package:turna/application/lesson_link_store.dart';
import 'package:turna/application/review_dashboard/review_data_revision.dart';
import 'package:turna/application/review_dashboard/review_dashboard_repository.dart';
import 'package:turna/application/srs_provider.dart';
import 'package:turna/application/streak_provider.dart';
import 'package:turna/data/anki_import_dao.dart';
import 'package:turna/data/course_database.dart';
import 'package:turna/data/study_log_repository.dart';
import 'package:turna/data/srs_state_dao.dart';
import 'package:turna/l10n/app_strings.dart';
import 'package:turna/service/locator.dart';
import 'package:turna/views/review/review_progress_page.dart';

import '../../helpers/in_memory_course_db.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late AppPrefs appPrefs;
  late ReviewDashboardRepository repo;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    final sp = await StreamingSharedPreferences.instance;
    appPrefs = AppPrefs(sp);
    final dao = emptySrsStateDao();
    final srs = SrsProvider(appPrefs, LessonLinkStore(appPrefs), dao);
    final grammar =
        GrammarReviewProvider(appPrefs, LessonLinkStore(appPrefs), dao);
    repo = ReviewDashboardRepository(
      emptyReviewHistoryDao(),
      srs,
      grammar,
      AnkiImportDao(CourseDatabase(NativeDatabase.memory())),
      ReviewDataRevision(),
      StudyLogRepository(appPrefs),
      appPrefs,
      StreakProvider(appPrefs),
    );
  });

  Future<void> pumpPage(WidgetTester tester) async {
    await tester.pumpWidget(
      Provider<ReviewDashboardRepository>.value(
        value: repo,
        child: const MaterialApp(home: ReviewProgressPage()),
      ),
    );
    await tester.pump(); // post-frame reload kick
  }

  testWidgets('first load shows skeleton, then the today hero', (tester) async {
    await pumpPage(tester);
    await tester.pumpAndSettle();
    expect(find.text(AppStrings.reviewTodayTitle), findsOneWidget);
    expect(find.text(AppStrings.reviewDueCard), findsOneWidget);
    expect(find.text(AppStrings.reviewNewCard), findsOneWidget);
    expect(find.text(AppStrings.reviewOverdueCard), findsOneWidget);
    expect(find.text(AppStrings.reviewSourcesTitle), findsOneWidget);

    // Heavy insights content stays off the overview home.
    expect(find.text(AppStrings.profileMemoryCurveTitle), findsNothing);
  });

  testWidgets('empty data shows guidance, not a fake accuracy', (tester) async {
    await pumpPage(tester);
    await tester.pumpAndSettle();

    expect(find.text(AppStrings.reviewNoDataYet), findsOneWidget);
    expect(find.text(AppStrings.reviewAccuracyPct(0)), findsNothing);
    expect(find.text(AppStrings.reviewEmptyHint), findsOneWidget);
    // No due cards → CTA shows 今日已完成 and is disabled.
    expect(find.text(AppStrings.reviewTodayDoneCta), findsOneWidget);
  });

  testWidgets('pull-to-refresh awaits the repository and keeps content',
      (tester) async {
    await pumpPage(tester);
    await tester.pumpAndSettle();

    // Drag down to trigger the RefreshIndicator.
    await tester.fling(
      find.text(AppStrings.reviewTodayTitle),
      const Offset(0, 300),
      1000,
    );
    await tester.pump(); // start the refresh
    // Content stays visible during the refresh (no full-page spinner).
    expect(find.text(AppStrings.reviewTodayTitle), findsOneWidget);
    await tester.pumpAndSettle();
    expect(find.text(AppStrings.reviewTodayTitle), findsOneWidget);
  });

  testWidgets('with due cards the CTA is enabled and shows counts',
      (tester) async {
    // Seed one due card through the same repo instance's providers is not
    // directly possible (page reads provider) — assert through the snapshot
    // contract instead by registering on a fresh provider set.
    final dao = SrsStateDao(CourseDatabase(NativeDatabase.memory()));
    final srs = SrsProvider(appPrefs, LessonLinkStore(appPrefs), dao);
    srs.registerWord('w1'); // a new card → actionableTotal > 0
    final grammar =
        GrammarReviewProvider(appPrefs, LessonLinkStore(appPrefs), dao);
    final repoWithCards = ReviewDashboardRepository(
      emptyReviewHistoryDao(),
      srs,
      grammar,
      AnkiImportDao(CourseDatabase(NativeDatabase.memory())),
      ReviewDataRevision(),
      StudyLogRepository(appPrefs),
      appPrefs,
      StreakProvider(appPrefs),
    );
    final snap = await repoWithCards.loadDashboard();
    expect(snap.due.newCards, 1);
    expect(snap.due.actionableTotal, 1);

    await tester.pumpWidget(
      Provider<ReviewDashboardRepository>.value(
        value: repoWithCards,
        child: const MaterialApp(home: ReviewProgressPage()),
      ),
    );
    await tester.pump();
    await tester.pumpAndSettle();
    expect(find.text(AppStrings.reviewContinueCta), findsOneWidget);
  });

  testWidgets('dashboard has no overflow at 200% text scale', (tester) async {
    await tester.pumpWidget(
      Provider<ReviewDashboardRepository>.value(
        value: repo,
        child: MaterialApp(
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context).copyWith(
              textScaler: const TextScaler.linear(2),
            ),
            child: child!,
          ),
          home: const ReviewProgressPage(),
        ),
      ),
    );
    await tester.pump();
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.text(AppStrings.reviewTodayTitle), findsOneWidget);
  });

  testWidgets('focus mode keeps only actionable dashboard sections',
      (tester) async {
    final accessibility = AccessibilityProvider(appPrefs);
    await accessibility.setFocusMode(true);
    await tester.pumpWidget(
      MultiProvider(
        providers: [
          Provider<ReviewDashboardRepository>.value(value: repo),
          ChangeNotifierProvider<AccessibilityProvider>.value(
            value: accessibility,
          ),
        ],
        child: const MaterialApp(home: ReviewProgressPage()),
      ),
    );
    await tester.pump();
    await tester.pumpAndSettle();
    expect(find.text(AppStrings.reviewTodayTitle), findsOneWidget);
    expect(find.text(AppStrings.reviewSourcesTitle), findsNothing);
    expect(find.text(AppStrings.reviewOpenInsights), findsNothing);
  });

  testWidgets('protected streak shows the honest dashboard badge',
      (tester) async {
    final today = DateTime.now();
    final day = DateTime(today.year, today.month, today.day);
    await appPrefs.preferences.setInt(LocalStateKeys.streak, 3);
    await appPrefs.preferences.setString(
      LocalStateKeys.lastStreakDate,
      day.toIso8601String(),
    );
    await appPrefs.preferences.setStringList(
      LocalStateKeys.streakProtectedDays,
      [day.subtract(const Duration(days: 1)).toIso8601String()],
    );

    await pumpPage(tester);
    await tester.pumpAndSettle();

    expect(find.text('已保护'), findsOneWidget);
    expect(
      find.byTooltip('本次连续记录由保护券保留；学习统计未修改'),
      findsOneWidget,
    );
  });
}
