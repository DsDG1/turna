// ignore: unused_import
import 'package:intl/intl.dart' as intl;
import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for English (`en`).
class AppLocalizationsEn extends AppLocalizations {
  AppLocalizationsEn([String locale = 'en']) : super(locale);

  @override
  String get appTitle => 'Varnamala';

  @override
  String get commonCancel => 'Cancel';

  @override
  String get commonBack => 'Back';

  @override
  String get commonClose => 'Close';

  @override
  String get commonDone => 'Done';

  @override
  String get commonRetry => 'Retry';

  @override
  String get commonRefresh => 'Refresh';

  @override
  String get commonSend => 'Send';

  @override
  String get commonApply => 'Apply';

  @override
  String get commonPractice => 'Practice';

  @override
  String get commonContinue => 'Continue';

  @override
  String get commonGotIt => 'Got it';

  @override
  String get commonOk => 'OK';

  @override
  String get commonSave => 'Save';

  @override
  String get commonImport => 'Import';

  @override
  String get commonLater => 'Later';

  @override
  String get commonNavLearn => 'Learn';

  @override
  String get commonNavPlay => 'Play';

  @override
  String get commonNavProfile => 'Profile';

  @override
  String get commonNavSettings => 'Settings';

  @override
  String get lessonCheck => 'CHECK';

  @override
  String get lessonChecked => 'CHECKED';

  @override
  String get lessonContinueUpper => 'CONTINUE';

  @override
  String get lessonGotItUpper => 'GOT IT';

  @override
  String get settingsCategoryAccount => 'Account';

  @override
  String get settingsCategoryLearning => 'Learning';

  @override
  String get settingsCategoryAudioHaptics => 'Audio & Haptics';

  @override
  String get settingsCategoryAccessibility => 'Accessibility';

  @override
  String get settingsCategoryAiTools => 'AI Tools';

  @override
  String get settingsCategoryData => 'Data';

  @override
  String get settingsCategoryAbout => 'About';

  @override
  String get settingsTitle => 'Settings';

  @override
  String get settingsBack => 'Back';

  @override
  String get settingsSoundEffectsTitle => 'Sound effects';

  @override
  String get settingsSoundEffectsSubtitle =>
      'Play sounds for errors and level-ups';

  @override
  String get settingsHapticFeedbackTitle => 'Haptic feedback';

  @override
  String get settingsHapticFeedbackSubtitle => 'Vibrate on key interactions';

  @override
  String get settingsAiApiConfigTitle => 'AI API Configuration';

  @override
  String get settingsAiApiConfigSubtitle =>
      'Base URL, API key & model (not saved on exit)';

  @override
  String get settingsDesignCourseAiTitle => 'Design a course with AI';

  @override
  String get settingsDesignCourseAiSubtitle => 'Open the AI design chat';

  @override
  String get settingsImportTextbookTitle => 'Import from Textbook';

  @override
  String get settingsImportTextbookSubtitle =>
      'Convert a markdown/text file into course sections';

  @override
  String get settingsExportDataTitle => 'Export data';

  @override
  String get settingsExportDataSubtitle =>
      'Save progress and/or course content to a file';

  @override
  String get settingsImportDataTitle => 'Import data';

  @override
  String get settingsImportDataSubtitle =>
      'Restore progress from an exported file';

  @override
  String get settingsClearMistakeLogTitle => 'Clear mistake log';

  @override
  String get settingsClearMistakeLogSubtitle => 'Remove all saved mistakes';

  @override
  String get settingsResetProgressTitle => 'Reset lesson progress';

  @override
  String get settingsResetProgressSubtitle =>
      'Mark all lessons as not completed';

  @override
  String get settingsClearMistakeDialogTitle => 'Clear mistake log?';

  @override
  String get settingsClearMistakeDialogMessage =>
      'This will permanently delete all saved mistakes.';

  @override
  String get settingsClearMistakeConfirm => 'Clear';

  @override
  String get settingsMistakeLogCleared => 'Mistake log cleared';

  @override
  String get settingsResetProgressDialogTitle => 'Reset lesson progress?';

  @override
  String get settingsResetProgressDialogMessage =>
      'All lesson completion and perfect-lesson records will be cleared. This cannot be undone.';

  @override
  String get settingsResetProgressConfirm => 'Reset';

  @override
  String get settingsProgressReset => 'Lesson progress reset';

  @override
  String get settingsImportDataDialogTitle => 'Import data?';

  @override
  String get settingsImportDataDialogMessage =>
      'This will overwrite your current progress with the file\'s contents. This cannot be undone. Consider exporting first.';

  @override
  String get settingsImportDataConfirm => 'Import';

  @override
  String get settingsCourseSavedRestart =>
      'Course content saved; restart to apply';

  @override
  String get settingsProgressRestoredRestart =>
      'Progress restored — restart the app to apply';

  @override
  String get settingsNothingToImport => 'Nothing to import';

  @override
  String settingsImportFailed(Object error) {
    return 'Import failed: $error';
  }

  @override
  String settingsExportFailed(Object error) {
    return 'Export failed: $error';
  }

  @override
  String get settingsAiApiConfigSheetTitle => 'AI API Configuration';

  @override
  String get settingsAiApiConfigNotSaved =>
      'Not saved on exit — kept in memory only.';

  @override
  String get settingsBaseUrlLabel => 'Base URL';

  @override
  String get settingsBaseUrlHint => 'https://api.deepseek.com';

  @override
  String get settingsApiKeyLabel => 'API Key';

  @override
  String get settingsApiKeyHint => 'sk-...';

  @override
  String get settingsModelLabel => 'Model';

  @override
  String get settingsModelHint => 'deepseek-v4-pro';

  @override
  String get settingsSaveConfig => 'Save configuration';

  @override
  String get settingsExportSheetTitle => 'Export data';

  @override
  String get settingsExportSubtitle =>
      'Choose what to include in the export file.';

  @override
  String get settingsExportProgressTitle => 'Progress data';

  @override
  String get settingsExportProgressSubtitle =>
      'SRS, score, streak, mistakes, achievements';

  @override
  String get settingsExportCourseTitle => 'Course content';

