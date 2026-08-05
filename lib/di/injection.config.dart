// GENERATED CODE - DO NOT MODIFY BY HAND
// dart format width=80

// **************************************************************************
// InjectableConfigGenerator
// **************************************************************************

// ignore_for_file: type=lint
// coverage:ignore-file

// ignore_for_file: no_leading_underscores_for_library_prefixes
import 'package:audioplayers/audioplayers.dart' as _i656;
import 'package:flutter_tts/flutter_tts.dart' as _i50;
import 'package:get_it/get_it.dart' as _i174;
import 'package:injectable/injectable.dart' as _i526;

import '../application/accessibility_provider.dart' as _i977;
import '../application/achievements_provider.dart' as _i143;
import '../application/ai/ai_course_provider.dart' as _i859;
import '../application/ai/ai_grounded_resource_provider.dart' as _i1068;
import '../application/ai/ai_lesson_helper_provider.dart' as _i872;
import '../application/ai/ai_wish_provider.dart' as _i561;
import '../application/ai/engine/ai_cache.dart' as _i423;
import '../application/ai/engine/ai_engine.dart' as _i717;
import '../application/ai/engine/ai_engine_config_holder.dart' as _i691;
import '../application/ai/engine/ai_http_client.dart' as _i518;
import '../application/ai/engine/ai_recent_tasks_provider.dart' as _i687;
import '../application/anki/anki_deck_manager.dart' as _i1045;
import '../application/audio_controller.dart' as _i106;
import '../application/character_provider.dart' as _i229;
import '../application/cosmetic_provider.dart' as _i42;
import '../application/course_provider.dart' as _i1051;
import '../application/fun_lab_snapshot_service.dart' as _i141;
import '../application/fun_provider.dart' as _i648;
import '../application/game_milestone_provider.dart' as _i788;
import '../application/game_provider.dart' as _i565;
import '../application/gems_provider.dart' as _i417;
import '../application/grammar_review_provider.dart' as _i1008;
import '../application/language_provider.dart' as _i233;
import '../application/lesson_completion_coordinator.dart' as _i495;
import '../application/lesson_link_store.dart' as _i854;
import '../application/lesson_progress_provider.dart' as _i409;
import '../application/lesson_viewmodel.dart' as _i274;
import '../application/match_provider.dart' as _i9;
import '../application/memory_curve_provider.dart' as _i257;
import '../application/mistake_provider.dart' as _i551;
import '../application/progress_provider.dart' as _i740;
import '../application/review_progress_provider.dart' as _i706;
import '../application/score_provider.dart' as _i166;
import '../application/settings_provider.dart' as _i793;
import '../application/srs_provider.dart' as _i361;
import '../application/srs_tutor_provider.dart' as _i669;
import '../application/streak_provider.dart' as _i927;
import '../application/study_stats_provider.dart' as _i620;
import '../application/theme_provider.dart' as _i151;
import '../courses/languages/vocab_audio_resolver.dart' as _i73;
import '../data/anki_import_dao.dart' as _i151;
import '../data/anki_note_dao.dart' as _i696;
import '../data/course_database.dart' as _i604;
import '../data/course_repository.dart' as _i848;
import '../data/review_history_dao.dart' as _i68;
import '../data/srs_state_dao.dart' as _i336;
import '../data/study_log_repository.dart' as _i889;
import '../domain/audio/anki_audio_resolver.dart' as _i180;
import '../domain/audio/vocab_audio_resolver.dart' as _i188;
import '../domain/repositories/i_course_repository.dart' as _i876;
import '../routing/course_ready_guard.dart' as _i579;
import '../routing/routing.dart' as _i936;
import '../service/local_reminder_service.dart' as _i711;
import '../service/locator.dart' as _i523;
import '../service/tts_availability_checker.dart' as _i307;
import '../views/lesson/components/interactions/anki_card_renderer.dart'
    as _i940;
