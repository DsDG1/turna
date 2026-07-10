// Flutter imports:
import 'package:flutter/material.dart';

// Package imports:
import 'package:auto_route/annotations.dart';
import 'package:provider/provider.dart';

// Project imports:
import 'package:varnamala/application/game_provider.dart';
import 'package:varnamala/application/gems_provider.dart';
import 'package:varnamala/application/language_provider.dart';
import 'package:varnamala/views/courses/course_tree.dart';
import 'package:varnamala/views/home/components/components.dart';
import 'package:varnamala/views/play/play_app_bar.dart';
import 'package:varnamala/views/play/play_hub_screen.dart';
import 'package:varnamala/views/profile/profile_screen.dart';
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
  ];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      initSession();
    });
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
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Your streak was broken. Start again today.'),
          backgroundColor: VarnamalaTheme.error,
        ),
      );
    }
  }

  final List<PreferredSizeWidget> appBars = [
    const StatAppBar(),
    const PlayAppBar(),
    const ProfileAppBar(),
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
      body: RepaintBoundary(
        child: AnimatedSwitcher(
          duration: const Duration(milliseconds: 200),
          child: screens[currentIndex],
        ),
      ),
    );
  }

  void onBottomNavigatorTapped(int index) {
    setState(() {
      currentIndex = index;
    });
  }
}