  @override
  String get settingsExportCourseSubtitle =>
      'The bundled Turkish course JSON files';

  @override
  String get settingsExportButton => 'Export';

  @override
  String get settingsExporting => 'Exporting...';

  @override
  String get settingsAboutVarnamala => 'About Varnamala';

  @override
  String get settingsOpenSourceLicenses => 'Open source licenses';

  @override
  String settingsVersionFooter(String version) {
    return 'Version $version';
  }

  @override
  String settingsVersionFooterWithBuild(String version, String build) {
    return 'Version $version ($build)';
  }

  @override
  String get settingsAccountLearnerFallback => 'Learner';

  @override
  String get settingsThemeLight => 'Light';

  @override
  String get settingsThemeDark => 'Dark';

  @override
  String get settingsThemeSystem => 'System';

  @override
  String get settingsLearningLanguageTitle => 'Learning Language';

  @override
  String get settingsLearningLanguageSubtitle =>
      'Choose the language you are learning';

  @override
  String get settingsTtsSpeedTitle => 'TTS Speed';

  @override
  String get settingsTtsSpeedSubtitle => 'Adjust voice playback speed';

  @override
  String settingsTtsSpeedValue(String ttsSpeed) {
    return '${ttsSpeed}x';
  }

  @override
  String get settingsDailyReminderTitle => 'Daily reminder';

  @override
  String get settingsDailyReminderSubtitle =>
      'Gentle nudge to review — no streaks or penalties';

  @override
  String get settingsReminderTimeTitle => 'Reminder time';

  @override
  String settingsReminderTimeSubtitle(String timeLabel) {
    return 'Currently $timeLabel';
  }

  @override
  String get settingsTtsChecking => 'Checking device TTS engines…';

  @override
  String settingsTtsReady(String locale) {
    return 'Google TTS ready ($locale) — recommended for learning';
  }

  @override
  String get settingsTtsGoogleInstalledMissingVoice =>
      'Google installed — download Turkish voice data in system TTS settings';

  @override
  String get settingsTtsTurkishVoiceMissing =>
      'Turkish voice not ready — open system TTS settings';

  @override
  String settingsTtsGoogleMissing(Object oem) {
    return 'Google TTS not detected (engines: $oem)';
  }

  @override
  String get settingsVoiceSourceTitle => 'Voice source';

  @override
  String get settingsSystemTts => 'System TTS';

  @override
  String get settingsVoiceSourceDialogTitle => 'Voice source';

  @override
  String get settingsPlaySample => 'Play sample (Merhaba)…';

  @override
  String get settingsOpenSystemTts => 'Open system TTS settings…';

  @override
  String get settingsInstallGoogleTts => 'Install / open Google TTS…';

  @override
  String settingsTtsNoVoicePlayed(Object error) {
    return 'No voice played. $error';
  }

  @override
  String get settingsTtsNoVoicePlayedFallback =>
      'No voice played. Check logcat for TTS errors.';

  @override
  String settingsTtsPlaying(String userLabel) {
    return 'Playing: $userLabel';
  }

  @override
  String get settingsTextSizeTitle => 'Text size';

  @override
  String get settingsTextSizeSubtitle => 'Magnify text app-wide';

  @override
  String settingsTextSizeValue(int textScale) {
    return '$textScale%';
  }

  @override
  String get settingsReduceMotionTitle => 'Reduce motion';

  @override
  String get settingsReduceMotionSubtitle =>
      'Shorten or disable animations and transitions';

  @override
  String get settingsHighContrastTitle => 'High contrast';

  @override
  String get settingsHighContrastSubtitle => 'Use a high-contrast color theme';

  @override
  String get settingsDyslexiaFontTitle => 'Dyslexia-friendly font';

  @override
  String get settingsDyslexiaFontSubtitle =>
      'Switch to the Lexend typeface for easier reading';

  @override
  String get settingsSensoryReduceTitle => 'Reduce sensory input';

  @override
  String get settingsSensoryReduceSubtitle =>
      'Mute non-essential sounds and haptics';

  @override
  String get settingsFocusModeTitle => 'Focus mode';

  @override
  String get settingsFocusModeSubtitle =>
      'Hide the rotating welcome animation on the home screen';

  @override
  String get aboutTitle => 'About Varnamala';

  @override
  String get aboutWhatIsTitle => 'What is Varnamala';

  @override
  String get aboutWhatIsBody =>
      'Varnamala is a free, open-source language learning app focused on helping you build real vocabulary and grammar skills — one small step at a time. It keeps learning offline, distraction-free, and under your control.';

  @override
  String get aboutHighlightsTitle => 'Highlights';

  @override
  String get aboutHighlightOfflineTitle => 'Offline first';

  @override
  String get aboutHighlightOfflineSubtitle => 'Learn anywhere';

  @override
  String get aboutHighlightSrsTitle => 'SRS review';

  @override
  String get aboutHighlightSrsSubtitle => 'Remember more';

  @override
  String get aboutHighlightInteractionsTitle => '11 interactions';

  @override
  String get aboutHighlightInteractionsSubtitle => 'Practice all skills';

  @override
  String get aboutPrivacyTitle => 'Privacy & local-first';

  @override
  String get aboutPrivacyBody =>
      'Everything you learn stays on this device. Varnamala has no cloud backend, no account, and no tracking — your progress, mistakes, and settings never leave your phone. Uninstalling the app removes all of it. The only network access is optional (opening external links or the AI tools you configure yourself).';

  @override
  String get aboutVersionTitle => 'Version & changelog';

  @override
  String get aboutLinksTitle => 'Links';

  @override
  String get aboutUpstreamTitle => 'Upstream project';

  @override
  String get aboutUpstreamSubtitle => 'github.com/rshrc/Varnamala';

  @override
  String get aboutReportIssueTitle => 'Report an issue';

  @override
  String get aboutReportIssueSubtitle => 'GitHub Issues';

  @override
  String get aboutViewReleasesTitle => 'View releases';

  @override
  String get aboutViewReleasesSubtitle => 'Changelog & downloads';

  @override
  String get aboutShareTitle => 'Share Varnamala';

  @override
  String get aboutCreditsTitle => 'Credits';