import '../views/lesson/components/interactions/anki_html_card_renderer.dart'
    as _i681;
import '../views/lesson/components/interactions/fill_blank_renderer.dart'
    as _i665;
import '../views/lesson/components/interactions/interaction_renderer.dart'
    as _i931;
import '../views/lesson/components/interactions/listen_and_pick_renderer.dart'
    as _i657;
import '../views/lesson/components/interactions/listen_only_renderer.dart'
    as _i785;
import '../views/lesson/components/interactions/multi_select_renderer.dart'
    as _i147;
import '../views/lesson/components/interactions/multiple_choice_renderer.dart'
    as _i990;
import '../views/lesson/components/interactions/reading_mcq_renderer.dart'
    as _i235;
import '../views/lesson/components/interactions/reading_short_answer_renderer.dart'
    as _i532;
import '../views/lesson/components/interactions/reading_true_false_renderer.dart'
    as _i399;
import '../views/lesson/components/interactions/reorder_sentence_renderer.dart'
    as _i215;
import '../views/lesson/components/interactions/show_word_renderer.dart'
    as _i440;
import '../views/lesson/components/interactions/translate_sentence_renderer.dart'
    as _i767;
import '../views/lesson/components/interactions/type_the_word_renderer.dart'
    as _i757;
import 'audio_module.dart' as _i83;
import 'renderer_module.dart' as _i702;

