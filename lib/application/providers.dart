// Dart imports:
import 'dart:async';

// Package imports:
import 'package:provider/provider.dart';

// Project imports:
import 'package:turna/application/achievements/achievement_service.dart';
import 'package:turna/application/accessibility_provider.dart';
import 'package:turna/application/ai/ai_course_provider.dart';
import 'package:turna/application/ai/ai_explain_prefs.dart';
import 'package:turna/application/ai/ai_grounded_resource_provider.dart';
import 'package:turna/application/ai/ai_hint_provider.dart';
import 'package:turna/application/ai/ai_lesson_helper_provider.dart';
import 'package:turna/application/ai/ai_saved_explanations.dart';
import 'package:turna/application/ai/ai_wish_provider.dart';
import 'package:turna/application/ai/dictionary_ai_provider.dart';
import 'package:turna/application/ai/engine/ai_engine_config_holder.dart';
import 'package:turna/application/ai/engine/ai_recent_tasks_provider.dart';
import 'package:turna/application/ai/textbook/textbook_import_provider.dart';
import 'package:turna/application/course_provider.dart';
import 'package:turna/application/fun_provider.dart';
import 'package:turna/application/game_provider.dart';
import 'package:turna/application/cosmetic_provider.dart';
import 'package:turna/application/gems_provider.dart';
import 'package:turna/application/grammar_review_provider.dart';
import 'package:turna/application/language_provider.dart';
import 'package:turna/application/lesson_viewmodel.dart';
import 'package:turna/application/memory_curve_provider.dart';
import 'package:turna/application/mistake_provider.dart';
import 'package:turna/application/progress_provider.dart';
import 'package:turna/application/review_dashboard/review_dashboard_repository.dart';
import 'package:turna/application/review_progress_provider.dart';
import 'package:turna/application/settings_provider.dart';
import 'package:turna/application/srs_provider.dart';
import 'package:turna/application/srs_tutor_provider.dart';
import 'package:turna/application/study_stats_provider.dart';
import 'package:turna/application/system_health_monitor.dart';
import 'package:turna/application/theme_provider.dart';
import 'package:turna/di/injection.dart';

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
  // Companion explain prefs: same GetIt singleton as setupLocator (no orphan).
  ChangeNotifierProvider<AiExplainPrefsStore>(
    create: (_) {
      final store = getIt.isRegistered<AiExplainPrefsStore>()
          ? getIt<AiExplainPrefsStore>()
          : AiExplainPrefsStore();
      unawaited(store.load());
      return store;
    },
  ),
  ChangeNotifierProvider<AiHintProvider>(
    create: (ctx) => AiHintProvider(
      prefs: ctx.read<AiExplainPrefsStore>(),
    ),
  ),
  ChangeNotifierProvider<AiSavedExplanationsStore>(
    create: (_) {
      final store = getIt.isRegistered<AiSavedExplanationsStore>()
          ? getIt<AiSavedExplanationsStore>()
          : AiSavedExplanationsStore();
      unawaited(store.load());
      return store;
    },
  ),
  ChangeNotifierProvider<DictionaryAiProvider>(
    create: (ctx) => DictionaryAiProvider(
      prefs: ctx.read<AiExplainPrefsStore>(),
    ),
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
  // pushes to the ring). Companion kinds are prefs-persisted.
  ChangeNotifierProvider<AiRecentTasksProvider>(
    create: (_) {
      final p = getIt<AiRecentTasksProvider>();
      unawaited(p.loadPersisted());
      return p;
    },
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
  ChangeNotifierProvider<CosmeticProvider>(
    create: (_) => getIt<CosmeticProvider>(),
  ),
  // Unified achievement engine: single writer for unlocks / rewards and the
  // only state source the achievement UI reads.
  ChangeNotifierProvider<AchievementService>(
    create: (_) => getIt<AchievementService>(),
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
  ChangeNotifierProvider<SystemHealthMonitor>(
    create: (_) => getIt<SystemHealthMonitor>(),
  ),
  Provider<MemoryCurveProvider>(
    create: (_) => getIt<MemoryCurveProvider>(),
  ),
  Provider<ReviewProgressProvider>(
    create: (_) => getIt<ReviewProgressProvider>(),
  ),
  Provider<ReviewDashboardRepository>(
    create: (_) => getIt<ReviewDashboardRepository>(),
  ),
];