  @override
  String get aboutCreditsOriginal =>
      'Original framework by Rishi Banerjee and the Varnamala open-source community.';

  @override
  String get aboutCreditsFork =>
      'This build is a local-first fork with additional accessibility settings and a focused course-authoring tool.';

  @override
  String get aboutLicense =>
      'Licensed under the GNU General Public License v3.0.';

  @override
  String aboutCopyright(String year) {
    return '© $year Varnamala';
  }

  @override
  String get aboutBrandName => 'Varnamala';

  @override
  String get aboutTagline => 'Learn languages, one step at a time.';

  @override
  String aboutVersionLabel(String version) {
    return 'Version $version';
  }

  @override
  String aboutVersionWithBuild(String version, String buildNumber) {
    return 'Version $version ($buildNumber)';
  }

  @override
  String get aboutShareText =>
      'Check out Varnamala — a free, open-source language learning app! https://github.com/rshrc/Varnamala';

  @override
  String aboutVersionShort(String version) {
    return 'Version $version';
  }

  @override
  String aboutVersionBuild(String buildNumber) {
    return '($buildNumber)';
  }

  @override
  String get aboutHideChangelog => 'Hide';

  @override
  String get aboutShowChangelog => 'Show changelog';

  @override
  String get aboutReleasesNote =>
      'For the full release history, see the GitHub releases page.';

  @override
  String get aboutMilestone1Title => 'future4 framework';

  @override
  String get aboutMilestone1Body =>
      'Completed clean-architecture framework: DI consolidation, audio/content decoupling, SRS queue base class, GameProvider facade, integration tests, release pipeline.';

  @override
  String get aboutMilestone2Title => 'Swahili → Turkish pivot';

  @override
  String get aboutMilestone2Body =>
      'Migrated the target language to Turkish and filled Section 1 with a real greetings lesson (8 words + 2 expressions).';

  @override
  String get aboutMilestone3Title => 'Accessibility settings';

  @override
  String get aboutMilestone3Body =>
      'Added neurodiversity-friendly options: text size, reduced motion, high contrast, dyslexia-friendly font, sensory reduction, and focus mode.';

  @override
  String get homeAiCourseDesigner => 'AI Course Designer';

  @override
  String get homeNewCourse => 'New Course';

  @override
  String get homeNewCourseSheetTitle => 'New Course';

  @override
  String get homeDesignWithAi => 'Design with AI';

  @override
  String get homeDesignWithAiSubtitle =>
      'Describe a course and let AI build it';

  @override
  String get homeImportFromTextbook => 'Import from Textbook';

  @override
  String get homeImportFromTextbookSubtitle =>
      'Convert a markdown/text file into sections';

  @override
  String get homeFromAnki => 'From Anki';

  @override
  String get homeFromAnkiSubtitle => 'Import an .apkg/.colpkg deck as a course';

  @override
  String get homeStreakBroken => 'Your streak was broken. Start again today.';

  @override
  String ankiImportSuccess(int count) {
    return 'Successfully imported $count words!';
  }

  @override
  String get ankiImportError => 'Import failed. Please check the file format.';

  @override
  String get homeNewCourseComingSoon =>
      'Multi-language course support is coming soon. Currently only Turkish is available.';

  @override
  String get homeNewCourseUseAi =>
      'You can also use the AI Course Designer to create custom courses.';

  @override
  String get dialogClose => 'Close';

  @override
  String get playQuickPlayTitle => 'Quick Play';

  @override
  String get playQuickPlaySubtitle => 'Match words as fast as you can';

  @override
  String get playMistakeReviewTitle => 'Mistake Review';

  @override
  String playMistakeReviewSubtitleWithCount(int mistakesCount) {
    return '$mistakesCount mistakes — practice up to 10';
  }

  @override
  String get playMistakeReviewSubtitleEmpty => 'No mistakes recorded';

  @override
  String get playReviewTitle => 'Review';

  @override
  String playReviewSubtitleWithDue(int srsDue) {
    return '$srsDue words due for review';
  }

  @override
  String get playReviewSubtitleEmpty => 'No words due right now';

  @override
  String get playGrammarReviewTitle => 'Grammar Review';

  @override
  String playGrammarReviewSubtitleWithDue(int grammarDue) {
    return '$grammarDue grammar points due for review';
  }

  @override
  String get playGrammarReviewSubtitleEmpty => 'No grammar due right now';

  @override
  String get playDailyChallengeTitle => 'Daily Challenge';

  @override
  String get playDailyChallengeSubtitle =>
      'Random 15 questions — test your Turkish';

  @override
  String get playWeakWordsTitle => 'Weak Words';

  @override
  String playWeakWordsSubtitleWithCount(int weakCount) {
    return '$weakCount words missed twice in 30 days';
  }

  @override
  String get playWeakWordsSubtitleEmpty => 'No weak words right now';

  @override
  String get playAnkiReviewTitle => 'Anki Review';

  @override
  String get playAnkiReviewSubtitle => 'Review imported Anki decks';

  @override
  String get playDictionaryTitle => 'Dictionary';

  @override
  String get playDictionarySubtitle => 'Search words, phrases, and grammar';

  @override
  String get playYourBestTitle => 'Your Best';

  @override
  String get playTotalXp => 'Total XP';

  @override
  String get playTitle => 'Play';

  @override
  String get playMatchMadness => 'Match Madness';

  @override
  String playXpLabel(int sessionScore) {
    return '$sessionScore XP';
  }

  @override
  String playRoundLabel(int roundsCompleted) {
    return 'Round $roundsCompleted';
  }

  @override
  String get playInfiniteRoundsNote =>
      'Infinite rounds. New words appear after each perfect board.';

  @override
  String get playRoundComplete => 'Round complete! Loading new words...';

  @override
  String playTimeUp(int roundsCompleted, int score) {
    return 'Time up! You completed $roundsCompleted rounds and earned $score XP.';
  }

  @override
  String get playPlayAgain => 'Play Again';

  @override
  String get playBrilliantRun => 'Brilliant Run!';

  @override
  String get playChampionEnergy => 'Champion Energy!';

  @override
  String get playLightningFast => 'Lightning Fast!';

