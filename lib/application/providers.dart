// Package imports:
import 'package:provider/provider.dart';

// Project imports:
import 'package:varnamala/application/achievements_provider.dart';
import 'package:varnamala/application/accessibility_provider.dart';
import 'package:varnamala/application/ai/ai_course_provider.dart';
import 'package:varnamala/application/ai/ai_grounded_resource_provider.dart';
import 'package:varnamala/application/ai/ai_hint_provider.dart';
import 'package:varnamala/application/ai/ai_lesson_helper_provider.dart';
import 'package:varnamala/application/ai/ai_wish_provider.dart';
import 'package:varnamala/application/ai/engine/ai_engine_config_holder.dart';
import 'package:varnamala/application/ai/engine/ai_recent_tasks_provider.dart';
import 'package:varnamala/application/ai/textbook/textbook_import_provider.dart';
import 'package:varnamala/application/character_provider.dart';
import 'package:varnamala/application/course_provider.dart';
import 'package:varnamala/application/fun_provider.dart';
import 'package:varnamala/application/game_provider.dart';
import 'package:varnamala/application/gems_provider.dart';
import 'package:varnamala/application/grammar_review_provider.dart';
import 'package:varnamala/application/language_provider.dart';
import 'package:varnamala/application/lesson_viewmodel.dart';
import 'package:varnamala/application/match_provider.dart';
import 'package:varnamala/application/memory_curve_provider.dart';
import 'package:varnamala/application/mistake_provider.dart';
import 'package:varnamala/application/progress_provider.dart';
import 'package:varnamala/application/review_progress_provider.dart';
import 'package:varnamala/application/settings_provider.dart';
import 'package:varnamala/application/srs_provider.dart';
import 'package:varnamala/application/srs_tutor_provider.dart';
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
  ChangeNotifierProvider<AiWishProvider>(
    create: (_) => AiWishProvider(),
  ),
  ChangeNotifierProvider<AiGroundedResourceProvider>(
    create: (_) => AiGroundedResourceProvider(),
  ),
  ChangeNotifierProvider<AiLessonHelperProvider>(
    create: (_) => AiLessonHelperProvider(),
  ),
  ChangeNotifierProvider<TextbookImportProvider>(
    create: (_) => TextbookImportProvider(),
  ),
  ChangeNotifierProvider<AiHintProvider>(
    create: (_) => AiHintProvider(),
  ),
  // In-memory AI engine config (provider / models / cache toggle). The engine
  // singletons (AiHttpClient, AiCache, AiEngine) are resolved via GetIt; this
  // holder is the UI-facing ChangeNotifier the Settings sheet watches.
  ChangeNotifierProvider<AiEngineConfigHolder>(
    create: (_) => getIt<AiEngineConfigHolder>(),
  ),
  // Recent AI tasks the engine consumers have completed. The Hub's Continue
  // section reads from this provider. Cache hits are intentionally NOT
  // recorded (the engine stays domain-agnostic; only the calling provider
  // pushes to the ring).
  ChangeNotifierProvider<AiRecentTasksProvider>(
    create: (_) => getIt<AiRecentTasksProvider>(),
  ),
  ChangeNotifierProvider<ThemeProvider>(
    create: (_) => getIt<ThemeProvider>(),
  ),
  ChangeNotifierProvider<SettingsProvider>(
    create: (_) => getIt<SettingsProvider>(),
  ),
  ChangeNotifierProvider<AccessibilityProvider>(
    create: (_) => getIt<AccessibilityProvider>(),
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
  ChangeNotifierProvider<SrsTutorProvider>(
    create: (_) => getIt<SrsTutorProvider>(),
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
  ChangeNotifierProvider<FunProvider>(
    create: (_) => getIt<FunProvider>(),
  ),
  Provider<MemoryCurveProvider>(
    create: (_) => getIt<MemoryCurveProvider>(),
  ),
  Provider<ReviewProgressProvider>(
    create: (_) => getIt<ReviewProgressProvider>(),
  ),
];