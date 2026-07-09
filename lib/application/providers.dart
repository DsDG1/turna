// Package imports:
import 'package:provider/provider.dart';

// Project imports:
import 'package:words625/application/achievements_provider.dart';
import 'package:words625/application/character_provider.dart';
import 'package:words625/application/course_provider.dart';
import 'package:words625/application/game_provider.dart';
import 'package:words625/application/gems_provider.dart';
import 'package:words625/application/grammar_review_provider.dart';
import 'package:words625/application/hearts_provider.dart';
import 'package:words625/application/language_provider.dart';
import 'package:words625/application/lesson_viewmodel.dart';
import 'package:words625/application/match_provider.dart';
import 'package:words625/application/mistake_provider.dart';
import 'package:words625/application/progress_provider.dart';
import 'package:words625/application/srs_provider.dart';
import 'package:words625/application/study_stats_provider.dart';
import 'package:words625/application/theme_provider.dart';
import 'package:words625/di/injection.dart';

import 'package:words625/service/locator.dart';

/// App-wide [ChangeNotifier] graph. Every `getIt<T>()` here must resolve the
/// **same** instance that constructor-injected collaborators receive
/// (stateful services are `@lazySingleton` — see Wave A).
final providers = [
  ChangeNotifierProvider<ThemeProvider>(
    create: (_) => ThemeProvider(getIt<AppPrefs>()),
  ),
  ChangeNotifierProvider<CharacterProvider>(
    create: (_) => getIt<CharacterProvider>(),
  ),
  ChangeNotifierProvider<LanguageProvider>(
    create: (_) => getIt<LanguageProvider>(),
  ),
  ChangeNotifierProvider<CourseProvider>(
    create: (_) => getIt<CourseProvider>(),
  ),
  ChangeNotifierProvider<LessonViewModel>(
    create: (_) => getIt<LessonViewModel>(),
  ),
  ChangeNotifierProvider<GameProvider>(
    create: (_) => getIt<GameProvider>(),
  ),
  ChangeNotifierProvider<GemsProvider>(
    create: (_) => getIt<GemsProvider>(),
  ),
  ChangeNotifierProvider<HeartsProvider>(
    create: (_) => getIt<HeartsProvider>(),
  ),
  ChangeNotifierProvider<AchievementsProvider>(
    create: (_) => getIt<AchievementsProvider>(),
  ),
  ChangeNotifierProvider<MatchProvider>(
    create: (_) => getIt<MatchProvider>(),
  ),
  ChangeNotifierProvider<SrsProvider>(
    create: (_) => getIt<SrsProvider>(),
  ),
  ChangeNotifierProvider<GrammarReviewProvider>(
    create: (_) => getIt<GrammarReviewProvider>(),
  ),
  ChangeNotifierProvider<MistakeProvider>(
    create: (_) => getIt<MistakeProvider>(),
  ),
  ChangeNotifierProvider<ProgressProvider>(
    create: (_) => getIt<ProgressProvider>(),
  ),
  ChangeNotifierProvider<StudyStatsProvider>(
    create: (_) => getIt<StudyStatsProvider>(),
  ),
];