  @override
  String playMatchCount(int matchedCount, int totalCount) {
    return '$matchedCount / $totalCount';
  }

  @override
  String get playDailyClose => 'Close';

  @override
  String get playDailyTitle => 'Daily Challenge';

  @override
  String playDailyQuestion(int current, int total) {
    return 'Question $current of $total';
  }

  @override
  String get playDailyChallengeFallback => 'Daily Challenge';

  @override
  String get playDailyContinue => 'CONTINUE';

  @override
  String get playDailyGotIt => 'GOT IT';

  @override
  String get playDailyNoQuestions => 'No challenge questions available yet';

  @override
  String get playDailyCompleteFewLessons =>
      'Complete a few lessons first to build up the question pool.';

  @override
  String get playWeakWordsEmpty =>
      'Keep practicing — no weak words yet.\nWords you miss twice in 30 days will show up here.';

  @override
  String get playWeakWordsTitleAppBar => 'Weak Words';

  @override
  String get reviewContinueUpper => 'CONTINUE';

  @override
  String get reviewGotItUpper => 'GOT IT';

  @override
  String get reviewWeakWordsTitleAppBar => 'Weak Words';

  @override
  String get reviewDoYouKnow => 'Do you know this word?';

  @override
  String get reviewDontKnow => 'Don\'t know';

  @override
  String get reviewKnowIt => 'Know it';

  @override
  String get reviewEmptyTitle => 'Review';

  @override
  String get reviewEmptyMessage => 'You\'ve reviewed everything for now.';

  @override
  String get reviewDueMessage => 'words are already due — pull to refresh';

  @override
  String get reviewNoItemsDue => 'No items due for review';

  @override
  String reviewDueCountMessage(int dueCount, String dueMessage) {
    return '$dueCount $dueMessage';
  }

  @override
  String get reviewCompletionTitle => 'Session Complete!';

  @override
  String get reviewCompletionMessage => 'You reviewed everything.';

  @override
  String get reviewReviewAppBarTitle => 'Review';

  @override
  String reviewXpEarned(int xpEarned) {
    return '+$xpEarned XP';
  }

  @override
  String reviewGemsEarned(int gemsEarned) {
    return '+$gemsEarned Gems';
  }

  @override
  String get reviewReviewMore => 'Review More';

  @override
  String get reviewSrsTitle => 'Review';

  @override
  String get reviewSrsSessionComplete => 'Session Complete!';

  @override
  String reviewSrsCompletionMessage(int sessionCount) {
    return 'You reviewed $sessionCount items.';
  }

  @override
  String get reviewSrsAppBarTitle => 'Review';

  @override
  String reviewSrsTtsSpeed(String ttsSpeed) {
    return '$ttsSpeed x';
  }

  @override
  String get reviewSrsTtsSpeedTooltip => 'TTS speed';

  @override
  String reviewSrsProgress(int currentIndex, int queueLength) {
    return '$currentIndex / $queueLength';
  }

  @override
  String get reviewSrsShowAnswer => 'Show Answer';

  @override
  String get reviewSrsPlayPronunciation => 'Play pronunciation';

  @override
  String get reviewSrsTapToReveal => 'Tap to reveal meaning';

  @override
  String reviewSrsLearnedIn(String lessonName) {
    return 'Learned in: $lessonName';
  }

  @override
  String reviewSrsFirstSeen(String wordId) {
    return 'First seen: $wordId';
  }

  @override
  String get reviewSrsEntryNotFound => 'Entry not found';

  @override
  String reviewSrsPronunciation(String pronunciation) {
    return '/$pronunciation/';
  }

  @override
  String get reviewMistakeReviewTitle => 'Mistake Review';

  @override
  String get reviewViewMistakeList => 'View mistake list';

  @override
  String get reviewNoMistakes =>
      'No mistakes to review.\nMistakes are recorded here automatically; practice up to 10 at a time.';

  @override
  String get reviewMyMistakesTitle => 'My Mistakes';

  @override
  String get reviewNoMistakesRecorded => 'No mistakes recorded';

  @override
  String get reviewKeepItUp => 'Keep it up!';

  @override
  String get reviewMistakesLabel => 'Mistakes';

  @override
  String get reviewWordsLabel => 'Words';

  @override
  String get reviewGrammarLabel => 'Grammar';

  @override
  String get reviewUnknownQuestion => 'Unknown question';

  @override
  String get reviewReviewGrammar => 'Review grammar';

  @override
  String get reviewGotItNow => 'I got it now';

  @override
  String get reviewYourAnswer => 'Your answer';

  @override
  String get reviewCorrectAnswer => 'Correct answer';

  @override
  String get reviewDash => '—';

  @override
  String reviewGrammarChip(String title) {
    return 'Grammar: $title';
  }

  @override
  String get reviewPracticeTitle => 'Practice';

  @override
  String get reviewCannotPractice => 'This mistake cannot be practiced.';

  @override
  String get reviewPracticeMistakeTitle => 'Practice Mistake';

  @override
  String get reviewGrammarReviewTitle => 'Grammar Review';

  @override
  String get reviewGrammarEmptyMessage =>
      'You\'ve reviewed everything for now.';

  @override
  String get reviewGrammarDueMessage =>
      'points are already due — refresh to load them';

  @override
  String get reviewGrammarSessionComplete => 'Session Complete!';

  @override
  String reviewGrammarCompletionMessage(int sessionCount) {
    return 'You reviewed $sessionCount grammar points.';
  }

  @override
  String get reviewGrammarAppBarTitle => 'Grammar Review';

  @override
  String reviewGrammarProgress(int currentIndex, int queueLength) {
    return '$currentIndex / $queueLength';
  }

  @override
  String reviewGrammarPracticeLabel(int practiceIndex, int practiceLength) {
    return 'Practice $practiceIndex / $practiceLength';
  }

  @override
  String get reviewGrammarDoYouUnderstand =>
      'Do you understand this grammar point?';

  @override
  String get reviewGrammarNextPractice => 'Next practice';

  @override
  String get reviewGrammarRateGrammar => 'Rate this grammar point';

