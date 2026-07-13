// Package imports:
import 'package:provider/provider.dart';

// Project imports:
import 'package:varnamala/application/achievements_provider.dart';
import 'package:varnamala/application/ai_course_provider.dart';
import 'package:varnamala/application/character_provider.dart';
import 'package:varnamala/application/course_provider.dart';
import 'package:varnamala/application/game_provider.dart';
import 'package:varnamala/application/gems_provider.dart';
import 'package:varnamala/application/grammar_review_provider.dart';
import 'package:varnamala/application/language_provider.dart';
import 'package:varnamala/application/lesson_viewmodel.dart';
import 'package:varnamala/application/match_provider.dart';
import 'package:varnamala/application/mistake_provider.dart';
import 'package:varnamala/application/progress_provider.dart';
import 'package:varnamala/application/settings_provider.dart';
import 'package:varnamala/application/srs_provider.dart';
import 'package:varnamala/application/study_stats_provider.dart';
import 'package:varnamala/application/theme_provider.dart';
import 'package:varnamala/di/injection.dart';

/// App-wide [ChangeNotifier] graph. Every `getIt<T>()` here must resolve the
/// **same** instance that constructor-injected collaborators receive
/// (stateful services are `@lazySingleton` — see Wave A).
final providers = [
  ChangeNotifierProvider<AiCourseProvider>(
    create: (_) => AiCourseProvider(),
  ),
  ChangeNotifierProvider<ThemeProvider>(
    create: (_) => getIt<ThemeProvider>(),
  ),
  ChangeNotifierProvider<SettingsProvider>(
    create: (_) => getIt<SettingsProvider>(),
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