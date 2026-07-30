// Flutter imports:
import 'package:flutter/material.dart';

// Package imports:
import 'package:auto_route/auto_route.dart';
import 'package:provider/provider.dart';

// Project imports:
import 'package:varnamala/application/game_provider.dart';
import 'package:varnamala/application/gems_provider.dart';
import 'package:varnamala/application/grammar_review_provider.dart';
import 'package:varnamala/application/language_provider.dart';
import 'package:varnamala/application/mistake_provider.dart';
import 'package:varnamala/application/srs_provider.dart';
import 'package:varnamala/data/course_database.dart';
import 'package:varnamala/data/course_repository.dart';
import 'package:varnamala/data/study_log_repository.dart';
import 'package:varnamala/di/injection.dart';
import 'package:varnamala/service/locator.dart';
import 'package:varnamala/service/tab_router.dart';
import 'package:varnamala/views/ai/ai_hub_page.dart';
import 'package:varnamala/views/ai/components/ai_hub_app_bar.dart';
import 'package:varnamala/views/content_update/content_update_dialog.dart';
import 'package:varnamala/views/courses/course_tree.dart';
import 'package:varnamala/views/home/components/components.dart';
import 'package:varnamala/views/home/streak_broken_dialog.dart';
import 'package:varnamala/views/play/play_app_bar.dart';
import 'package:varnamala/views/play/play_hub_screen.dart';
import 'package:varnamala/views/profile/profile_screen.dart';
import 'package:varnamala/views/settings/settings_app_bar.dart';
import 'package:varnamala/views/settings/settings_page.dart';
import 'package:varnamala/views/theme.dart';


@RoutePage()
class HomePage extends StatefulWidget {
  const HomePage({Key? key}) : super(key: key);

  @override
  State<StatefulWidget> createState() {
    return _HomePageState();
  }
}

class _HomePageState extends State<HomePage> {
  int currentIndex = 0;

  final screens = [
    const CourseTree(),
    const PlayHubScreen(),
    const ProfilePage(),
    const SettingsPage(),
    const AiHubPage(),
  ];

  @override
  void initState() {
    super.initState();
    getIt<TabRouter>().index.addListener(_onTabRouteChanged);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      initSession();
    });
  }

  @override
  void dispose() {
    getIt<TabRouter>().index.removeListener(_onTabRouteChanged);
    super.dispose();
  }

  void _onTabRouteChanged() {
    final next = getIt<TabRouter>().index.value;
    if (next == currentIndex) return;
    setState(() => currentIndex = next);
  }

  initSession() async {
    context.read<LanguageProvider>().initLanguage();
    final gameProvider = context.read<GameProvider>();
    final gemsProvider = context.read<GemsProvider>();

    await Future.wait([
      gameProvider.ensureUserGameFields(),
      gemsProvider.ensureGemsInitialized(),
    ]);
    final streakResult = await gameProvider.checkStreakOnAppOpen();

    if (!mounted) return;
    if (streakResult == StreakCheckResult.broken) {
      // Lightweight notice only — no streak repair / freeze / monetization.
      await showDialog<void>(
        context: context,
        barrierDismissible: true,
        builder: (_) => const StreakBrokenDialog(),
      );
    }

    if (!mounted) return;
    // Content-update prompt (ADR 0002): once per content-version bump, when
    // the user has existing progress, offer to keep or reset progress.
    await _maybePromptContentUpdate();
  }

  Future<void> _maybePromptContentUpdate() async {
    final appPrefs = getIt<AppPrefs>();
    final repo = CourseRepository(getIt<CourseDatabase>());
    final storedVersion = await repo.contentVersion();
    if (storedVersion == null) return; // not seeded yet

    final acknowledged = appPrefs.preferences
        .getString(LocalStateKeys.contentVersionAcknowledged, defaultValue: '')
        .getValue();
    if (storedVersion == acknowledged) return; // already acknowledged

    if (!mounted) return;
    final game = context.read<GameProvider>();
    if (game.completedLessonIds.isEmpty) {
      // No progress to protect: silently acknowledge, no dialog.
      await appPrefs.setString(
        LocalStateKeys.contentVersionAcknowledged,
        storedVersion,
      );
      return;
    }

    if (!mounted) return;
    final choice = await showDialog<ContentUpdateChoice>(
      context: context,
      barrierDismissible: false,
      builder: (_) => const ContentUpdateDialog(),
    );
    if (!mounted) return;

    if (choice == ContentUpdateChoice.resetProgress) {
      if (!mounted) return;
      await Future.wait([
        game.resetLessonProgress(),
        context.read<MistakeProvider>().clear(),
        getIt<StudyLogRepository>().clearAll(),
        context.read<SrsProvider>().clear(),
        context.read<GrammarReviewProvider>().clear(),
      ]);
    }
    // Either choice persists the acknowledged version so the dialog won't recur.
    await appPrefs.setString(
      LocalStateKeys.contentVersionAcknowledged,
      storedVersion,
    );
  }

  final List<PreferredSizeWidget> appBars = [
    const StatAppBar(),
    const PlayAppBar(),
    const ProfileAppBar(),
    const SettingsAppBar(),
    const AiHubAppBar(),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: currentIndex == 0
          ? VarnamalaTheme.scaffoldBg(context)
          : VarnamalaTheme.surfaceColor(context),
      appBar: appBars[currentIndex],
      bottomNavigationBar: BottomNavigator(
        currentIndex: currentIndex,
        onPress: onBottomNavigatorTapped,
      ),
      body: IndexedStack(
        index: currentIndex,
        children: screens,
      ),
    );
  }

  void onBottomNavigatorTapped(int index) {
    // Route through TabRouter so external callers (e.g. the lesson "去设置"
    // dialog) and the nav bar share one write path. The listener applies it.
    getIt<TabRouter>().switchTo(index);
  }
}