  @override
  String get reviewGrammarShowExplanation => 'Show Explanation';

  @override
  String reviewGrammarLearnedIn(String lessonName) {
    return 'Learned in: $lessonName';
  }

  @override
  String reviewGrammarFirstSeen(String wordId) {
    return 'First seen: $wordId';
  }

  @override
  String get reviewGrammarTapToReveal => 'Tap to reveal explanation';

  @override
  String get reviewGrammarPointNotFound => 'Grammar point not found';

  @override
  String get lessonFlipCardCaption => 'FLIP CARD';

  @override
  String get lessonShowAnswer => 'Show Answer';

  @override
  String get lessonTapToReveal => 'Tap below to reveal the answer';

  @override
  String get lessonHowWellDidYouKnow => 'How well did you know this?';

  @override
  String get lessonAgain => 'Again';

  @override
  String get lessonHard => 'Hard';

  @override
  String get lessonGood => 'Good';

  @override
  String get lessonEasy => 'Easy';

  @override
  String get lessonPlayAudioLabel => 'Play audio';

  @override
  String get lessonFillBlankCaption => 'Fill in the blank';

  @override
  String get lessonFillBlankHint => '___';

  @override
  String get lessonCorrectAnswer => 'Correct answer';

  @override
  String get lessonListenAndPickCaption => 'Listen and pick';

  @override
  String get lessonSummaryCaption => 'Summary';

  @override
  String get lessonListenToSummary => 'Listen to the summary';

  @override
  String get lessonTapToReplay => 'Tap the speaker to replay';

  @override
  String get lessonTapToListen => 'Tap the speaker to listen';

  @override
  String get lessonMultipleChoiceCaption => 'Multiple choice';

  @override
  String get lessonSelectAllCaption => 'Select all that apply';

  @override
  String lessonSelectAtLeast(int min, int count) {
    return 'Select at least $min ($count selected)';
  }

  @override
  String lessonSelectExact(int min, int count) {
    return 'Select $min ($count selected)';
  }

  @override
  String lessonSelectRange(int min, int max, int count) {
    return 'Select $min–$max ($count selected)';
  }

  @override
  String get lessonReadingComprehensionCaption => 'Reading comprehension';

  @override
  String get lessonShortAnswerCaption => 'Short answer';

  @override
  String get lessonTypeYourAnswer => 'Type your answer...';

  @override
  String get lessonTrueFalseCaption => 'True or False';

  @override
  String get lessonTrue => 'True';

  @override
  String get lessonFalse => 'False';

  @override
  String get lessonArrangeWordsCaption => 'Arrange the words';

  @override
  String get lessonTapRightOrder => 'Tap the words in the right order';

  @override
  String get lessonWordBank => 'Word bank';

  @override
  String get lessonCorrectOrder => 'Correct order';

  @override
  String get lessonTapWordToStart => 'Tap a word below to start';

  @override
  String lessonSpeakTerm(String term) {
    return 'Speak $term';
  }

  @override
  String get lessonSpeakContextSentence => 'Speak context sentence';

  @override
  String get lessonTapToContinue => 'Tap to continue';

  @override
  String get lessonItemNotLoaded => 'This item could not be loaded.';

  @override
  String get lessonTranslateCaption => 'Translate this sentence';

  @override
  String get lessonTypeTranslation => 'Type the translation...';

  @override
  String get lessonCorrectTranslation => 'Correct translation';

  @override
  String get lessonTypeWhatYouHearCaption => 'Type what you hear';

  @override
  String get lessonTypeHere => 'Type here...';

  @override
  String get lessonCompleteTitle1 => 'Lesson Complete!';

  @override
  String get lessonCompleteSubtitle1 =>
      'Brilliant focus. You cleared this lesson.';

  @override
  String get lessonCompleteTitle2 => 'That Was Fast!';

  @override
  String get lessonCompleteSubtitle2 =>
      'You are climbing fast. Keep the streak alive.';

  @override
  String get lessonCompleteTitle3 => 'Excellent Work!';

  @override
  String get lessonCompleteSubtitle3 =>
      'Every lesson gets you closer to mastery.';

  @override
  String get lessonPerfectLesson => 'Perfect lesson! All answers correct.';

  @override
  String get lessonCorrect => 'Correct';

  @override
  String get lessonWrong => 'Wrong';

  @override
  String get lessonTime => 'Time';

  @override
  String get lessonXp => 'XP';

  @override
  String get lessonAnswerBreakdown => 'Answer breakdown';

  @override
  String lessonResultsCount(int correctCount, int totalCount) {
    return '$correctCount / $totalCount';
  }

  @override
  String get lessonBackToCourses => 'Back to Courses';

  @override
  String get lessonAccuracy => 'accuracy';

  @override
  String lessonPercentValue(int percent) {
    return '$percent%';
  }

  @override
  String lessonQuestionResult(int index, String prompt) {
    return '$index. $prompt';
  }

  @override
  String lessonQuestionAnswer(String correctAnswer) {
    return 'Answer: $correctAnswer';
  }

  @override
  String get lessonNotYet => 'Not Yet';

  @override
  String lessonMasteryMessage(int correct, int total, int accuracyPercent) {
    return 'You got $correct / $total ($accuracyPercent%). You need 80% to pass. Try again!';
  }

  @override
  String get lessonTryAgain => 'Try Again';

  @override
  String lessonDurationSeconds(int seconds) {
    return '${seconds}s';
  }

  @override
  String lessonDurationMinutes(int minutes, int seconds) {
    return '${minutes}m ${seconds}s';
  }

  @override
  String get lessonAiHelperTooltip => 'AI lesson helper';

  @override
  String get lessonAiHintTooltip => 'AI hint';

  @override
  String get lessonNoContent => 'No content';

  @override
  String get lessonLessonFallback => 'Lesson';

  @override
  String get lessonCouldNotLoadLesson => 'Could not load lesson';

  @override
  String get aiNotConfiguredTitle => 'AI not configured';

  @override
  String get aiNotConfiguredMessageLesson =>
      'Please fill in Base URL / API Key / Model under Settings → Learning → AI API Configuration before using AI hints.';

  @override
  String get aiGoToSettings => 'Go to settings';