extension GetItInjectableX on _i174.GetIt {
// initializes the registration of main-scope dependencies inside of GetIt
  _i174.GetIt init({
    String? environment,
    _i526.EnvironmentFilter? environmentFilter,
  }) {
    final gh = _i526.GetItHelper(
      this,
      environment,
      environmentFilter,
    );
    final audioModule = _$AudioModule();
    final rendererModule = _$RendererModule();
    gh.factory<_i940.AnkiCardRenderer>(() => _i940.AnkiCardRenderer());
    gh.factory<_i681.AnkiHtmlCardRenderer>(() => _i681.AnkiHtmlCardRenderer());
    gh.factory<_i665.FillBlankRenderer>(() => _i665.FillBlankRenderer());
    gh.factory<_i657.ListenAndPickRenderer>(
        () => _i657.ListenAndPickRenderer());
    gh.factory<_i785.ListenOnlyRenderer>(() => _i785.ListenOnlyRenderer());
    gh.factory<_i147.MultiSelectRenderer>(() => _i147.MultiSelectRenderer());
    gh.factory<_i990.MultipleChoiceRenderer>(
        () => _i990.MultipleChoiceRenderer());
    gh.factory<_i235.ReadingMcqRenderer>(() => _i235.ReadingMcqRenderer());
    gh.factory<_i532.ReadingShortAnswerRenderer>(
        () => _i532.ReadingShortAnswerRenderer());
    gh.factory<_i399.ReadingTrueFalseRenderer>(
        () => _i399.ReadingTrueFalseRenderer());
    gh.factory<_i215.ReorderSentenceRenderer>(
        () => _i215.ReorderSentenceRenderer());
    gh.factory<_i767.TranslateSentenceRenderer>(
        () => _i767.TranslateSentenceRenderer());
    gh.factory<_i757.TypeTheWordRenderer>(() => _i757.TypeTheWordRenderer());
    gh.lazySingleton<_i423.AiCache>(() => _i423.AiCache());
    gh.lazySingleton<_i691.AiEngineConfigHolder>(
        () => _i691.AiEngineConfigHolder());
    gh.lazySingleton<_i518.AiHttpClient>(() => _i518.AiHttpClient());
    gh.lazySingleton<_i687.AiRecentTasksProvider>(
        () => _i687.AiRecentTasksProvider());
    gh.lazySingleton<_i229.CharacterProvider>(() => _i229.CharacterProvider());
    gh.lazySingleton<_i180.AnkiAudioResolver>(() => _i180.AnkiAudioResolver());
    gh.lazySingleton<_i711.LocalReminderService>(
        () => _i711.LocalReminderService());
    gh.lazySingleton<_i656.AudioPlayer>(
      () => audioModule.speechPlayer,
      instanceName: 'speechPlayer',
    );
    gh.lazySingleton<_i656.AudioPlayer>(
      () => audioModule.audioPlayer,
      instanceName: 'audioPlayer',
    );
    gh.lazySingleton<_i669.SrsTutorProvider>(() => _i669.SrsTutorProvider(
          engine: gh<_i717.AiEngine>(),
          courseProvider: gh<_i859.AiCourseProvider>(),
          mistakeProvider: gh<_i551.MistakeProvider>(),
          srsDao: gh<_i336.SrsStateDao>(),
        ));
    gh.lazySingleton<_i307.TtsAvailabilityChecker>(
        () => _i307.TtsAvailabilityChecker(gh<_i50.FlutterTts>()));
    gh.lazySingleton<_i188.VocabAudioResolver>(
        () => _i73.VocabAudioResolverImpl());
    gh.lazySingleton<_i143.AchievementsProvider>(
        () => _i143.AchievementsProvider(gh<_i523.AppPrefs>()));
    gh.lazySingleton<_i788.GameMilestoneProvider>(
        () => _i788.GameMilestoneProvider(gh<_i523.AppPrefs>()));
    gh.lazySingleton<_i417.GemsProvider>(
        () => _i417.GemsProvider(gh<_i523.AppPrefs>()));
    gh.lazySingleton<_i233.LanguageProvider>(
        () => _i233.LanguageProvider(gh<_i523.AppPrefs>()));
    gh.lazySingleton<_i854.LessonLinkStore>(
        () => _i854.LessonLinkStore(gh<_i523.AppPrefs>()));
    gh.lazySingleton<_i409.LessonProgressProvider>(
        () => _i409.LessonProgressProvider(gh<_i523.AppPrefs>()));
    gh.lazySingleton<_i551.MistakeProvider>(
        () => _i551.MistakeProvider(gh<_i523.AppPrefs>()));
    gh.lazySingleton<_i166.ScoreProvider>(
        () => _i166.ScoreProvider(gh<_i523.AppPrefs>()));
    gh.lazySingleton<_i927.StreakProvider>(
        () => _i927.StreakProvider(gh<_i523.AppPrefs>()));
    gh.lazySingleton<_i151.ThemeProvider>(
        () => _i151.ThemeProvider(gh<_i523.AppPrefs>()));
    gh.lazySingleton<_i889.StudyLogRepository>(
        () => _i889.StudyLogRepository(gh<_i523.AppPrefs>()));
    gh.lazySingleton<_i42.CosmeticProvider>(() => _i42.CosmeticProvider(
          gh<_i523.AppPrefs>(),
          gh<_i417.GemsProvider>(),
        ));
    gh.lazySingleton<_i151.AnkiImportDao>(
        () => _i151.AnkiImportDao(gh<_i604.CourseDatabase>()));
    gh.lazySingleton<_i696.AnkiNoteDao>(
        () => _i696.AnkiNoteDao(gh<_i604.CourseDatabase>()));
    gh.lazySingleton<_i68.ReviewHistoryDao>(
        () => _i68.ReviewHistoryDao(gh<_i604.CourseDatabase>()));
    gh.lazySingleton<_i336.SrsStateDao>(
        () => _i336.SrsStateDao(gh<_i604.CourseDatabase>()));
    gh.lazySingleton<_i977.AccessibilityProvider>(
        () => _i977.AccessibilityProvider(gh<_i523.AppPrefs>()));
    gh.lazySingleton<_i1051.CourseProvider>(
        () => _i1051.CourseProvider(gh<_i523.AppPrefs>()));
    gh.lazySingleton<_i793.SettingsProvider>(
        () => _i793.SettingsProvider(gh<_i523.AppPrefs>()));
    gh.lazySingleton<_i859.AiCourseProvider>(() => _i859.AiCourseProvider(
          engine: gh<_i717.AiEngine>(),
          groundedProvider: gh<_i1068.AiGroundedResourceProvider>(),
        ));
    gh.lazySingleton<_i872.AiLessonHelperProvider>(
        () => _i872.AiLessonHelperProvider(
              engine: gh<_i717.AiEngine>(),
              groundedProvider: gh<_i1068.AiGroundedResourceProvider>(),
            ));
    gh.lazySingleton<_i561.AiWishProvider>(() => _i561.AiWishProvider(
          engine: gh<_i717.AiEngine>(),
          groundedProvider: gh<_i1068.AiGroundedResourceProvider>(),
        ));
    gh.lazySingleton<_i717.AiEngine>(() => _i717.AiEngine(
          gh<_i518.AiHttpClient>(),
          gh<_i423.AiCache>(),
        ));
    gh.lazySingleton<_i1068.AiGroundedResourceProvider>(() =>
        _i1068.AiGroundedResourceProvider(
            repository: gh<_i876.ICourseRepository>()));
    gh.lazySingleton<_i876.ICourseRepository>(
        () => _i848.CourseRepository(gh<_i604.CourseDatabase>()));
    gh.lazySingleton<_i1008.GrammarReviewProvider>(
        () => _i1008.GrammarReviewProvider(
              gh<_i523.AppPrefs>(),
              gh<_i854.LessonLinkStore>(),
              gh<_i336.SrsStateDao>(),
            ));
    gh.lazySingleton<_i361.SrsProvider>(() => _i361.SrsProvider(
          gh<_i523.AppPrefs>(),
          gh<_i854.LessonLinkStore>(),
          gh<_i336.SrsStateDao>(),
        ));
    gh.lazySingleton<_i620.StudyStatsProvider>(() => _i620.StudyStatsProvider(
          gh<_i889.StudyLogRepository>(),
          gh<_i551.MistakeProvider>(),
        ));
    gh.lazySingleton<_i706.ReviewProgressProvider>(
        () => _i706.ReviewProgressProvider(
              gh<_i68.ReviewHistoryDao>(),
              gh<_i361.SrsProvider>(),
              gh<_i1008.GrammarReviewProvider>(),
              gh<_i151.AnkiImportDao>(),
            ));
    gh.lazySingleton<_i565.GameProvider>(() => _i565.GameProvider(
          gh<_i523.AppPrefs>(),
          gh<_i166.ScoreProvider>(),
          gh<_i927.StreakProvider>(),
          gh<_i409.LessonProgressProvider>(),
          gh<_i788.GameMilestoneProvider>(),
        ));
    gh.lazySingleton<_i579.CourseReadyGuard>(
        () => _i579.CourseReadyGuard(gh<_i1051.CourseProvider>()));
    gh.lazySingleton<_i1045.AnkiDeckManager>(() => _i1045.AnkiDeckManager(
          repo: gh<_i876.ICourseRepository>(),
          srsProvider: gh<_i361.SrsProvider>(),
          importDao: gh<_i151.AnkiImportDao>(),
          noteDao: gh<_i696.AnkiNoteDao>(),
          appPrefs: gh<_i523.AppPrefs>(),
          audioResolver: gh<_i180.AnkiAudioResolver>(),
        ));
    gh.lazySingleton<_i495.LessonCompletionCoordinator>(
        () => _i495.LessonCompletionCoordinator(
              gh<_i565.GameProvider>(),
              gh<_i417.GemsProvider>(),
              gh<_i143.AchievementsProvider>(),
              gh<_i620.StudyStatsProvider>(),
            ));
    gh.lazySingleton<_i106.AudioController>(() => _i106.AudioController(
          gh<_i50.FlutterTts>(),
          gh<_i233.LanguageProvider>(),
          gh<_i793.SettingsProvider>(),
          gh<_i977.AccessibilityProvider>(),
          gh<_i188.VocabAudioResolver>(),
          audioPlayer: gh<_i656.AudioPlayer>(instanceName: 'audioPlayer'),
          speechPlayer: gh<_i656.AudioPlayer>(instanceName: 'speechPlayer'),
          ttsChecker: gh<_i307.TtsAvailabilityChecker>(),
          ankiMediaResolver: gh<_i180.AnkiAudioResolver>(),
        ));
    gh.factory<_i440.ShowWordRenderer>(
        () => _i440.ShowWordRenderer(gh<_i106.AudioController>()));
    gh.lazySingleton<_i257.MemoryCurveProvider>(() => _i257.MemoryCurveProvider(
          gh<_i68.ReviewHistoryDao>(),
          gh<_i361.SrsProvider>(),
          gh<_i1008.GrammarReviewProvider>(),
        ));
    gh.lazySingleton<_i141.FunLabSnapshotService>(
        () => _i141.FunLabSnapshotService(
              gh<_i523.AppPrefs>(),
              gh<_i604.CourseDatabase>(),
              gh<_i336.SrsStateDao>(),
              gh<_i361.SrsProvider>(),
              gh<_i1008.GrammarReviewProvider>(),
              gh<_i409.LessonProgressProvider>(),
              gh<_i551.MistakeProvider>(),
              gh<_i854.LessonLinkStore>(),
              gh<_i889.StudyLogRepository>(),
              gh<_i620.StudyStatsProvider>(),
              gh<_i417.GemsProvider>(),
              gh<_i565.GameProvider>(),
            ));
    gh.lazySingleton<_i274.LessonViewModel>(() => _i274.LessonViewModel(
          gh<_i1051.CourseProvider>(),
          gh<_i106.AudioController>(),
          gh<_i361.SrsProvider>(),
          gh<_i551.MistakeProvider>(),
          gh<_i1008.GrammarReviewProvider>(),
          gh<_i495.LessonCompletionCoordinator>(),
        ));
    gh.lazySingleton<_i740.ProgressProvider>(
        () => _i740.ProgressProvider(gh<_i565.GameProvider>()));
    gh.lazySingleton<_i9.MatchProvider>(() => _i9.MatchProvider(
          gh<_i106.AudioController>(),
          gh<_i523.AppPrefs>(),
        ));
    gh.lazySingleton<_i936.AppRouter>(
        () => _i936.AppRouter(gh<_i579.CourseReadyGuard>()));
    gh.lazySingleton<Set<_i931.InteractionRenderer>>(
        () => rendererModule.renderers(
              gh<_i440.ShowWordRenderer>(),
              gh<_i990.MultipleChoiceRenderer>(),
              gh<_i147.MultiSelectRenderer>(),
              gh<_i665.FillBlankRenderer>(),
              gh<_i767.TranslateSentenceRenderer>(),
              gh<_i657.ListenAndPickRenderer>(),
              gh<_i757.TypeTheWordRenderer>(),
              gh<_i785.ListenOnlyRenderer>(),
              gh<_i215.ReorderSentenceRenderer>(),
              gh<_i235.ReadingMcqRenderer>(),
              gh<_i399.ReadingTrueFalseRenderer>(),
              gh<_i532.ReadingShortAnswerRenderer>(),
              gh<_i940.AnkiCardRenderer>(),
              gh<_i681.AnkiHtmlCardRenderer>(),
            ));
    gh.lazySingleton<_i648.FunProvider>(() => _i648.FunProvider(
          gh<_i523.AppPrefs>(),
          gh<_i565.GameProvider>(),
          gh<_i417.GemsProvider>(),
          gh<_i141.FunLabSnapshotService>(),
        ));
    return this;
  }
}

class _$AudioModule extends _i83.AudioModule {}

class _$RendererModule extends _i702.RendererModule {}
