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
import '../application/audio_controller.dart' as _i106;
import '../application/character_provider.dart' as _i229;
import '../application/course_provider.dart' as _i1051;
import '../application/game_milestone_provider.dart' as _i788;
import '../application/game_provider.dart' as _i565;
import '../application/gems_provider.dart' as _i417;
import '../application/grammar_review_provider.dart' as _i1008;
import '../application/language_provider.dart' as _i233;
import '../application/lesson_completion_coordinator.dart' as _i495;
import '../application/lesson_link_store.dart' as _i854;
import '../application/lesson_progress_provider.dart' as _i409;
import '../application/lesson_viewmodel.dart' as _i274;
import '../application/locale_provider.dart' as _i649;
import '../application/match_provider.dart' as _i9;
import '../application/mistake_provider.dart' as _i551;
import '../application/progress_provider.dart' as _i740;
import '../application/score_provider.dart' as _i166;
import '../application/settings_provider.dart' as _i793;
import '../application/srs_provider.dart' as _i361;
import '../application/streak_provider.dart' as _i927;
import '../application/study_stats_provider.dart' as _i620;
import '../application/theme_provider.dart' as _i151;
import '../courses/languages/vocab_audio_resolver.dart' as _i73;
import '../data/anki_import_dao.dart' as _i151;
import '../data/course_database.dart' as _i604;
import '../data/course_repository.dart' as _i848;
import '../data/study_log_repository.dart' as _i889;
import '../domain/audio/vocab_audio_resolver.dart' as _i188;
import '../domain/repositories/i_course_repository.dart' as _i876;
import '../routing/course_ready_guard.dart' as _i579;
import '../routing/routing.dart' as _i936;
import '../service/local_reminder_service.dart' as _i711;
import '../service/locator.dart' as _i523;
import '../service/tts_availability_checker.dart' as _i307;
import '../views/lesson/components/interactions/anki_card_renderer.dart'
    as _i940;
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
    gh.lazySingleton<_i229.CharacterProvider>(() => _i229.CharacterProvider());
    gh.lazySingleton<_i1051.CourseProvider>(() => _i1051.CourseProvider());
    gh.lazySingleton<_i711.LocalReminderService>(
        () => _i711.LocalReminderService());
    gh.lazySingleton<_i188.VocabAudioResolver>(
        () => _i73.VocabAudioResolverImpl());
    gh.lazySingleton<_i656.AudioPlayer>(
      () => audioModule.speechPlayer,
      instanceName: 'speechPlayer',
    );
    gh.lazySingleton<_i656.AudioPlayer>(
      () => audioModule.audioPlayer,
      instanceName: 'audioPlayer',
    );
    gh.lazySingleton<_i307.TtsAvailabilityChecker>(
        () => _i307.TtsAvailabilityChecker(gh<_i50.FlutterTts>()));
    gh.lazySingleton<_i977.AccessibilityProvider>(
        () => _i977.AccessibilityProvider(gh<_i523.AppPrefs>()));
    gh.lazySingleton<_i649.LocaleProvider>(
        () => _i649.LocaleProvider(gh<_i523.AppPrefs>()));
    gh.lazySingleton<_i793.SettingsProvider>(
        () => _i793.SettingsProvider(gh<_i523.AppPrefs>()));
    gh.lazySingleton<_i151.AnkiImportDao>(
        () => _i151.AnkiImportDao(gh<_i604.CourseDatabase>()));
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
    gh.lazySingleton<_i579.CourseReadyGuard>(
        () => _i579.CourseReadyGuard(gh<_i1051.CourseProvider>()));
    gh.lazySingleton<_i106.AudioController>(() => _i106.AudioController(
          gh<_i50.FlutterTts>(),
          gh<_i233.LanguageProvider>(),
          gh<_i793.SettingsProvider>(),
          gh<_i977.AccessibilityProvider>(),
          gh<_i188.VocabAudioResolver>(),
          audioPlayer: gh<_i656.AudioPlayer>(instanceName: 'audioPlayer'),
          speechPlayer: gh<_i656.AudioPlayer>(instanceName: 'speechPlayer'),
          ttsChecker: gh<_i307.TtsAvailabilityChecker>(),
        ));
    gh.lazySingleton<_i876.ICourseRepository>(
        () => _i848.CourseRepository(gh<_i604.CourseDatabase>()));
    gh.lazySingleton<_i620.StudyStatsProvider>(() => _i620.StudyStatsProvider(
          gh<_i889.StudyLogRepository>(),
          gh<_i551.MistakeProvider>(),
        ));
    gh.factory<_i440.ShowWordRenderer>(
        () => _i440.ShowWordRenderer(gh<_i106.AudioController>()));
    gh.lazySingleton<_i1008.GrammarReviewProvider>(
        () => _i1008.GrammarReviewProvider(
              gh<_i523.AppPrefs>(),
              gh<_i854.LessonLinkStore>(),
            ));
    gh.lazySingleton<_i361.SrsProvider>(() => _i361.SrsProvider(
          gh<_i523.AppPrefs>(),
          gh<_i854.LessonLinkStore>(),
        ));
    gh.lazySingleton<_i565.GameProvider>(() => _i565.GameProvider(
          gh<_i523.AppPrefs>(),
          gh<_i166.ScoreProvider>(),
          gh<_i927.StreakProvider>(),
          gh<_i409.LessonProgressProvider>(),
          gh<_i788.GameMilestoneProvider>(),
        ));
    gh.lazySingleton<_i495.LessonCompletionCoordinator>(
        () => _i495.LessonCompletionCoordinator(
              gh<_i565.GameProvider>(),
              gh<_i417.GemsProvider>(),
              gh<_i143.AchievementsProvider>(),
              gh<_i620.StudyStatsProvider>(),
            ));
    gh.lazySingleton<_i9.MatchProvider>(() => _i9.MatchProvider(
          gh<_i106.AudioController>(),
          gh<_i523.AppPrefs>(),
        ));
    gh.lazySingleton<_i936.AppRouter>(
        () => _i936.AppRouter(gh<_i579.CourseReadyGuard>()));
    gh.lazySingleton<_i274.LessonViewModel>(() => _i274.LessonViewModel(
          gh<_i1051.CourseProvider>(),
          gh<_i106.AudioController>(),
          gh<_i361.SrsProvider>(),
          gh<_i551.MistakeProvider>(),
          gh<_i1008.GrammarReviewProvider>(),
          gh<_i495.LessonCompletionCoordinator>(),
        ));
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
            ));
    gh.lazySingleton<_i740.ProgressProvider>(
        () => _i740.ProgressProvider(gh<_i565.GameProvider>()));
    return this;
  }
}

class _$AudioModule extends _i83.AudioModule {}

class _$RendererModule extends _i702.RendererModule {}