  @override
  String get aiCourseDesignerTitle => 'AI Course Designer';

  @override
  String get aiCourseParametersTooltip => 'Course parameters';

  @override
  String get aiCourseParametersTitle => 'Course Parameters';

  @override
  String get aiTargetLanguageLabel => 'Target language';

  @override
  String get aiSourceLanguageLabel => 'Source language';

  @override
  String get aiTopicLabel => 'Topic';

  @override
  String get aiLevelLabel => 'Level';

  @override
  String get aiUnitsLabel => 'Units';

  @override
  String get aiLessonsPerUnitLabel => 'Lessons/unit';

  @override
  String get aiTemplateLabel => 'Template';

  @override
  String get aiGenreBatchTitle => 'Genre batch';

  @override
  String get aiGenreBatchSubtitle =>
      'Use [genre] tags for multi-template batch generation';

  @override
  String get aiGroundedGenerationTitle => 'Grounded generation';

  @override
  String get aiGroundedGenerationSubtitle =>
      'Reuse existing vocabulary, expressions, and grammar points';

  @override
  String get aiExtraInstructionsLabel => 'Extra instructions (optional)';

  @override
  String get aiEmptyHintWish =>
      'Tell the AI what course you want. For example:\n\"I want to teach Turkish travel phrases — greetings and ordering food.\"';

  @override
  String aiErrorBubble(Object error) {
    return 'Error: $error';
  }

  @override
  String get aiCourseGenerated => 'Course generated';

  @override
  String aiAiExplanation(String explanation) {
    return 'AI explanation: $explanation';
  }

  @override
  String get aiSaveToCourseTree => 'Save to Course Tree';

  @override
  String get aiTypeIdea => 'Type your idea…';

  @override
  String get aiSwipeToFinalize => 'Swipe to finalize';

  @override
  String get aiReleaseToFinalize => 'Release to finalize';

  @override
  String get aiCourseSaved => 'Course saved to database.';

  @override
  String aiSaveFailed(Object error) {
    return 'Save failed: $error';
  }

  @override
  String get aiTextbookImportTitle => 'Import from Textbook';

  @override
  String get aiTextbookNotConfiguredMessage =>
      'Please fill in Base URL / API Key / Model under Settings → AI API Configuration first.';

  @override
  String get aiTextbookTargetLanguageLabel => 'Target language';

  @override
  String get aiTextbookSourceLanguageLabel => 'Source language';

  @override
  String get aiTextbookLevelLabel => 'Level';

  @override
  String get aiTextbookImportStrategyLabel => 'Import strategy';

  @override
  String get aiTextbookPickPrompt =>
      'Pick a markdown or text file to import as course sections.';

  @override
  String get aiTextbookPickFile => 'Pick file';

  @override
  String aiTextbookSelected(String fileName) {
    return 'Selected: $fileName';
  }

  @override
  String get aiTextbookParsing => 'Parsing file…';

  @override
  String get aiTextbookExtracting => 'Extracting knowledge…';

  @override
  String get aiTextbookReviewChapters => 'Review chapters';

  @override
  String aiTextbookChapterChars(int length) {
    return '$length chars';
  }

  @override
  String get aiTextbookReviewKnowledge => 'Review extracted knowledge';

  @override
  String aiTextbookWords(int count) {
    return 'Words: $count';
  }

  @override
  String aiTextbookExpressions(int count) {
    return 'Expressions: $count';
  }

  @override
  String aiTextbookGrammar(int count) {
    return 'Grammar: $count';
  }

  @override
  String get aiTextbookImportComplete => 'Import complete!';

  @override
  String aiTextbookErrorFooter(Object error) {
    return 'Error: $error';
  }

  @override
  String get aiTextbookExtractKnowledge => 'Extract knowledge';

  @override
  String get aiTextbookImportSections => 'Import sections';

  @override
  String get aiLessonHelperTitle => 'AI Lesson Helper';

  @override
  String get aiLessonHelperHint =>
      'e.g. \"Make this easier\" or \"Add 3 more exercises\"';

  @override
  String get aiLessonHelperInstructionLabel => 'Instruction';

  @override
  String get aiLessonHelperChipMakeEasier => 'Make easier';

  @override
  String get aiLessonHelperChipMakeHarder => 'Make harder';

  @override
  String get aiLessonHelperChipAddExercises => 'Add 3 exercises';

  @override
  String get aiLessonHelperChipListening => 'Change to listening';

  @override
  String get aiLessonHelperChipPolish => 'Polish prompts';

  @override
  String aiLessonHelperError(Object error) {
    return 'Something went wrong: $error';
  }

  @override
  String get aiLessonHelperErrorUnknown =>
      'Something went wrong: Unknown error';

  @override
  String get aiLessonHelperPreviewTitle => 'Preview';

  @override
  String get aiLessonHelperTransformationReady =>
      'Transformation ready. Tap Apply to update the lesson.';

  @override
  String get aiLessonHelperTransform => 'Transform';

  @override
  String aiLessonHelperInvalidJson(Object error) {
    return 'Invalid lesson JSON: $error';
  }

  @override
  String get aiLessonHelperLessonUpdated => 'Lesson updated.';

  @override
  String aiLessonHelperUpdateFailed(Object error) {
    return 'Update failed: $error';
  }

  @override
  String get aiTutorTitle => 'AI Tutor';

  @override
  String aiTutorTitleWithType(String typeLabel) {
    return 'AI Tutor · $typeLabel';
  }

  @override
  String get aiEmptyHintTutor =>
      'AI is preparing an explanation for this question…';

  @override
  String get aiThinking => 'AI is thinking…';

  @override
  String get aiAskMore => 'Ask more…';

  @override
  String get aiHintTitle => 'AI hint';

  @override
  String aiHintTitleWithType(String typeLabel) {
    return 'AI hint · $typeLabel';
  }

  @override
  String aiHintError(Object error) {
    return 'Something went wrong: $error';
  }

  @override
  String get aiHintErrorUnknown => 'Something went wrong: Unknown error';

  @override
  String get aiHintOpenChat => 'Open chat';

  @override
  String get ankiImportTitle => 'Import Anki Deck';

  @override
  String get ankiImportDialogTitle => 'Import Anki Deck';

  @override
  String get ankiImportSelectTitle => 'Import an Anki Deck';

  @override
  String get ankiImportSelectSubtitle =>
      'Select a .apkg or .colpkg file exported from Anki';

  @override
  String get ankiChooseFile => 'Choose File';

  @override
  String get ankiParsing => 'Parsing Anki collection...';

  @override
  String get ankiCollectionSummary => 'Collection Summary';

  @override
  String get ankiDecksLabel => 'Decks';

  @override
  String get ankiNotesLabel => 'Notes';

  @override
  String get ankiCardsLabel => 'Cards';

  @override
  String get ankiMediaFilesLabel => 'Media files';

  @override
  String get ankiDeckStructure => 'Deck Structure';

  @override
  String ankiDeckCardCount(int cardCount) {
    return '$cardCount cards';
  }

  @override
  String get ankiNotetypeMapping => 'Notetype Mapping';

  @override
  String get ankiCollisionReport => 'Collision Report';

  @override
  String get ankiNewCards => 'New cards';

  @override
  String get ankiExistingCards => 'Already existing';

  @override
  String get ankiImportStrategy => 'Import Strategy';

  @override
  String get ankiImportComplete => 'Import Complete!';

  @override
  String ankiCardsImported(int cardCount) {
    return '$cardCount cards imported';
  }

  @override
  String ankiLessonsCreated(int lessonCount) {
    return '$lessonCount lessons created';
  }

  @override
  String ankiVocabAdded(int wordEntryCount) {
    return '$wordEntryCount vocabulary entries added';
  }

  @override
  String get ankiPickFileError => 'Please select an .apkg or .colpkg file.';

  @override
  String ankiPickFileFailed(Object error) {
    return 'Failed to pick file: $error';
  }

  @override
  String ankiParseFailed(Object error) {
    return 'Failed to parse: $error';
  }

  @override
  String get ankiPreparingImport => 'Preparing import...';

  @override
  String get ankiAssemblingCourse => 'Assembling course tree...';

  @override
  String get ankiMigratingSrs => 'Migrating SRS state...';

  @override
  String get ankiSavingMetadata => 'Saving import metadata...';

  @override
  String ankiImportFailed(Object error) {
    return 'Import failed: $error';
  }

  @override
  String get ankiStrategyMerge => 'Merge';

  @override
  String get ankiStrategySkipExisting => 'Skip Existing';

  @override
  String get ankiStrategyForceReplace => 'Force Replace';

  @override
  String get ankiStrategyAppendAsNew => 'Append as New';

  @override
  String get ankiStrategyMergeDesc => 'Update existing cards, add new ones';

  @override
  String get ankiStrategySkipExistingDesc =>
      'Only import cards that don\'t exist';

  @override
  String get ankiStrategyForceReplaceDesc => 'Replace all existing data';

  @override
  String get ankiStrategyAppendAsNewDesc => 'Add all as new (with suffix)';

  @override
  String get ankiReviewTitle => 'Anki Review';

  @override
  String get ankiNoCardsDue => 'No Anki cards due for review right now.';

  @override
  String get ankiReviewScreenTitle => 'Anki Review';

  @override
  String get ankiImportNewDeck => 'Import new deck';

  @override
  String ankiCardsDueReview(int totalDue) {
    return '$totalDue cards due for review';
  }

  @override
  String get ankiReviewAll => 'Review All';

  @override
  String get ankiNoDecksTitle => 'No Anki Decks Imported';

  @override
  String get ankiNoDecksSubtitle => 'Import an .apkg file to start reviewing';

  @override
  String get ankiImportDeck => 'Import Deck';

  @override
  String ankiQuotaRemaining(int newLeft, int reviewLeft) {
    return 'Today: $newLeft new, $reviewLeft reviews left';
  }

  @override
  String get ankiQuotaExhausted => 'Daily limit reached — come back tomorrow';

  @override
  String get ankiUninstallDeck => 'Remove deck';

  @override
  String get ankiUninstallConfirmTitle => 'Remove this deck?';

  @override
  String get ankiUninstallConfirmBody =>
      'This deletes the deck\'s cards, review progress, and media files. This cannot be undone.';

  @override
  String get ankiDeckRemoved => 'Deck removed';

  @override
  String get coursesCouldNotLoadCourse => 'Could not load course';

  @override
  String get coursesNoSectionsFound => 'No course sections found.';

  @override
  String get coursesCouldNotLoadSection => 'Could not load section';

  @override
  String get coursesNoUnitsAvailable => 'No units available';

  @override
  String get coursesLoadingCourses => 'Loading courses...';

  @override
  String get coursesLessonTypeNormal => 'Lesson';

  @override
  String get coursesLessonTypeListening => 'Listening';

  @override
  String get coursesLessonTypeReading => 'Reading';

  @override
  String get coursesLessonTypeReview => 'Review';

  @override
  String get coursesLessonTypeChallenge => 'Challenge';

  @override
  String get coursesPerfect => 'Perfect';

  @override
  String coursesUnitProgress(int completedCount, int lessonsCount) {
    return '$completedCount/$lessonsCount';
  }

  @override
  String get coursesChooseSection => 'Choose a Section';

  @override
  String get dictionaryTitle => 'Dictionary';

  @override
  String get dictionarySearchHint => 'Search Turkish or English…';

  @override
  String get dictionarySearchEmpty =>
      'Search vocabulary, expressions, and grammar';

  @override
  String get dictionaryNoMatches => 'No matches';

  @override
  String get dictionaryKindWord => 'Word';

  @override
  String get dictionaryKindPhrase => 'Phrase';

  @override
  String get dictionaryKindGrammar => 'Grammar';

  @override
  String get dictionaryPlayPronunciation => 'Play pronunciation';

  @override
  String get onboardingReclaimingTitle => 'Reclaiming Language Learning';

  @override
  String get onboardingBody =>
      'Remember when learning was about knowledge, not maximizing ad revenue? No hearts. No energy. No pay-to-win. Just pure, open-source education.';

  @override
  String get onboardingStartLearning => 'Start Learning';

  @override
  String get profileTitle => 'Profile';

  @override
  String get profileShare => 'Share';

  @override
  String get profileShareYourProgress => 'Share your progress';

  @override
  String get profileShareButton => 'Share';

  @override
  String get profileSharing => 'Sharing...';

  @override
  String profileShareFailed(Object error) {
    return 'Could not share progress: $error';
  }

  @override
  String get profileLearnerFallback => 'Learner';

  @override
  String get profileAchievementsTitle => 'Achievements';

  @override
  String profileViewMore(int remainingCount) {
    return 'View $remainingCount more';
  }

  @override
  String get profileShowLess => 'Show less';

  @override
  String profileAchievementLevel(int level) {
    return 'Lv.$level';
  }

  @override
  String profileAchievementProgress(int current, int displayTarget) {
    return '$current/$displayTarget';
  }

  @override
  String get profileLearningStatsTitle => 'Learning Stats';

  @override
  String get profileXpToday => 'XP Today';

  @override
  String get profileStudyTime => 'Study Time';

  @override
  String get profileAccuracy => 'Accuracy';

  @override
  String profileStudyTimeValue(int minutes) {
    return '$minutes\'';
  }

  @override
  String profileAccuracyValue(int accuracy) {
    return '$accuracy%';
  }

  @override
  String get profileLast7Days => 'Last 7 Days';

  @override
  String get profileTotalStudyTime => 'Total Study Time';

  @override
  String get profileOverallAccuracy => 'Overall Accuracy';

  @override
  String get profileLessonsDone => 'Lessons Done';

  @override
  String get profileReviewsDone => 'Reviews Done';

  @override
  String profileTotalStudyTimeValue(int totalMinutes) {
    return '${totalMinutes}m';
  }

  @override
  String profileOverallAccuracyValue(int accuracy) {
    return '$accuracy%';
  }

  @override
  String get profileStatisticsTitle => 'Statistics';

  @override
  String get profileDayStreak => 'Day Streak';

  @override
  String get profileTotalXp => 'Total XP';

  @override
  String get profileGems => 'Gems';

  @override
  String profileShareCardLearning(String displayName) {
    return '$displayName is learning';
  }

  @override
  String get profileShareCardDayStreak => 'Day Streak';

  @override
  String get profileShareCardTotalXp => 'Total XP';

  @override
  String get profileShareCardGems => 'Gems';

  @override
  String get profileShareCardLessons => 'Lessons';

  @override
  String get profileShareCardJoinMe => 'Join me on Varnamala!';

  @override
  String get profileShareText => 'Check out my progress on Varnamala!';

  @override
  String charactersScriptTitle(String currentLanguage) {
    return '$currentLanguage Script';
  }

  @override
  String get charactersVowelsTitle => 'Vowels';

  @override
  String charactersVowelsSubtitle(int count) {
    return '$count characters';
  }

  @override
  String get charactersConsonantsTitle => 'Consonants';

  @override
  String charactersConsonantsSubtitle(int count) {
    return '$count characters';
  }

  @override
  String get charactersLearnVowels => 'Learn Vowels';

  @override
  String get charactersLearnConsonants => 'Learn Consonants';

  @override
  String get charactersRandomPractice => 'Random Practice';

  @override
  String get charactersVowelsModeTitle => 'Vowels';

  @override
  String get charactersConsonantsModeTitle => 'Consonants';

  @override
  String get charactersRandomModeTitle => 'Random Practice';

  @override
  String get charactersNext => 'Next';

  @override
  String get contentUpdateTitle => 'Course updated';

  @override
  String get contentUpdateMessage =>
      'The Turkish course has been updated with new words and lessons. You can start over or continue with your current progress.';

  @override
  String get contentUpdateKeepProgress => 'Keep progress';

  @override
  String get contentUpdateResetProgress => 'Reset progress';

  @override
  String get splashReclaiming => 'Reclaiming Language Learning';

  @override
  String get splashLearnTurkish => 'Learn Turkish • Türkçe öğren';

  @override
  String get splashFreeForever => 'Free. Forever.';

  @override
  String get splashAppName => 'Varnamala';

  @override
  String get splashSubtitle =>
      'No hearts to lose. No energy to refill.\nJust pure learning.';

  @override
  String get splashGetStarted => 'GET STARTED';

  @override
  String get splashTurkishVoiceMissingTitle => 'Turkish voice data missing';

  @override
  String get splashTurkishVoiceMissingBody =>
      'Google Text-to-speech is installed, but the Turkish voice pack is not downloaded yet.\n\nOpen system TTS settings → preferred engine = Google → install language data for Turkish (Türkçe).';

  @override
  String get splashGoogleTtsMissingTitle => 'Google TTS not available';

  @override
  String get splashGoogleTtsMissingBody =>
      'This device does not show Google Text-to-speech (or package visibility blocked engine discovery).\n\nInstall \"Speech Recognition & Synthesis from Google\", set it as the preferred engine, and download the Turkish voice.';

  @override
  String get splashGoogleTtsNotReadyTitle => 'Google TTS not available';

  @override
  String get splashGoogleTtsNotReadyBody =>
      'Preferred system voice is not ready. Install Google TTS and the Turkish voice pack.';

  @override
  String get splashKeepCurrentVoice => 'Keep current voice';

  @override
  String get splashTtsSettings => 'TTS settings';

  @override
  String get splashInstallGoogleTts => 'Install Google TTS';

  @override
  String get splashCouldNotOpenStore =>
      'Could not open the store. Install Google TTS manually.';

  @override
  String get aiTemplateIntro => 'New Words';

  @override
  String get aiTemplatePractice => 'Practice';

  @override
  String get aiTemplateReview => 'Review';

  @override
  String get aiTemplateListening => 'Listening';

  @override
  String get aiTemplateReading => 'Reading';

  @override
  String get aiTemplateMastery => 'Quiz';

  @override
  String get aiTemplateMixed => 'Mixed';

  @override
  String get settingsUiLanguageTitle => 'App Language';

  @override
  String get settingsUiLanguageSubtitle => 'Choose the interface language';

  @override
  String get settingsUiLanguageSystem => 'Follow system';
}
