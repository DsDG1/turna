import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:intl/intl.dart' as intl;

import 'app_localizations_en.dart';
import 'app_localizations_zh.dart';

// ignore_for_file: type=lint

/// Callers can lookup localized strings with an instance of AppLocalizations
/// returned by `AppLocalizations.of(context)`.
///
/// Applications need to include `AppLocalizations.delegate()` in their app's
/// `localizationDelegates` list, and the locales they support in the app's
/// `supportedLocales` list. For example:
///
/// ```dart
/// import 'l10n/app_localizations.dart';
///
/// return MaterialApp(
///   localizationsDelegates: AppLocalizations.localizationsDelegates,
///   supportedLocales: AppLocalizations.supportedLocales,
///   home: MyApplicationHome(),
/// );
/// ```
///
/// ## Update pubspec.yaml
///
/// Please make sure to update your pubspec.yaml to include the following
/// packages:
///
/// ```yaml
/// dependencies:
///   # Internationalization support.
///   flutter_localizations:
///     sdk: flutter
///   intl: any # Use the pinned version from flutter_localizations
///
///   # Rest of dependencies
/// ```
///
/// ## iOS Applications
///
/// iOS applications define key application metadata, including supported
/// locales, in an Info.plist file that is built into the application bundle.
/// To configure the locales supported by your app, you’ll need to edit this
/// file.
///
/// First, open your project’s ios/Runner.xcworkspace Xcode workspace file.
/// Then, in the Project Navigator, open the Info.plist file under the Runner
/// project’s Runner folder.
///
/// Next, select the Information Property List item, select Add Item from the
/// Editor menu, then select Localizations from the pop-up menu.
///
/// Select and expand the newly-created Localizations item then, for each
/// locale your application supports, add a new item and select the locale
/// you wish to add from the pop-up menu in the Value field. This list should
/// be consistent with the languages listed in the AppLocalizations.supportedLocales
/// property.
abstract class AppLocalizations {
  AppLocalizations(String locale)
      : localeName = intl.Intl.canonicalizedLocale(locale.toString());

  final String localeName;

  static AppLocalizations? of(BuildContext context) {
    return Localizations.of<AppLocalizations>(context, AppLocalizations);
  }

  static const LocalizationsDelegate<AppLocalizations> delegate =
      _AppLocalizationsDelegate();

  /// A list of this localizations delegate along with the default localizations
  /// delegates.
  ///
  /// Returns a list of localizations delegates containing this delegate along with
  /// GlobalMaterialLocalizations.delegate, GlobalCupertinoLocalizations.delegate,
  /// and GlobalWidgetsLocalizations.delegate.
  ///
  /// Additional delegates can be added by appending to this list in
  /// MaterialApp. This list does not have to be used at all if a custom list
  /// of delegates is preferred or required.
  static const List<LocalizationsDelegate<dynamic>> localizationsDelegates =
      <LocalizationsDelegate<dynamic>>[
    delegate,
    GlobalMaterialLocalizations.delegate,
    GlobalCupertinoLocalizations.delegate,
    GlobalWidgetsLocalizations.delegate,
  ];

  /// A list of this localizations delegate's supported locales.
  static const List<Locale> supportedLocales = <Locale>[
    Locale('en'),
    Locale('zh')
  ];

  /// No description provided for @appTitle.
  ///
  /// In en, this message translates to:
  /// **'Varnamala'**
  String get appTitle;

  /// No description provided for @commonCancel.
  ///
  /// In en, this message translates to:
  /// **'Cancel'**
  String get commonCancel;

  /// No description provided for @commonBack.
  ///
  /// In en, this message translates to:
  /// **'Back'**
  String get commonBack;

  /// No description provided for @commonClose.
  ///
  /// In en, this message translates to:
  /// **'Close'**
  String get commonClose;

  /// No description provided for @commonDone.
  ///
  /// In en, this message translates to:
  /// **'Done'**
  String get commonDone;

  /// No description provided for @commonRetry.
  ///
  /// In en, this message translates to:
  /// **'Retry'**
  String get commonRetry;

  /// No description provided for @commonRefresh.
  ///
  /// In en, this message translates to:
  /// **'Refresh'**
  String get commonRefresh;

  /// No description provided for @commonSend.
  ///
  /// In en, this message translates to:
  /// **'Send'**
  String get commonSend;

  /// No description provided for @commonApply.
  ///
  /// In en, this message translates to:
  /// **'Apply'**
  String get commonApply;

  /// No description provided for @commonPractice.
  ///
  /// In en, this message translates to:
  /// **'Practice'**
  String get commonPractice;

  /// No description provided for @commonContinue.
  ///
  /// In en, this message translates to:
  /// **'Continue'**
  String get commonContinue;

  /// No description provided for @commonGotIt.
  ///
  /// In en, this message translates to:
  /// **'Got it'**
  String get commonGotIt;

  /// No description provided for @commonOk.
  ///
  /// In en, this message translates to:
  /// **'OK'**
  String get commonOk;

  /// No description provided for @commonSave.
  ///
  /// In en, this message translates to:
  /// **'Save'**
  String get commonSave;

  /// No description provided for @commonImport.
  ///
  /// In en, this message translates to:
  /// **'Import'**
  String get commonImport;

  /// No description provided for @commonLater.
  ///
  /// In en, this message translates to:
  /// **'Later'**
  String get commonLater;

  /// No description provided for @commonNavLearn.
  ///
  /// In en, this message translates to:
  /// **'Learn'**
  String get commonNavLearn;

  /// No description provided for @commonNavPlay.
  ///
  /// In en, this message translates to:
  /// **'Play'**
  String get commonNavPlay;

  /// No description provided for @commonNavProfile.
  ///
  /// In en, this message translates to:
  /// **'Profile'**
  String get commonNavProfile;

  /// No description provided for @commonNavSettings.
  ///
  /// In en, this message translates to:
  /// **'Settings'**
  String get commonNavSettings;

  /// No description provided for @lessonCheck.
  ///
  /// In en, this message translates to:
  /// **'CHECK'**
  String get lessonCheck;

  /// No description provided for @lessonChecked.
  ///
  /// In en, this message translates to:
  /// **'CHECKED'**
  String get lessonChecked;

  /// No description provided for @lessonContinueUpper.
  ///
  /// In en, this message translates to:
  /// **'CONTINUE'**
  String get lessonContinueUpper;

  /// No description provided for @lessonGotItUpper.
  ///
  /// In en, this message translates to:
  /// **'GOT IT'**
  String get lessonGotItUpper;

  /// No description provided for @settingsCategoryAccount.
  ///
  /// In en, this message translates to:
  /// **'Account'**
  String get settingsCategoryAccount;

  /// No description provided for @settingsCategoryLearning.
  ///
  /// In en, this message translates to:
  /// **'Learning'**
  String get settingsCategoryLearning;

  /// No description provided for @settingsCategoryAudioHaptics.
  ///
  /// In en, this message translates to:
  /// **'Audio & Haptics'**
  String get settingsCategoryAudioHaptics;

  /// No description provided for @settingsCategoryAccessibility.
  ///
  /// In en, this message translates to:
  /// **'Accessibility'**
  String get settingsCategoryAccessibility;

  /// No description provided for @settingsCategoryAiTools.
  ///
  /// In en, this message translates to:
  /// **'AI Tools'**
  String get settingsCategoryAiTools;

  /// No description provided for @settingsCategoryData.
  ///
  /// In en, this message translates to:
  /// **'Data'**
  String get settingsCategoryData;

  /// No description provided for @settingsCategoryAbout.
  ///
  /// In en, this message translates to:
  /// **'About'**
  String get settingsCategoryAbout;

  /// No description provided for @settingsTitle.
  ///
  /// In en, this message translates to:
  /// **'Settings'**
  String get settingsTitle;

  /// No description provided for @settingsBack.
  ///
  /// In en, this message translates to:
  /// **'Back'**
  String get settingsBack;

  /// No description provided for @settingsSoundEffectsTitle.
  ///
  /// In en, this message translates to:
  /// **'Sound effects'**
  String get settingsSoundEffectsTitle;

  /// No description provided for @settingsSoundEffectsSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Play sounds for errors and level-ups'**
  String get settingsSoundEffectsSubtitle;

  /// No description provided for @settingsHapticFeedbackTitle.
  ///
  /// In en, this message translates to:
  /// **'Haptic feedback'**
  String get settingsHapticFeedbackTitle;

  /// No description provided for @settingsHapticFeedbackSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Vibrate on key interactions'**
  String get settingsHapticFeedbackSubtitle;

  /// No description provided for @settingsAiApiConfigTitle.
  ///
  /// In en, this message translates to:
  /// **'AI API Configuration'**
  String get settingsAiApiConfigTitle;

  /// No description provided for @settingsAiApiConfigSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Base URL, API key & model (not saved on exit)'**
  String get settingsAiApiConfigSubtitle;

  /// No description provided for @settingsDesignCourseAiTitle.
  ///
  /// In en, this message translates to:
  /// **'Design a course with AI'**
  String get settingsDesignCourseAiTitle;

  /// No description provided for @settingsDesignCourseAiSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Open the AI design chat'**
  String get settingsDesignCourseAiSubtitle;

  /// No description provided for @settingsImportTextbookTitle.
  ///
  /// In en, this message translates to:
  /// **'Import from Textbook'**
  String get settingsImportTextbookTitle;

  /// No description provided for @settingsImportTextbookSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Convert a markdown/text file into course sections'**
  String get settingsImportTextbookSubtitle;

  /// No description provided for @settingsExportDataTitle.
  ///
  /// In en, this message translates to:
  /// **'Export data'**
  String get settingsExportDataTitle;

  /// No description provided for @settingsExportDataSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Save progress and/or course content to a file'**
  String get settingsExportDataSubtitle;

  /// No description provided for @settingsImportDataTitle.
  ///
  /// In en, this message translates to:
  /// **'Import data'**
  String get settingsImportDataTitle;

  /// No description provided for @settingsImportDataSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Restore progress from an exported file'**
  String get settingsImportDataSubtitle;

  /// No description provided for @settingsClearMistakeLogTitle.
  ///
  /// In en, this message translates to:
  /// **'Clear mistake log'**
  String get settingsClearMistakeLogTitle;

  /// No description provided for @settingsClearMistakeLogSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Remove all saved mistakes'**
  String get settingsClearMistakeLogSubtitle;

  /// No description provided for @settingsResetProgressTitle.
  ///
  /// In en, this message translates to:
  /// **'Reset lesson progress'**
  String get settingsResetProgressTitle;

  /// No description provided for @settingsResetProgressSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Mark all lessons as not completed'**
  String get settingsResetProgressSubtitle;

  /// No description provided for @settingsClearMistakeDialogTitle.
  ///
  /// In en, this message translates to:
  /// **'Clear mistake log?'**
  String get settingsClearMistakeDialogTitle;

  /// No description provided for @settingsClearMistakeDialogMessage.
  ///
  /// In en, this message translates to:
  /// **'This will permanently delete all saved mistakes.'**
  String get settingsClearMistakeDialogMessage;

  /// No description provided for @settingsClearMistakeConfirm.
  ///
  /// In en, this message translates to:
  /// **'Clear'**
  String get settingsClearMistakeConfirm;

  /// No description provided for @settingsMistakeLogCleared.
  ///
  /// In en, this message translates to:
  /// **'Mistake log cleared'**
  String get settingsMistakeLogCleared;

  /// No description provided for @settingsResetProgressDialogTitle.
  ///
  /// In en, this message translates to:
  /// **'Reset lesson progress?'**
  String get settingsResetProgressDialogTitle;

  /// No description provided for @settingsResetProgressDialogMessage.
  ///
  /// In en, this message translates to:
  /// **'All lesson completion and perfect-lesson records will be cleared. This cannot be undone.'**
  String get settingsResetProgressDialogMessage;

  /// No description provided for @settingsResetProgressConfirm.
  ///
  /// In en, this message translates to:
  /// **'Reset'**
  String get settingsResetProgressConfirm;

  /// No description provided for @settingsProgressReset.
  ///
  /// In en, this message translates to:
  /// **'Lesson progress reset'**
  String get settingsProgressReset;

  /// No description provided for @settingsImportDataDialogTitle.
  ///
  /// In en, this message translates to:
  /// **'Import data?'**
  String get settingsImportDataDialogTitle;

  /// No description provided for @settingsImportDataDialogMessage.
  ///
  /// In en, this message translates to:
  /// **'This will overwrite your current progress with the file\'s contents. This cannot be undone. Consider exporting first.'**
  String get settingsImportDataDialogMessage;

  /// No description provided for @settingsImportDataConfirm.
  ///
  /// In en, this message translates to:
  /// **'Import'**
  String get settingsImportDataConfirm;

  /// No description provided for @settingsCourseSavedRestart.
  ///
  /// In en, this message translates to:
  /// **'Course content saved; restart to apply'**
  String get settingsCourseSavedRestart;

  /// No description provided for @settingsProgressRestoredRestart.
  ///
  /// In en, this message translates to:
  /// **'Progress restored — restart the app to apply'**
  String get settingsProgressRestoredRestart;

  /// No description provided for @settingsNothingToImport.
  ///
  /// In en, this message translates to:
  /// **'Nothing to import'**
  String get settingsNothingToImport;

  /// No description provided for @settingsImportFailed.
  ///
  /// In en, this message translates to:
  /// **'Import failed: {error}'**
  String settingsImportFailed(Object error);

  /// No description provided for @settingsExportFailed.
  ///
  /// In en, this message translates to:
  /// **'Export failed: {error}'**
  String settingsExportFailed(Object error);

  /// No description provided for @settingsAiApiConfigSheetTitle.
  ///
  /// In en, this message translates to:
  /// **'AI API Configuration'**
  String get settingsAiApiConfigSheetTitle;

  /// No description provided for @settingsAiApiConfigNotSaved.
  ///
  /// In en, this message translates to:
  /// **'Not saved on exit — kept in memory only.'**
  String get settingsAiApiConfigNotSaved;

  /// No description provided for @settingsBaseUrlLabel.
  ///
  /// In en, this message translates to:
  /// **'Base URL'**
  String get settingsBaseUrlLabel;

  /// No description provided for @settingsBaseUrlHint.
  ///
  /// In en, this message translates to:
  /// **'https://api.deepseek.com'**
  String get settingsBaseUrlHint;

  /// No description provided for @settingsApiKeyLabel.
  ///
  /// In en, this message translates to:
  /// **'API Key'**
  String get settingsApiKeyLabel;

  /// No description provided for @settingsApiKeyHint.
  ///
  /// In en, this message translates to:
  /// **'sk-...'**
  String get settingsApiKeyHint;

  /// No description provided for @settingsModelLabel.
  ///
  /// In en, this message translates to:
  /// **'Model'**
  String get settingsModelLabel;

  /// No description provided for @settingsModelHint.
  ///
  /// In en, this message translates to:
  /// **'deepseek-v4-pro'**
  String get settingsModelHint;

  /// No description provided for @settingsSaveConfig.
  ///
  /// In en, this message translates to:
  /// **'Save configuration'**
  String get settingsSaveConfig;

  /// No description provided for @settingsExportSheetTitle.
  ///
  /// In en, this message translates to:
  /// **'Export data'**
  String get settingsExportSheetTitle;

  /// No description provided for @settingsExportSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Choose what to include in the export file.'**
  String get settingsExportSubtitle;

  /// No description provided for @settingsExportProgressTitle.
  ///
  /// In en, this message translates to:
  /// **'Progress data'**
  String get settingsExportProgressTitle;

  /// No description provided for @settingsExportProgressSubtitle.
  ///
  /// In en, this message translates to:
  /// **'SRS, score, streak, mistakes, achievements'**
  String get settingsExportProgressSubtitle;

  /// No description provided for @settingsExportCourseTitle.
  ///
  /// In en, this message translates to:
  /// **'Course content'**
  String get settingsExportCourseTitle;

  /// No description provided for @settingsExportCourseSubtitle.
  ///
  /// In en, this message translates to:
  /// **'The bundled Turkish course JSON files'**
  String get settingsExportCourseSubtitle;

  /// No description provided for @settingsExportButton.
  ///
  /// In en, this message translates to:
  /// **'Export'**
  String get settingsExportButton;

  /// No description provided for @settingsExporting.
  ///
  /// In en, this message translates to:
  /// **'Exporting...'**
  String get settingsExporting;

  /// No description provided for @settingsAboutVarnamala.
  ///
  /// In en, this message translates to:
  /// **'About Varnamala'**
  String get settingsAboutVarnamala;

  /// No description provided for @settingsOpenSourceLicenses.
  ///
  /// In en, this message translates to:
  /// **'Open source licenses'**
  String get settingsOpenSourceLicenses;

  /// No description provided for @settingsVersionFooter.
  ///
  /// In en, this message translates to:
  /// **'Version {version}'**
  String settingsVersionFooter(String version);

  /// No description provided for @settingsVersionFooterWithBuild.
  ///
  /// In en, this message translates to:
  /// **'Version {version} ({build})'**
  String settingsVersionFooterWithBuild(String version, String build);

  /// No description provided for @settingsAccountLearnerFallback.
  ///
  /// In en, this message translates to:
  /// **'Learner'**
  String get settingsAccountLearnerFallback;

  /// No description provided for @settingsThemeLight.
  ///
  /// In en, this message translates to:
  /// **'Light'**
  String get settingsThemeLight;

  /// No description provided for @settingsThemeDark.
  ///
  /// In en, this message translates to:
  /// **'Dark'**
  String get settingsThemeDark;

  /// No description provided for @settingsThemeSystem.
  ///
  /// In en, this message translates to:
  /// **'System'**
  String get settingsThemeSystem;

  /// No description provided for @settingsLearningLanguageTitle.
  ///
  /// In en, this message translates to:
  /// **'Learning Language'**
  String get settingsLearningLanguageTitle;

  /// No description provided for @settingsLearningLanguageSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Choose the language you are learning'**
  String get settingsLearningLanguageSubtitle;

  /// No description provided for @settingsTtsSpeedTitle.
  ///
  /// In en, this message translates to:
  /// **'TTS Speed'**
  String get settingsTtsSpeedTitle;

  /// No description provided for @settingsTtsSpeedSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Adjust voice playback speed'**
  String get settingsTtsSpeedSubtitle;

  /// No description provided for @settingsTtsSpeedValue.
  ///
  /// In en, this message translates to:
  /// **'{ttsSpeed}x'**
  String settingsTtsSpeedValue(String ttsSpeed);

  /// No description provided for @settingsDailyReminderTitle.
  ///
  /// In en, this message translates to:
  /// **'Daily reminder'**
  String get settingsDailyReminderTitle;

  /// No description provided for @settingsDailyReminderSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Gentle nudge to review — no streaks or penalties'**
  String get settingsDailyReminderSubtitle;

  /// No description provided for @settingsReminderTimeTitle.
  ///
  /// In en, this message translates to:
  /// **'Reminder time'**
  String get settingsReminderTimeTitle;

  /// No description provided for @settingsReminderTimeSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Currently {timeLabel}'**
  String settingsReminderTimeSubtitle(String timeLabel);

  /// No description provided for @settingsTtsChecking.
  ///
  /// In en, this message translates to:
  /// **'Checking device TTS engines…'**
  String get settingsTtsChecking;

  /// No description provided for @settingsTtsReady.
  ///
  /// In en, this message translates to:
  /// **'Google TTS ready ({locale}) — recommended for learning'**
  String settingsTtsReady(String locale);

  /// No description provided for @settingsTtsGoogleInstalledMissingVoice.
  ///
  /// In en, this message translates to:
  /// **'Google installed — download Turkish voice data in system TTS settings'**
  String get settingsTtsGoogleInstalledMissingVoice;

  /// No description provided for @settingsTtsTurkishVoiceMissing.
  ///
  /// In en, this message translates to:
  /// **'Turkish voice not ready — open system TTS settings'**
  String get settingsTtsTurkishVoiceMissing;

  /// No description provided for @settingsTtsGoogleMissing.
  ///
  /// In en, this message translates to:
  /// **'Google TTS not detected (engines: {oem})'**
  String settingsTtsGoogleMissing(Object oem);

  /// No description provided for @settingsVoiceSourceTitle.
  ///
  /// In en, this message translates to:
  /// **'Voice source'**
  String get settingsVoiceSourceTitle;

  /// No description provided for @settingsSystemTts.
  ///
  /// In en, this message translates to:
  /// **'System TTS'**
  String get settingsSystemTts;

  /// No description provided for @settingsVoiceSourceDialogTitle.
  ///
  /// In en, this message translates to:
  /// **'Voice source'**
  String get settingsVoiceSourceDialogTitle;

  /// No description provided for @settingsPlaySample.
  ///
  /// In en, this message translates to:
  /// **'Play sample (Merhaba)…'**
  String get settingsPlaySample;

  /// No description provided for @settingsOpenSystemTts.
  ///
  /// In en, this message translates to:
  /// **'Open system TTS settings…'**
  String get settingsOpenSystemTts;

  /// No description provided for @settingsInstallGoogleTts.
  ///
  /// In en, this message translates to:
  /// **'Install / open Google TTS…'**
  String get settingsInstallGoogleTts;

  /// No description provided for @settingsTtsNoVoicePlayed.
  ///
  /// In en, this message translates to:
  /// **'No voice played. {error}'**
  String settingsTtsNoVoicePlayed(Object error);

  /// No description provided for @settingsTtsNoVoicePlayedFallback.
  ///
  /// In en, this message translates to:
  /// **'No voice played. Check logcat for TTS errors.'**
  String get settingsTtsNoVoicePlayedFallback;

  /// No description provided for @settingsTtsPlaying.
  ///
  /// In en, this message translates to:
  /// **'Playing: {userLabel}'**
  String settingsTtsPlaying(String userLabel);

  /// No description provided for @settingsTextSizeTitle.
  ///
  /// In en, this message translates to:
  /// **'Text size'**
  String get settingsTextSizeTitle;

  /// No description provided for @settingsTextSizeSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Magnify text app-wide'**
  String get settingsTextSizeSubtitle;

  /// No description provided for @settingsTextSizeValue.
  ///
  /// In en, this message translates to:
  /// **'{textScale}%'**
  String settingsTextSizeValue(int textScale);

  /// No description provided for @settingsReduceMotionTitle.
  ///
  /// In en, this message translates to:
  /// **'Reduce motion'**
  String get settingsReduceMotionTitle;

  /// No description provided for @settingsReduceMotionSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Shorten or disable animations and transitions'**
  String get settingsReduceMotionSubtitle;

  /// No description provided for @settingsHighContrastTitle.
  ///
  /// In en, this message translates to:
  /// **'High contrast'**
  String get settingsHighContrastTitle;

  /// No description provided for @settingsHighContrastSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Use a high-contrast color theme'**
  String get settingsHighContrastSubtitle;

  /// No description provided for @settingsDyslexiaFontTitle.
  ///
  /// In en, this message translates to:
  /// **'Dyslexia-friendly font'**
  String get settingsDyslexiaFontTitle;

  /// No description provided for @settingsDyslexiaFontSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Switch to the Lexend typeface for easier reading'**
  String get settingsDyslexiaFontSubtitle;

  /// No description provided for @settingsSensoryReduceTitle.
  ///
  /// In en, this message translates to:
  /// **'Reduce sensory input'**
  String get settingsSensoryReduceTitle;

  /// No description provided for @settingsSensoryReduceSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Mute non-essential sounds and haptics'**
  String get settingsSensoryReduceSubtitle;

  /// No description provided for @settingsFocusModeTitle.
  ///
  /// In en, this message translates to:
  /// **'Focus mode'**
  String get settingsFocusModeTitle;

  /// No description provided for @settingsFocusModeSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Hide the rotating welcome animation on the home screen'**
  String get settingsFocusModeSubtitle;

  /// No description provided for @aboutTitle.
  ///
  /// In en, this message translates to:
  /// **'About Varnamala'**
  String get aboutTitle;

  /// No description provided for @aboutWhatIsTitle.
  ///
  /// In en, this message translates to:
  /// **'What is Varnamala'**
  String get aboutWhatIsTitle;

  /// No description provided for @aboutWhatIsBody.
  ///
  /// In en, this message translates to:
  /// **'Varnamala is a free, open-source language learning app focused on helping you build real vocabulary and grammar skills — one small step at a time. It keeps learning offline, distraction-free, and under your control.'**
  String get aboutWhatIsBody;

  /// No description provided for @aboutHighlightsTitle.
  ///
  /// In en, this message translates to:
  /// **'Highlights'**
  String get aboutHighlightsTitle;

  /// No description provided for @aboutHighlightOfflineTitle.
  ///
  /// In en, this message translates to:
  /// **'Offline first'**
  String get aboutHighlightOfflineTitle;

  /// No description provided for @aboutHighlightOfflineSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Learn anywhere'**
  String get aboutHighlightOfflineSubtitle;

  /// No description provided for @aboutHighlightSrsTitle.
  ///
  /// In en, this message translates to:
  /// **'SRS review'**
  String get aboutHighlightSrsTitle;

  /// No description provided for @aboutHighlightSrsSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Remember more'**
  String get aboutHighlightSrsSubtitle;

  /// No description provided for @aboutHighlightInteractionsTitle.
  ///
  /// In en, this message translates to:
  /// **'11 interactions'**
  String get aboutHighlightInteractionsTitle;

  /// No description provided for @aboutHighlightInteractionsSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Practice all skills'**
  String get aboutHighlightInteractionsSubtitle;

  /// No description provided for @aboutPrivacyTitle.
  ///
  /// In en, this message translates to:
  /// **'Privacy & local-first'**
  String get aboutPrivacyTitle;

  /// No description provided for @aboutPrivacyBody.
  ///
  /// In en, this message translates to:
  /// **'Everything you learn stays on this device. Varnamala has no cloud backend, no account, and no tracking — your progress, mistakes, and settings never leave your phone. Uninstalling the app removes all of it. The only network access is optional (opening external links or the AI tools you configure yourself).'**
  String get aboutPrivacyBody;

  /// No description provided for @aboutVersionTitle.
  ///
  /// In en, this message translates to:
  /// **'Version & changelog'**
  String get aboutVersionTitle;

  /// No description provided for @aboutLinksTitle.
  ///
  /// In en, this message translates to:
  /// **'Links'**
  String get aboutLinksTitle;

  /// No description provided for @aboutUpstreamTitle.
  ///
  /// In en, this message translates to:
  /// **'Upstream project'**
  String get aboutUpstreamTitle;

  /// No description provided for @aboutUpstreamSubtitle.
  ///
  /// In en, this message translates to:
  /// **'github.com/rshrc/Varnamala'**
  String get aboutUpstreamSubtitle;

  /// No description provided for @aboutReportIssueTitle.
  ///
  /// In en, this message translates to:
  /// **'Report an issue'**
  String get aboutReportIssueTitle;

  /// No description provided for @aboutReportIssueSubtitle.
  ///
  /// In en, this message translates to:
  /// **'GitHub Issues'**
  String get aboutReportIssueSubtitle;

  /// No description provided for @aboutViewReleasesTitle.
  ///
  /// In en, this message translates to:
  /// **'View releases'**
  String get aboutViewReleasesTitle;

  /// No description provided for @aboutViewReleasesSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Changelog & downloads'**
  String get aboutViewReleasesSubtitle;

  /// No description provided for @aboutShareTitle.
  ///
  /// In en, this message translates to:
  /// **'Share Varnamala'**
  String get aboutShareTitle;

  /// No description provided for @aboutCreditsTitle.
  ///
  /// In en, this message translates to:
  /// **'Credits'**
  String get aboutCreditsTitle;

  /// No description provided for @aboutCreditsOriginal.
  ///
  /// In en, this message translates to:
  /// **'Original framework by Rishi Banerjee and the Varnamala open-source community.'**
  String get aboutCreditsOriginal;

  /// No description provided for @aboutCreditsFork.
  ///
  /// In en, this message translates to:
  /// **'This build is a local-first fork with additional accessibility settings and a focused course-authoring tool.'**
  String get aboutCreditsFork;

  /// No description provided for @aboutLicense.
  ///
  /// In en, this message translates to:
  /// **'Licensed under the GNU General Public License v3.0.'**
  String get aboutLicense;

  /// No description provided for @aboutCopyright.
  ///
  /// In en, this message translates to:
  /// **'© {year} Varnamala'**
  String aboutCopyright(String year);

  /// No description provided for @aboutBrandName.
  ///
  /// In en, this message translates to:
  /// **'Varnamala'**
  String get aboutBrandName;

  /// No description provided for @aboutTagline.
  ///
  /// In en, this message translates to:
  /// **'Learn languages, one step at a time.'**
  String get aboutTagline;

  /// No description provided for @aboutVersionLabel.
  ///
  /// In en, this message translates to:
  /// **'Version {version}'**
  String aboutVersionLabel(String version);

  /// No description provided for @aboutVersionWithBuild.
  ///
  /// In en, this message translates to:
  /// **'Version {version} ({buildNumber})'**
  String aboutVersionWithBuild(String version, String buildNumber);

  /// No description provided for @aboutShareText.
  ///
  /// In en, this message translates to:
  /// **'Check out Varnamala — a free, open-source language learning app! https://github.com/rshrc/Varnamala'**
  String get aboutShareText;

  /// No description provided for @aboutVersionShort.
  ///
  /// In en, this message translates to:
  /// **'Version {version}'**
  String aboutVersionShort(String version);

  /// No description provided for @aboutVersionBuild.
  ///
  /// In en, this message translates to:
  /// **'({buildNumber})'**
  String aboutVersionBuild(String buildNumber);

  /// No description provided for @aboutHideChangelog.
  ///
  /// In en, this message translates to:
  /// **'Hide'**
  String get aboutHideChangelog;

  /// No description provided for @aboutShowChangelog.
  ///
  /// In en, this message translates to:
  /// **'Show changelog'**
  String get aboutShowChangelog;

  /// No description provided for @aboutReleasesNote.
  ///
  /// In en, this message translates to:
  /// **'For the full release history, see the GitHub releases page.'**
  String get aboutReleasesNote;

  /// No description provided for @aboutMilestone1Title.
  ///
  /// In en, this message translates to:
  /// **'future4 framework'**
  String get aboutMilestone1Title;

  /// No description provided for @aboutMilestone1Body.
  ///
  /// In en, this message translates to:
  /// **'Completed clean-architecture framework: DI consolidation, audio/content decoupling, SRS queue base class, GameProvider facade, integration tests, release pipeline.'**
  String get aboutMilestone1Body;

  /// No description provided for @aboutMilestone2Title.
  ///
  /// In en, this message translates to:
  /// **'Swahili → Turkish pivot'**
  String get aboutMilestone2Title;

  /// No description provided for @aboutMilestone2Body.
  ///
  /// In en, this message translates to:
  /// **'Migrated the target language to Turkish and filled Section 1 with a real greetings lesson (8 words + 2 expressions).'**
  String get aboutMilestone2Body;

  /// No description provided for @aboutMilestone3Title.
  ///
  /// In en, this message translates to:
  /// **'Accessibility settings'**
  String get aboutMilestone3Title;

  /// No description provided for @aboutMilestone3Body.
  ///
  /// In en, this message translates to:
  /// **'Added neurodiversity-friendly options: text size, reduced motion, high contrast, dyslexia-friendly font, sensory reduction, and focus mode.'**
  String get aboutMilestone3Body;

  /// No description provided for @homeAiCourseDesigner.
  ///
  /// In en, this message translates to:
  /// **'AI Course Designer'**
  String get homeAiCourseDesigner;

  /// No description provided for @homeNewCourse.
  ///
  /// In en, this message translates to:
  /// **'New Course'**
  String get homeNewCourse;

  /// No description provided for @homeNewCourseSheetTitle.
  ///
  /// In en, this message translates to:
  /// **'New Course'**
  String get homeNewCourseSheetTitle;

  /// No description provided for @homeDesignWithAi.
  ///
  /// In en, this message translates to:
  /// **'Design with AI'**
  String get homeDesignWithAi;

  /// No description provided for @homeDesignWithAiSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Describe a course and let AI build it'**
  String get homeDesignWithAiSubtitle;

  /// No description provided for @homeImportFromTextbook.
  ///
  /// In en, this message translates to:
  /// **'Import from Textbook'**
  String get homeImportFromTextbook;

  /// No description provided for @homeImportFromTextbookSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Convert a markdown/text file into sections'**
  String get homeImportFromTextbookSubtitle;

  /// No description provided for @homeFromAnki.
  ///
  /// In en, this message translates to:
  /// **'From Anki'**
  String get homeFromAnki;

  /// No description provided for @homeFromAnkiSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Import an .apkg/.colpkg deck as a course'**
  String get homeFromAnkiSubtitle;

  /// No description provided for @homeStreakBroken.
  ///
  /// In en, this message translates to:
  /// **'Your streak was broken. Start again today.'**
  String get homeStreakBroken;

  /// No description provided for @ankiImportSuccess.
  ///
  /// In en, this message translates to:
  /// **'Successfully imported {count} words!'**
  String ankiImportSuccess(int count);

  /// No description provided for @ankiImportError.
  ///
  /// In en, this message translates to:
  /// **'Import failed. Please check the file format.'**
  String get ankiImportError;

  /// No description provided for @homeNewCourseComingSoon.
  ///
  /// In en, this message translates to:
  /// **'Multi-language course support is coming soon. Currently only Turkish is available.'**
  String get homeNewCourseComingSoon;

  /// No description provided for @homeNewCourseUseAi.
  ///
  /// In en, this message translates to:
  /// **'You can also use the AI Course Designer to create custom courses.'**
  String get homeNewCourseUseAi;

  /// No description provided for @dialogClose.
  ///
  /// In en, this message translates to:
  /// **'Close'**
  String get dialogClose;

  /// No description provided for @playQuickPlayTitle.
  ///
  /// In en, this message translates to:
  /// **'Quick Play'**
  String get playQuickPlayTitle;

  /// No description provided for @playQuickPlaySubtitle.
  ///
  /// In en, this message translates to:
  /// **'Match words as fast as you can'**
  String get playQuickPlaySubtitle;

  /// No description provided for @playMistakeReviewTitle.
  ///
  /// In en, this message translates to:
  /// **'Mistake Review'**
  String get playMistakeReviewTitle;

  /// No description provided for @playMistakeReviewSubtitleWithCount.
  ///
  /// In en, this message translates to:
  /// **'{mistakesCount} mistakes — practice up to 10'**
  String playMistakeReviewSubtitleWithCount(int mistakesCount);

  /// No description provided for @playMistakeReviewSubtitleEmpty.
  ///
  /// In en, this message translates to:
  /// **'No mistakes recorded'**
  String get playMistakeReviewSubtitleEmpty;

  /// No description provided for @playReviewTitle.
  ///
  /// In en, this message translates to:
  /// **'Review'**
  String get playReviewTitle;

  /// No description provided for @playReviewSubtitleWithDue.
  ///
  /// In en, this message translates to:
  /// **'{srsDue} words due for review'**
  String playReviewSubtitleWithDue(int srsDue);

  /// No description provided for @playReviewSubtitleEmpty.
  ///
  /// In en, this message translates to:
  /// **'No words due right now'**
  String get playReviewSubtitleEmpty;

  /// No description provided for @playGrammarReviewTitle.
  ///
  /// In en, this message translates to:
  /// **'Grammar Review'**
  String get playGrammarReviewTitle;

  /// No description provided for @playGrammarReviewSubtitleWithDue.
  ///
  /// In en, this message translates to:
  /// **'{grammarDue} grammar points due for review'**
  String playGrammarReviewSubtitleWithDue(int grammarDue);

  /// No description provided for @playGrammarReviewSubtitleEmpty.
  ///
  /// In en, this message translates to:
  /// **'No grammar due right now'**
  String get playGrammarReviewSubtitleEmpty;

  /// No description provided for @playDailyChallengeTitle.
  ///
  /// In en, this message translates to:
  /// **'Daily Challenge'**
  String get playDailyChallengeTitle;

  /// No description provided for @playDailyChallengeSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Random 15 questions — test your Turkish'**
  String get playDailyChallengeSubtitle;

  /// No description provided for @playWeakWordsTitle.
  ///
  /// In en, this message translates to:
  /// **'Weak Words'**
  String get playWeakWordsTitle;

  /// No description provided for @playWeakWordsSubtitleWithCount.
  ///
  /// In en, this message translates to:
  /// **'{weakCount} words missed twice in 30 days'**
  String playWeakWordsSubtitleWithCount(int weakCount);

  /// No description provided for @playWeakWordsSubtitleEmpty.
  ///
  /// In en, this message translates to:
  /// **'No weak words right now'**
  String get playWeakWordsSubtitleEmpty;

  /// No description provided for @playAnkiReviewTitle.
  ///
  /// In en, this message translates to:
  /// **'Anki Review'**
  String get playAnkiReviewTitle;

  /// No description provided for @playAnkiReviewSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Review imported Anki decks'**
  String get playAnkiReviewSubtitle;

  /// No description provided for @playDictionaryTitle.
  ///
  /// In en, this message translates to:
  /// **'Dictionary'**
  String get playDictionaryTitle;

  /// No description provided for @playDictionarySubtitle.
  ///
  /// In en, this message translates to:
  /// **'Search words, phrases, and grammar'**
  String get playDictionarySubtitle;

  /// No description provided for @playYourBestTitle.
  ///
  /// In en, this message translates to:
  /// **'Your Best'**
  String get playYourBestTitle;

  /// No description provided for @playTotalXp.
  ///
  /// In en, this message translates to:
  /// **'Total XP'**
  String get playTotalXp;

  /// No description provided for @playTitle.
  ///
  /// In en, this message translates to:
  /// **'Play'**
  String get playTitle;

  /// No description provided for @playMatchMadness.
  ///
  /// In en, this message translates to:
  /// **'Match Madness'**
  String get playMatchMadness;

  /// No description provided for @playXpLabel.
  ///
  /// In en, this message translates to:
  /// **'{sessionScore} XP'**
  String playXpLabel(int sessionScore);

  /// No description provided for @playRoundLabel.
  ///
  /// In en, this message translates to:
  /// **'Round {roundsCompleted}'**
  String playRoundLabel(int roundsCompleted);

  /// No description provided for @playInfiniteRoundsNote.
  ///
  /// In en, this message translates to:
  /// **'Infinite rounds. New words appear after each perfect board.'**
  String get playInfiniteRoundsNote;

  /// No description provided for @playRoundComplete.
  ///
  /// In en, this message translates to:
  /// **'Round complete! Loading new words...'**
  String get playRoundComplete;

  /// No description provided for @playTimeUp.
  ///
  /// In en, this message translates to:
  /// **'Time up! You completed {roundsCompleted} rounds and earned {score} XP.'**
  String playTimeUp(int roundsCompleted, int score);

  /// No description provided for @playPlayAgain.
  ///
  /// In en, this message translates to:
  /// **'Play Again'**
  String get playPlayAgain;

  /// No description provided for @playBrilliantRun.
  ///
  /// In en, this message translates to:
  /// **'Brilliant Run!'**
  String get playBrilliantRun;

  /// No description provided for @playChampionEnergy.
  ///
  /// In en, this message translates to:
  /// **'Champion Energy!'**
  String get playChampionEnergy;

  /// No description provided for @playLightningFast.
  ///
  /// In en, this message translates to:
  /// **'Lightning Fast!'**
  String get playLightningFast;

  /// No description provided for @playMatchCount.
  ///
  /// In en, this message translates to:
  /// **'{matchedCount} / {totalCount}'**
  String playMatchCount(int matchedCount, int totalCount);

  /// No description provided for @playDailyClose.
  ///
  /// In en, this message translates to:
  /// **'Close'**
  String get playDailyClose;

  /// No description provided for @playDailyTitle.
  ///
  /// In en, this message translates to:
  /// **'Daily Challenge'**
  String get playDailyTitle;

  /// No description provided for @playDailyQuestion.
  ///
  /// In en, this message translates to:
  /// **'Question {current} of {total}'**
  String playDailyQuestion(int current, int total);

  /// No description provided for @playDailyChallengeFallback.
  ///
  /// In en, this message translates to:
  /// **'Daily Challenge'**
  String get playDailyChallengeFallback;

  /// No description provided for @playDailyContinue.
  ///
  /// In en, this message translates to:
  /// **'CONTINUE'**
  String get playDailyContinue;

  /// No description provided for @playDailyGotIt.
  ///
  /// In en, this message translates to:
  /// **'GOT IT'**
  String get playDailyGotIt;

  /// No description provided for @playDailyNoQuestions.
  ///
  /// In en, this message translates to:
  /// **'No challenge questions available yet'**
  String get playDailyNoQuestions;

  /// No description provided for @playDailyCompleteFewLessons.
  ///
  /// In en, this message translates to:
  /// **'Complete a few lessons first to build up the question pool.'**
  String get playDailyCompleteFewLessons;

  /// No description provided for @playWeakWordsEmpty.
  ///
  /// In en, this message translates to:
  /// **'Keep practicing — no weak words yet.\nWords you miss twice in 30 days will show up here.'**
  String get playWeakWordsEmpty;

  /// No description provided for @playWeakWordsTitleAppBar.
  ///
  /// In en, this message translates to:
  /// **'Weak Words'**
  String get playWeakWordsTitleAppBar;

  /// No description provided for @reviewContinueUpper.
  ///
  /// In en, this message translates to:
  /// **'CONTINUE'**
  String get reviewContinueUpper;

  /// No description provided for @reviewGotItUpper.
  ///
  /// In en, this message translates to:
  /// **'GOT IT'**
  String get reviewGotItUpper;

  /// No description provided for @reviewWeakWordsTitleAppBar.
  ///
  /// In en, this message translates to:
  /// **'Weak Words'**
  String get reviewWeakWordsTitleAppBar;

  /// No description provided for @reviewDoYouKnow.
  ///
  /// In en, this message translates to:
  /// **'Do you know this word?'**
  String get reviewDoYouKnow;

  /// No description provided for @reviewDontKnow.
  ///
  /// In en, this message translates to:
  /// **'Don\'t know'**
  String get reviewDontKnow;

  /// No description provided for @reviewKnowIt.
  ///
  /// In en, this message translates to:
  /// **'Know it'**
  String get reviewKnowIt;

  /// No description provided for @reviewEmptyTitle.
  ///
  /// In en, this message translates to:
  /// **'Review'**
  String get reviewEmptyTitle;

  /// No description provided for @reviewEmptyMessage.
  ///
  /// In en, this message translates to:
  /// **'You\'ve reviewed everything for now.'**
  String get reviewEmptyMessage;

  /// No description provided for @reviewDueMessage.
  ///
  /// In en, this message translates to:
  /// **'words are already due — pull to refresh'**
  String get reviewDueMessage;

  /// No description provided for @reviewNoItemsDue.
  ///
  /// In en, this message translates to:
  /// **'No items due for review'**
  String get reviewNoItemsDue;

  /// No description provided for @reviewDueCountMessage.
  ///
  /// In en, this message translates to:
  /// **'{dueCount} {dueMessage}'**
  String reviewDueCountMessage(int dueCount, String dueMessage);

  /// No description provided for @reviewCompletionTitle.
  ///
  /// In en, this message translates to:
  /// **'Session Complete!'**
  String get reviewCompletionTitle;

  /// No description provided for @reviewCompletionMessage.
  ///
  /// In en, this message translates to:
  /// **'You reviewed everything.'**
  String get reviewCompletionMessage;

  /// No description provided for @reviewReviewAppBarTitle.
  ///
  /// In en, this message translates to:
  /// **'Review'**
  String get reviewReviewAppBarTitle;

  /// No description provided for @reviewXpEarned.
  ///
  /// In en, this message translates to:
  /// **'+{xpEarned} XP'**
  String reviewXpEarned(int xpEarned);

  /// No description provided for @reviewGemsEarned.
  ///
  /// In en, this message translates to:
  /// **'+{gemsEarned} Gems'**
  String reviewGemsEarned(int gemsEarned);

  /// No description provided for @reviewReviewMore.
  ///
  /// In en, this message translates to:
  /// **'Review More'**
  String get reviewReviewMore;

  /// No description provided for @reviewSrsTitle.
  ///
  /// In en, this message translates to:
  /// **'Review'**
  String get reviewSrsTitle;

  /// No description provided for @reviewSrsSessionComplete.
  ///
  /// In en, this message translates to:
  /// **'Session Complete!'**
  String get reviewSrsSessionComplete;

  /// No description provided for @reviewSrsCompletionMessage.
  ///
  /// In en, this message translates to:
  /// **'You reviewed {sessionCount} items.'**
  String reviewSrsCompletionMessage(int sessionCount);

  /// No description provided for @reviewSrsAppBarTitle.
  ///
  /// In en, this message translates to:
  /// **'Review'**
  String get reviewSrsAppBarTitle;

  /// No description provided for @reviewSrsTtsSpeed.
  ///
  /// In en, this message translates to:
  /// **'{ttsSpeed} x'**
  String reviewSrsTtsSpeed(String ttsSpeed);

  /// No description provided for @reviewSrsTtsSpeedTooltip.
  ///
  /// In en, this message translates to:
  /// **'TTS speed'**
  String get reviewSrsTtsSpeedTooltip;

  /// No description provided for @reviewSrsProgress.
  ///
  /// In en, this message translates to:
  /// **'{currentIndex} / {queueLength}'**
  String reviewSrsProgress(int currentIndex, int queueLength);

  /// No description provided for @reviewSrsShowAnswer.
  ///
  /// In en, this message translates to:
  /// **'Show Answer'**
  String get reviewSrsShowAnswer;

  /// No description provided for @reviewSrsPlayPronunciation.
  ///
  /// In en, this message translates to:
  /// **'Play pronunciation'**
  String get reviewSrsPlayPronunciation;

  /// No description provided for @reviewSrsTapToReveal.
  ///
  /// In en, this message translates to:
  /// **'Tap to reveal meaning'**
  String get reviewSrsTapToReveal;

  /// No description provided for @reviewSrsLearnedIn.
  ///
  /// In en, this message translates to:
  /// **'Learned in: {lessonName}'**
  String reviewSrsLearnedIn(String lessonName);

  /// No description provided for @reviewSrsFirstSeen.
  ///
  /// In en, this message translates to:
  /// **'First seen: {wordId}'**
  String reviewSrsFirstSeen(String wordId);

  /// No description provided for @reviewSrsEntryNotFound.
  ///
  /// In en, this message translates to:
  /// **'Entry not found'**
  String get reviewSrsEntryNotFound;

  /// No description provided for @reviewSrsPronunciation.
  ///
  /// In en, this message translates to:
  /// **'/{pronunciation}/'**
  String reviewSrsPronunciation(String pronunciation);

  /// No description provided for @reviewMistakeReviewTitle.
  ///
  /// In en, this message translates to:
  /// **'Mistake Review'**
  String get reviewMistakeReviewTitle;

  /// No description provided for @reviewViewMistakeList.
  ///
  /// In en, this message translates to:
  /// **'View mistake list'**
  String get reviewViewMistakeList;

  /// No description provided for @reviewNoMistakes.
  ///
  /// In en, this message translates to:
  /// **'No mistakes to review.\nMistakes are recorded here automatically; practice up to 10 at a time.'**
  String get reviewNoMistakes;

  /// No description provided for @reviewMyMistakesTitle.
  ///
  /// In en, this message translates to:
  /// **'My Mistakes'**
  String get reviewMyMistakesTitle;

  /// No description provided for @reviewNoMistakesRecorded.
  ///
  /// In en, this message translates to:
  /// **'No mistakes recorded'**
  String get reviewNoMistakesRecorded;

  /// No description provided for @reviewKeepItUp.
  ///
  /// In en, this message translates to:
  /// **'Keep it up!'**
  String get reviewKeepItUp;

  /// No description provided for @reviewMistakesLabel.
  ///
  /// In en, this message translates to:
  /// **'Mistakes'**
  String get reviewMistakesLabel;

  /// No description provided for @reviewWordsLabel.
  ///
  /// In en, this message translates to:
  /// **'Words'**
  String get reviewWordsLabel;

  /// No description provided for @reviewGrammarLabel.
  ///
  /// In en, this message translates to:
  /// **'Grammar'**
  String get reviewGrammarLabel;

  /// No description provided for @reviewUnknownQuestion.
  ///
  /// In en, this message translates to:
  /// **'Unknown question'**
  String get reviewUnknownQuestion;

  /// No description provided for @reviewReviewGrammar.
  ///
  /// In en, this message translates to:
  /// **'Review grammar'**
  String get reviewReviewGrammar;

  /// No description provided for @reviewGotItNow.
  ///
  /// In en, this message translates to:
  /// **'I got it now'**
  String get reviewGotItNow;

  /// No description provided for @reviewYourAnswer.
  ///
  /// In en, this message translates to:
  /// **'Your answer'**
  String get reviewYourAnswer;

  /// No description provided for @reviewCorrectAnswer.
  ///
  /// In en, this message translates to:
  /// **'Correct answer'**
  String get reviewCorrectAnswer;

  /// No description provided for @reviewDash.
  ///
  /// In en, this message translates to:
  /// **'—'**
  String get reviewDash;

  /// No description provided for @reviewGrammarChip.
  ///
  /// In en, this message translates to:
  /// **'Grammar: {title}'**
  String reviewGrammarChip(String title);

  /// No description provided for @reviewPracticeTitle.
  ///
  /// In en, this message translates to:
  /// **'Practice'**
  String get reviewPracticeTitle;

  /// No description provided for @reviewCannotPractice.
  ///
  /// In en, this message translates to:
  /// **'This mistake cannot be practiced.'**
  String get reviewCannotPractice;

  /// No description provided for @reviewPracticeMistakeTitle.
  ///
  /// In en, this message translates to:
  /// **'Practice Mistake'**
  String get reviewPracticeMistakeTitle;

  /// No description provided for @reviewGrammarReviewTitle.
  ///
  /// In en, this message translates to:
  /// **'Grammar Review'**
  String get reviewGrammarReviewTitle;

  /// No description provided for @reviewGrammarEmptyMessage.
  ///
  /// In en, this message translates to:
  /// **'You\'ve reviewed everything for now.'**
  String get reviewGrammarEmptyMessage;

  /// No description provided for @reviewGrammarDueMessage.
  ///
  /// In en, this message translates to:
  /// **'points are already due — refresh to load them'**
  String get reviewGrammarDueMessage;

  /// No description provided for @reviewGrammarSessionComplete.
  ///
  /// In en, this message translates to:
  /// **'Session Complete!'**
  String get reviewGrammarSessionComplete;

  /// No description provided for @reviewGrammarCompletionMessage.
  ///
  /// In en, this message translates to:
  /// **'You reviewed {sessionCount} grammar points.'**
  String reviewGrammarCompletionMessage(int sessionCount);

  /// No description provided for @reviewGrammarAppBarTitle.
  ///
  /// In en, this message translates to:
  /// **'Grammar Review'**
  String get reviewGrammarAppBarTitle;

  /// No description provided for @reviewGrammarProgress.
  ///
  /// In en, this message translates to:
  /// **'{currentIndex} / {queueLength}'**
  String reviewGrammarProgress(int currentIndex, int queueLength);

  /// No description provided for @reviewGrammarPracticeLabel.
  ///
  /// In en, this message translates to:
  /// **'Practice {practiceIndex} / {practiceLength}'**
  String reviewGrammarPracticeLabel(int practiceIndex, int practiceLength);

  /// No description provided for @reviewGrammarDoYouUnderstand.
  ///
  /// In en, this message translates to:
  /// **'Do you understand this grammar point?'**
  String get reviewGrammarDoYouUnderstand;

  /// No description provided for @reviewGrammarNextPractice.
  ///
  /// In en, this message translates to:
  /// **'Next practice'**
  String get reviewGrammarNextPractice;

  /// No description provided for @reviewGrammarRateGrammar.
  ///
  /// In en, this message translates to:
  /// **'Rate this grammar point'**
  String get reviewGrammarRateGrammar;

  /// No description provided for @reviewGrammarShowExplanation.
  ///
  /// In en, this message translates to:
  /// **'Show Explanation'**
  String get reviewGrammarShowExplanation;

  /// No description provided for @reviewGrammarLearnedIn.
  ///
  /// In en, this message translates to:
  /// **'Learned in: {lessonName}'**
  String reviewGrammarLearnedIn(String lessonName);

  /// No description provided for @reviewGrammarFirstSeen.
  ///
  /// In en, this message translates to:
  /// **'First seen: {wordId}'**
  String reviewGrammarFirstSeen(String wordId);

  /// No description provided for @reviewGrammarTapToReveal.
  ///
  /// In en, this message translates to:
  /// **'Tap to reveal explanation'**
  String get reviewGrammarTapToReveal;

  /// No description provided for @reviewGrammarPointNotFound.
  ///
  /// In en, this message translates to:
  /// **'Grammar point not found'**
  String get reviewGrammarPointNotFound;

  /// No description provided for @lessonFlipCardCaption.
  ///
  /// In en, this message translates to:
  /// **'FLIP CARD'**
  String get lessonFlipCardCaption;

  /// No description provided for @lessonShowAnswer.
  ///
  /// In en, this message translates to:
  /// **'Show Answer'**
  String get lessonShowAnswer;

  /// No description provided for @lessonTapToReveal.
  ///
  /// In en, this message translates to:
  /// **'Tap below to reveal the answer'**
  String get lessonTapToReveal;

  /// No description provided for @lessonHowWellDidYouKnow.
  ///
  /// In en, this message translates to:
  /// **'How well did you know this?'**
  String get lessonHowWellDidYouKnow;

  /// No description provided for @lessonAgain.
  ///
  /// In en, this message translates to:
  /// **'Again'**
  String get lessonAgain;

  /// No description provided for @lessonHard.
  ///
  /// In en, this message translates to:
  /// **'Hard'**
  String get lessonHard;

  /// No description provided for @lessonGood.
  ///
  /// In en, this message translates to:
  /// **'Good'**
  String get lessonGood;

  /// No description provided for @lessonEasy.
  ///
  /// In en, this message translates to:
  /// **'Easy'**
  String get lessonEasy;

  /// No description provided for @lessonPlayAudioLabel.
  ///
  /// In en, this message translates to:
  /// **'Play audio'**
  String get lessonPlayAudioLabel;

  /// No description provided for @lessonFillBlankCaption.
  ///
  /// In en, this message translates to:
  /// **'Fill in the blank'**
  String get lessonFillBlankCaption;

  /// No description provided for @lessonFillBlankHint.
  ///
  /// In en, this message translates to:
  /// **'___'**
  String get lessonFillBlankHint;

  /// No description provided for @lessonCorrectAnswer.
  ///
  /// In en, this message translates to:
  /// **'Correct answer'**
  String get lessonCorrectAnswer;

  /// No description provided for @lessonListenAndPickCaption.
  ///
  /// In en, this message translates to:
  /// **'Listen and pick'**
  String get lessonListenAndPickCaption;

  /// No description provided for @lessonSummaryCaption.
  ///
  /// In en, this message translates to:
  /// **'Summary'**
  String get lessonSummaryCaption;

  /// No description provided for @lessonListenToSummary.
  ///
  /// In en, this message translates to:
  /// **'Listen to the summary'**
  String get lessonListenToSummary;

  /// No description provided for @lessonTapToReplay.
  ///
  /// In en, this message translates to:
  /// **'Tap the speaker to replay'**
  String get lessonTapToReplay;

  /// No description provided for @lessonTapToListen.
  ///
  /// In en, this message translates to:
  /// **'Tap the speaker to listen'**
  String get lessonTapToListen;

  /// No description provided for @lessonMultipleChoiceCaption.
  ///
  /// In en, this message translates to:
  /// **'Multiple choice'**
  String get lessonMultipleChoiceCaption;

  /// No description provided for @lessonSelectAllCaption.
  ///
  /// In en, this message translates to:
  /// **'Select all that apply'**
  String get lessonSelectAllCaption;

  /// No description provided for @lessonSelectAtLeast.
  ///
  /// In en, this message translates to:
  /// **'Select at least {min} ({count} selected)'**
  String lessonSelectAtLeast(int min, int count);

  /// No description provided for @lessonSelectExact.
  ///
  /// In en, this message translates to:
  /// **'Select {min} ({count} selected)'**
  String lessonSelectExact(int min, int count);

  /// No description provided for @lessonSelectRange.
  ///
  /// In en, this message translates to:
  /// **'Select {min}–{max} ({count} selected)'**
  String lessonSelectRange(int min, int max, int count);

  /// No description provided for @lessonReadingComprehensionCaption.
  ///
  /// In en, this message translates to:
  /// **'Reading comprehension'**
  String get lessonReadingComprehensionCaption;

  /// No description provided for @lessonShortAnswerCaption.
  ///
  /// In en, this message translates to:
  /// **'Short answer'**
  String get lessonShortAnswerCaption;

  /// No description provided for @lessonTypeYourAnswer.
  ///
  /// In en, this message translates to:
  /// **'Type your answer...'**
  String get lessonTypeYourAnswer;

  /// No description provided for @lessonTrueFalseCaption.
  ///
  /// In en, this message translates to:
  /// **'True or False'**
  String get lessonTrueFalseCaption;

  /// No description provided for @lessonTrue.
  ///
  /// In en, this message translates to:
  /// **'True'**
  String get lessonTrue;

  /// No description provided for @lessonFalse.
  ///
  /// In en, this message translates to:
  /// **'False'**
  String get lessonFalse;

  /// No description provided for @lessonArrangeWordsCaption.
  ///
  /// In en, this message translates to:
  /// **'Arrange the words'**
  String get lessonArrangeWordsCaption;

  /// No description provided for @lessonTapRightOrder.
  ///
  /// In en, this message translates to:
  /// **'Tap the words in the right order'**
  String get lessonTapRightOrder;

  /// No description provided for @lessonWordBank.
  ///
  /// In en, this message translates to:
  /// **'Word bank'**
  String get lessonWordBank;

  /// No description provided for @lessonCorrectOrder.
  ///
  /// In en, this message translates to:
  /// **'Correct order'**
  String get lessonCorrectOrder;

  /// No description provided for @lessonTapWordToStart.
  ///
  /// In en, this message translates to:
  /// **'Tap a word below to start'**
  String get lessonTapWordToStart;

  /// No description provided for @lessonSpeakTerm.
  ///
  /// In en, this message translates to:
  /// **'Speak {term}'**
  String lessonSpeakTerm(String term);

  /// No description provided for @lessonSpeakContextSentence.
  ///
  /// In en, this message translates to:
  /// **'Speak context sentence'**
  String get lessonSpeakContextSentence;

  /// No description provided for @lessonTapToContinue.
  ///
  /// In en, this message translates to:
  /// **'Tap to continue'**
  String get lessonTapToContinue;

  /// No description provided for @lessonItemNotLoaded.
  ///
  /// In en, this message translates to:
  /// **'This item could not be loaded.'**
  String get lessonItemNotLoaded;

  /// No description provided for @lessonTranslateCaption.
  ///
  /// In en, this message translates to:
  /// **'Translate this sentence'**
  String get lessonTranslateCaption;

  /// No description provided for @lessonTypeTranslation.
  ///
  /// In en, this message translates to:
  /// **'Type the translation...'**
  String get lessonTypeTranslation;

  /// No description provided for @lessonCorrectTranslation.
  ///
  /// In en, this message translates to:
  /// **'Correct translation'**
  String get lessonCorrectTranslation;

  /// No description provided for @lessonTypeWhatYouHearCaption.
  ///
  /// In en, this message translates to:
  /// **'Type what you hear'**
  String get lessonTypeWhatYouHearCaption;

  /// No description provided for @lessonTypeHere.
  ///
  /// In en, this message translates to:
  /// **'Type here...'**
  String get lessonTypeHere;

  /// No description provided for @lessonCompleteTitle1.
  ///
  /// In en, this message translates to:
  /// **'Lesson Complete!'**
  String get lessonCompleteTitle1;

  /// No description provided for @lessonCompleteSubtitle1.
  ///
  /// In en, this message translates to:
  /// **'Brilliant focus. You cleared this lesson.'**
  String get lessonCompleteSubtitle1;

  /// No description provided for @lessonCompleteTitle2.
  ///
  /// In en, this message translates to:
  /// **'That Was Fast!'**
  String get lessonCompleteTitle2;

  /// No description provided for @lessonCompleteSubtitle2.
  ///
  /// In en, this message translates to:
  /// **'You are climbing fast. Keep the streak alive.'**
  String get lessonCompleteSubtitle2;

  /// No description provided for @lessonCompleteTitle3.
  ///
  /// In en, this message translates to:
  /// **'Excellent Work!'**
  String get lessonCompleteTitle3;

  /// No description provided for @lessonCompleteSubtitle3.
  ///
  /// In en, this message translates to:
  /// **'Every lesson gets you closer to mastery.'**
  String get lessonCompleteSubtitle3;

  /// No description provided for @lessonPerfectLesson.
  ///
  /// In en, this message translates to:
  /// **'Perfect lesson! All answers correct.'**
  String get lessonPerfectLesson;

  /// No description provided for @lessonCorrect.
  ///
  /// In en, this message translates to:
  /// **'Correct'**
  String get lessonCorrect;

  /// No description provided for @lessonWrong.
  ///
  /// In en, this message translates to:
  /// **'Wrong'**
  String get lessonWrong;

  /// No description provided for @lessonTime.
  ///
  /// In en, this message translates to:
  /// **'Time'**
  String get lessonTime;

  /// No description provided for @lessonXp.
  ///
  /// In en, this message translates to:
  /// **'XP'**
  String get lessonXp;

  /// No description provided for @lessonAnswerBreakdown.
  ///
  /// In en, this message translates to:
  /// **'Answer breakdown'**
  String get lessonAnswerBreakdown;

  /// No description provided for @lessonResultsCount.
  ///
  /// In en, this message translates to:
  /// **'{correctCount} / {totalCount}'**
  String lessonResultsCount(int correctCount, int totalCount);

  /// No description provided for @lessonBackToCourses.
  ///
  /// In en, this message translates to:
  /// **'Back to Courses'**
  String get lessonBackToCourses;

  /// No description provided for @lessonAccuracy.
  ///
  /// In en, this message translates to:
  /// **'accuracy'**
  String get lessonAccuracy;

  /// No description provided for @lessonPercentValue.
  ///
  /// In en, this message translates to:
  /// **'{percent}%'**
  String lessonPercentValue(int percent);

  /// No description provided for @lessonQuestionResult.
  ///
  /// In en, this message translates to:
  /// **'{index}. {prompt}'**
  String lessonQuestionResult(int index, String prompt);

  /// No description provided for @lessonQuestionAnswer.
  ///
  /// In en, this message translates to:
  /// **'Answer: {correctAnswer}'**
  String lessonQuestionAnswer(String correctAnswer);

  /// No description provided for @lessonNotYet.
  ///
  /// In en, this message translates to:
  /// **'Not Yet'**
  String get lessonNotYet;

  /// No description provided for @lessonMasteryMessage.
  ///
  /// In en, this message translates to:
  /// **'You got {correct} / {total} ({accuracyPercent}%). You need 80% to pass. Try again!'**
  String lessonMasteryMessage(int correct, int total, int accuracyPercent);

  /// No description provided for @lessonTryAgain.
  ///
  /// In en, this message translates to:
  /// **'Try Again'**
  String get lessonTryAgain;

  /// No description provided for @lessonDurationSeconds.
  ///
  /// In en, this message translates to:
  /// **'{seconds}s'**
  String lessonDurationSeconds(int seconds);

  /// No description provided for @lessonDurationMinutes.
  ///
  /// In en, this message translates to:
  /// **'{minutes}m {seconds}s'**
  String lessonDurationMinutes(int minutes, int seconds);

  /// No description provided for @lessonAiHelperTooltip.
  ///
  /// In en, this message translates to:
  /// **'AI lesson helper'**
  String get lessonAiHelperTooltip;

  /// No description provided for @lessonAiHintTooltip.
  ///
  /// In en, this message translates to:
  /// **'AI hint'**
  String get lessonAiHintTooltip;

  /// No description provided for @lessonNoContent.
  ///
  /// In en, this message translates to:
  /// **'No content'**
  String get lessonNoContent;

  /// No description provided for @lessonLessonFallback.
  ///
  /// In en, this message translates to:
  /// **'Lesson'**
  String get lessonLessonFallback;

  /// No description provided for @lessonCouldNotLoadLesson.
  ///
  /// In en, this message translates to:
  /// **'Could not load lesson'**
  String get lessonCouldNotLoadLesson;

  /// No description provided for @aiNotConfiguredTitle.
  ///
  /// In en, this message translates to:
  /// **'AI not configured'**
  String get aiNotConfiguredTitle;

  /// No description provided for @aiNotConfiguredMessageLesson.
  ///
  /// In en, this message translates to:
  /// **'Please fill in Base URL / API Key / Model under Settings → Learning → AI API Configuration before using AI hints.'**
  String get aiNotConfiguredMessageLesson;

  /// No description provided for @aiGoToSettings.
  ///
  /// In en, this message translates to:
  /// **'Go to settings'**
  String get aiGoToSettings;

  /// No description provided for @aiCourseDesignerTitle.
  ///
  /// In en, this message translates to:
  /// **'AI Course Designer'**
  String get aiCourseDesignerTitle;

  /// No description provided for @aiCourseParametersTooltip.
  ///
  /// In en, this message translates to:
  /// **'Course parameters'**
  String get aiCourseParametersTooltip;

  /// No description provided for @aiCourseParametersTitle.
  ///
  /// In en, this message translates to:
  /// **'Course Parameters'**
  String get aiCourseParametersTitle;

  /// No description provided for @aiTargetLanguageLabel.
  ///
  /// In en, this message translates to:
  /// **'Target language'**
  String get aiTargetLanguageLabel;

  /// No description provided for @aiSourceLanguageLabel.
  ///
  /// In en, this message translates to:
  /// **'Source language'**
  String get aiSourceLanguageLabel;

  /// No description provided for @aiTopicLabel.
  ///
  /// In en, this message translates to:
  /// **'Topic'**
  String get aiTopicLabel;

  /// No description provided for @aiLevelLabel.
  ///
  /// In en, this message translates to:
  /// **'Level'**
  String get aiLevelLabel;

  /// No description provided for @aiUnitsLabel.
  ///
  /// In en, this message translates to:
  /// **'Units'**
  String get aiUnitsLabel;

  /// No description provided for @aiLessonsPerUnitLabel.
  ///
  /// In en, this message translates to:
  /// **'Lessons/unit'**
  String get aiLessonsPerUnitLabel;

  /// No description provided for @aiTemplateLabel.
  ///
  /// In en, this message translates to:
  /// **'Template'**
  String get aiTemplateLabel;

  /// No description provided for @aiGenreBatchTitle.
  ///
  /// In en, this message translates to:
  /// **'Genre batch'**
  String get aiGenreBatchTitle;

  /// No description provided for @aiGenreBatchSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Use [genre] tags for multi-template batch generation'**
  String get aiGenreBatchSubtitle;

  /// No description provided for @aiGroundedGenerationTitle.
  ///
  /// In en, this message translates to:
  /// **'Grounded generation'**
  String get aiGroundedGenerationTitle;

  /// No description provided for @aiGroundedGenerationSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Reuse existing vocabulary, expressions, and grammar points'**
  String get aiGroundedGenerationSubtitle;

  /// No description provided for @aiExtraInstructionsLabel.
  ///
  /// In en, this message translates to:
  /// **'Extra instructions (optional)'**
  String get aiExtraInstructionsLabel;

  /// No description provided for @aiEmptyHintWish.
  ///
  /// In en, this message translates to:
  /// **'Tell the AI what course you want. For example:\n\"I want to teach Turkish travel phrases — greetings and ordering food.\"'**
  String get aiEmptyHintWish;

  /// No description provided for @aiErrorBubble.
  ///
  /// In en, this message translates to:
  /// **'Error: {error}'**
  String aiErrorBubble(Object error);

  /// No description provided for @aiCourseGenerated.
  ///
  /// In en, this message translates to:
  /// **'Course generated'**
  String get aiCourseGenerated;

  /// No description provided for @aiAiExplanation.
  ///
  /// In en, this message translates to:
  /// **'AI explanation: {explanation}'**
  String aiAiExplanation(String explanation);

  /// No description provided for @aiSaveToCourseTree.
  ///
  /// In en, this message translates to:
  /// **'Save to Course Tree'**
  String get aiSaveToCourseTree;

  /// No description provided for @aiTypeIdea.
  ///
  /// In en, this message translates to:
  /// **'Type your idea…'**
  String get aiTypeIdea;

  /// No description provided for @aiSwipeToFinalize.
  ///
  /// In en, this message translates to:
  /// **'Swipe to finalize'**
  String get aiSwipeToFinalize;

  /// No description provided for @aiReleaseToFinalize.
  ///
  /// In en, this message translates to:
  /// **'Release to finalize'**
  String get aiReleaseToFinalize;

  /// No description provided for @aiCourseSaved.
  ///
  /// In en, this message translates to:
  /// **'Course saved to database.'**
  String get aiCourseSaved;

  /// No description provided for @aiSaveFailed.
  ///
  /// In en, this message translates to:
  /// **'Save failed: {error}'**
  String aiSaveFailed(Object error);

  /// No description provided for @aiTextbookImportTitle.
  ///
  /// In en, this message translates to:
  /// **'Import from Textbook'**
  String get aiTextbookImportTitle;

  /// No description provided for @aiTextbookNotConfiguredMessage.
  ///
  /// In en, this message translates to:
  /// **'Please fill in Base URL / API Key / Model under Settings → AI API Configuration first.'**
  String get aiTextbookNotConfiguredMessage;

  /// No description provided for @aiTextbookTargetLanguageLabel.
  ///
  /// In en, this message translates to:
  /// **'Target language'**
  String get aiTextbookTargetLanguageLabel;

  /// No description provided for @aiTextbookSourceLanguageLabel.
  ///
  /// In en, this message translates to:
  /// **'Source language'**
  String get aiTextbookSourceLanguageLabel;

  /// No description provided for @aiTextbookLevelLabel.
  ///
  /// In en, this message translates to:
  /// **'Level'**
  String get aiTextbookLevelLabel;

  /// No description provided for @aiTextbookImportStrategyLabel.
  ///
  /// In en, this message translates to:
  /// **'Import strategy'**
  String get aiTextbookImportStrategyLabel;

  /// No description provided for @aiTextbookPickPrompt.
  ///
  /// In en, this message translates to:
  /// **'Pick a markdown or text file to import as course sections.'**
  String get aiTextbookPickPrompt;

  /// No description provided for @aiTextbookPickFile.
  ///
  /// In en, this message translates to:
  /// **'Pick file'**
  String get aiTextbookPickFile;

  /// No description provided for @aiTextbookSelected.
  ///
  /// In en, this message translates to:
  /// **'Selected: {fileName}'**
  String aiTextbookSelected(String fileName);

  /// No description provided for @aiTextbookParsing.
  ///
  /// In en, this message translates to:
  /// **'Parsing file…'**
  String get aiTextbookParsing;

  /// No description provided for @aiTextbookExtracting.
  ///
  /// In en, this message translates to:
  /// **'Extracting knowledge…'**
  String get aiTextbookExtracting;

  /// No description provided for @aiTextbookReviewChapters.
  ///
  /// In en, this message translates to:
  /// **'Review chapters'**
  String get aiTextbookReviewChapters;

  /// No description provided for @aiTextbookChapterChars.
  ///
  /// In en, this message translates to:
  /// **'{length} chars'**
  String aiTextbookChapterChars(int length);

  /// No description provided for @aiTextbookReviewKnowledge.
  ///
  /// In en, this message translates to:
  /// **'Review extracted knowledge'**
  String get aiTextbookReviewKnowledge;

  /// No description provided for @aiTextbookWords.
  ///
  /// In en, this message translates to:
  /// **'Words: {count}'**
  String aiTextbookWords(int count);

  /// No description provided for @aiTextbookExpressions.
  ///
  /// In en, this message translates to:
  /// **'Expressions: {count}'**
  String aiTextbookExpressions(int count);

  /// No description provided for @aiTextbookGrammar.
  ///
  /// In en, this message translates to:
  /// **'Grammar: {count}'**
  String aiTextbookGrammar(int count);

  /// No description provided for @aiTextbookImportComplete.
  ///
  /// In en, this message translates to:
  /// **'Import complete!'**
  String get aiTextbookImportComplete;

  /// No description provided for @aiTextbookErrorFooter.
  ///
  /// In en, this message translates to:
  /// **'Error: {error}'**
  String aiTextbookErrorFooter(Object error);

  /// No description provided for @aiTextbookExtractKnowledge.
  ///
  /// In en, this message translates to:
  /// **'Extract knowledge'**
  String get aiTextbookExtractKnowledge;

  /// No description provided for @aiTextbookImportSections.
  ///
  /// In en, this message translates to:
  /// **'Import sections'**
  String get aiTextbookImportSections;

  /// No description provided for @aiLessonHelperTitle.
  ///
  /// In en, this message translates to:
  /// **'AI Lesson Helper'**
  String get aiLessonHelperTitle;

  /// No description provided for @aiLessonHelperHint.
  ///
  /// In en, this message translates to:
  /// **'e.g. \"Make this easier\" or \"Add 3 more exercises\"'**
  String get aiLessonHelperHint;

  /// No description provided for @aiLessonHelperInstructionLabel.
  ///
  /// In en, this message translates to:
  /// **'Instruction'**
  String get aiLessonHelperInstructionLabel;

  /// No description provided for @aiLessonHelperChipMakeEasier.
  ///
  /// In en, this message translates to:
  /// **'Make easier'**
  String get aiLessonHelperChipMakeEasier;

  /// No description provided for @aiLessonHelperChipMakeHarder.
  ///
  /// In en, this message translates to:
  /// **'Make harder'**
  String get aiLessonHelperChipMakeHarder;

  /// No description provided for @aiLessonHelperChipAddExercises.
  ///
  /// In en, this message translates to:
  /// **'Add 3 exercises'**
  String get aiLessonHelperChipAddExercises;

  /// No description provided for @aiLessonHelperChipListening.
  ///
  /// In en, this message translates to:
  /// **'Change to listening'**
  String get aiLessonHelperChipListening;

  /// No description provided for @aiLessonHelperChipPolish.
  ///
  /// In en, this message translates to:
  /// **'Polish prompts'**
  String get aiLessonHelperChipPolish;

  /// No description provided for @aiLessonHelperError.
  ///
  /// In en, this message translates to:
  /// **'Something went wrong: {error}'**
  String aiLessonHelperError(Object error);

  /// No description provided for @aiLessonHelperErrorUnknown.
  ///
  /// In en, this message translates to:
  /// **'Something went wrong: Unknown error'**
  String get aiLessonHelperErrorUnknown;

  /// No description provided for @aiLessonHelperPreviewTitle.
  ///
  /// In en, this message translates to:
  /// **'Preview'**
  String get aiLessonHelperPreviewTitle;

  /// No description provided for @aiLessonHelperTransformationReady.
  ///
  /// In en, this message translates to:
  /// **'Transformation ready. Tap Apply to update the lesson.'**
  String get aiLessonHelperTransformationReady;

  /// No description provided for @aiLessonHelperTransform.
  ///
  /// In en, this message translates to:
  /// **'Transform'**
  String get aiLessonHelperTransform;

  /// No description provided for @aiLessonHelperInvalidJson.
  ///
  /// In en, this message translates to:
  /// **'Invalid lesson JSON: {error}'**
  String aiLessonHelperInvalidJson(Object error);

  /// No description provided for @aiLessonHelperLessonUpdated.
  ///
  /// In en, this message translates to:
  /// **'Lesson updated.'**
  String get aiLessonHelperLessonUpdated;

  /// No description provided for @aiLessonHelperUpdateFailed.
  ///
  /// In en, this message translates to:
  /// **'Update failed: {error}'**
  String aiLessonHelperUpdateFailed(Object error);

  /// No description provided for @aiTutorTitle.
  ///
  /// In en, this message translates to:
  /// **'AI Tutor'**
  String get aiTutorTitle;

  /// No description provided for @aiTutorTitleWithType.
  ///
  /// In en, this message translates to:
  /// **'AI Tutor · {typeLabel}'**
  String aiTutorTitleWithType(String typeLabel);

  /// No description provided for @aiEmptyHintTutor.
  ///
  /// In en, this message translates to:
  /// **'AI is preparing an explanation for this question…'**
  String get aiEmptyHintTutor;

  /// No description provided for @aiThinking.
  ///
  /// In en, this message translates to:
  /// **'AI is thinking…'**
  String get aiThinking;

  /// No description provided for @aiAskMore.
  ///
  /// In en, this message translates to:
  /// **'Ask more…'**
  String get aiAskMore;

  /// No description provided for @aiHintTitle.
  ///
  /// In en, this message translates to:
  /// **'AI hint'**
  String get aiHintTitle;

  /// No description provided for @aiHintTitleWithType.
  ///
  /// In en, this message translates to:
  /// **'AI hint · {typeLabel}'**
  String aiHintTitleWithType(String typeLabel);

  /// No description provided for @aiHintError.
  ///
  /// In en, this message translates to:
  /// **'Something went wrong: {error}'**
  String aiHintError(Object error);

  /// No description provided for @aiHintErrorUnknown.
  ///
  /// In en, this message translates to:
  /// **'Something went wrong: Unknown error'**
  String get aiHintErrorUnknown;

  /// No description provided for @aiHintOpenChat.
  ///
  /// In en, this message translates to:
  /// **'Open chat'**
  String get aiHintOpenChat;

  /// No description provided for @ankiImportTitle.
  ///
  /// In en, this message translates to:
  /// **'Import Anki Deck'**
  String get ankiImportTitle;

  /// No description provided for @ankiImportDialogTitle.
  ///
  /// In en, this message translates to:
  /// **'Import Anki Deck'**
  String get ankiImportDialogTitle;

  /// No description provided for @ankiImportSelectTitle.
  ///
  /// In en, this message translates to:
  /// **'Import an Anki Deck'**
  String get ankiImportSelectTitle;

  /// No description provided for @ankiImportSelectSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Select a .apkg or .colpkg file exported from Anki'**
  String get ankiImportSelectSubtitle;

  /// No description provided for @ankiChooseFile.
  ///
  /// In en, this message translates to:
  /// **'Choose File'**
  String get ankiChooseFile;

  /// No description provided for @ankiParsing.
  ///
  /// In en, this message translates to:
  /// **'Parsing Anki collection...'**
  String get ankiParsing;

  /// No description provided for @ankiCollectionSummary.
  ///
  /// In en, this message translates to:
  /// **'Collection Summary'**
  String get ankiCollectionSummary;

  /// No description provided for @ankiDecksLabel.
  ///
  /// In en, this message translates to:
  /// **'Decks'**
  String get ankiDecksLabel;

  /// No description provided for @ankiNotesLabel.
  ///
  /// In en, this message translates to:
  /// **'Notes'**
  String get ankiNotesLabel;

  /// No description provided for @ankiCardsLabel.
  ///
  /// In en, this message translates to:
  /// **'Cards'**
  String get ankiCardsLabel;

  /// No description provided for @ankiMediaFilesLabel.
  ///
  /// In en, this message translates to:
  /// **'Media files'**
  String get ankiMediaFilesLabel;

  /// No description provided for @ankiDeckStructure.
  ///
  /// In en, this message translates to:
  /// **'Deck Structure'**
  String get ankiDeckStructure;

  /// No description provided for @ankiDeckCardCount.
  ///
  /// In en, this message translates to:
  /// **'{cardCount} cards'**
  String ankiDeckCardCount(int cardCount);

  /// No description provided for @ankiNotetypeMapping.
  ///
  /// In en, this message translates to:
  /// **'Notetype Mapping'**
  String get ankiNotetypeMapping;

  /// No description provided for @ankiCollisionReport.
  ///
  /// In en, this message translates to:
  /// **'Collision Report'**
  String get ankiCollisionReport;

  /// No description provided for @ankiNewCards.
  ///
  /// In en, this message translates to:
  /// **'New cards'**
  String get ankiNewCards;

  /// No description provided for @ankiExistingCards.
  ///
  /// In en, this message translates to:
  /// **'Already existing'**
  String get ankiExistingCards;

  /// No description provided for @ankiImportStrategy.
  ///
  /// In en, this message translates to:
  /// **'Import Strategy'**
  String get ankiImportStrategy;

  /// No description provided for @ankiImportComplete.
  ///
  /// In en, this message translates to:
  /// **'Import Complete!'**
  String get ankiImportComplete;

  /// No description provided for @ankiCardsImported.
  ///
  /// In en, this message translates to:
  /// **'{cardCount} cards imported'**
  String ankiCardsImported(int cardCount);

  /// No description provided for @ankiLessonsCreated.
  ///
  /// In en, this message translates to:
  /// **'{lessonCount} lessons created'**
  String ankiLessonsCreated(int lessonCount);

  /// No description provided for @ankiVocabAdded.
  ///
  /// In en, this message translates to:
  /// **'{wordEntryCount} vocabulary entries added'**
  String ankiVocabAdded(int wordEntryCount);

  /// No description provided for @ankiPickFileError.
  ///
  /// In en, this message translates to:
  /// **'Please select an .apkg or .colpkg file.'**
  String get ankiPickFileError;

  /// No description provided for @ankiPickFileFailed.
  ///
  /// In en, this message translates to:
  /// **'Failed to pick file: {error}'**
  String ankiPickFileFailed(Object error);

  /// No description provided for @ankiParseFailed.
  ///
  /// In en, this message translates to:
  /// **'Failed to parse: {error}'**
  String ankiParseFailed(Object error);

  /// No description provided for @ankiPreparingImport.
  ///
  /// In en, this message translates to:
  /// **'Preparing import...'**
  String get ankiPreparingImport;

  /// No description provided for @ankiAssemblingCourse.
  ///
  /// In en, this message translates to:
  /// **'Assembling course tree...'**
  String get ankiAssemblingCourse;

  /// No description provided for @ankiMigratingSrs.
  ///
  /// In en, this message translates to:
  /// **'Migrating SRS state...'**
  String get ankiMigratingSrs;

  /// No description provided for @ankiSavingMetadata.
  ///
  /// In en, this message translates to:
  /// **'Saving import metadata...'**
  String get ankiSavingMetadata;

  /// No description provided for @ankiImportFailed.
  ///
  /// In en, this message translates to:
  /// **'Import failed: {error}'**
  String ankiImportFailed(Object error);

  /// No description provided for @ankiStrategyMerge.
  ///
  /// In en, this message translates to:
  /// **'Merge'**
  String get ankiStrategyMerge;

  /// No description provided for @ankiStrategySkipExisting.
  ///
  /// In en, this message translates to:
  /// **'Skip Existing'**
  String get ankiStrategySkipExisting;

  /// No description provided for @ankiStrategyForceReplace.
  ///
  /// In en, this message translates to:
  /// **'Force Replace'**
  String get ankiStrategyForceReplace;

  /// No description provided for @ankiStrategyAppendAsNew.
  ///
  /// In en, this message translates to:
  /// **'Append as New'**
  String get ankiStrategyAppendAsNew;

  /// No description provided for @ankiStrategyMergeDesc.
  ///
  /// In en, this message translates to:
  /// **'Update existing cards, add new ones'**
  String get ankiStrategyMergeDesc;

  /// No description provided for @ankiStrategySkipExistingDesc.
  ///
  /// In en, this message translates to:
  /// **'Only import cards that don\'t exist'**
  String get ankiStrategySkipExistingDesc;

  /// No description provided for @ankiStrategyForceReplaceDesc.
  ///
  /// In en, this message translates to:
  /// **'Replace all existing data'**
  String get ankiStrategyForceReplaceDesc;

  /// No description provided for @ankiStrategyAppendAsNewDesc.
  ///
  /// In en, this message translates to:
  /// **'Add all as new (with suffix)'**
  String get ankiStrategyAppendAsNewDesc;

  /// No description provided for @ankiReviewTitle.
  ///
  /// In en, this message translates to:
  /// **'Anki Review'**
  String get ankiReviewTitle;

  /// No description provided for @ankiNoCardsDue.
  ///
  /// In en, this message translates to:
  /// **'No Anki cards due for review right now.'**
  String get ankiNoCardsDue;

  /// No description provided for @ankiReviewScreenTitle.
  ///
  /// In en, this message translates to:
  /// **'Anki Review'**
  String get ankiReviewScreenTitle;

  /// No description provided for @ankiImportNewDeck.
  ///
  /// In en, this message translates to:
  /// **'Import new deck'**
  String get ankiImportNewDeck;

  /// No description provided for @ankiCardsDueReview.
  ///
  /// In en, this message translates to:
  /// **'{totalDue} cards due for review'**
  String ankiCardsDueReview(int totalDue);

  /// No description provided for @ankiReviewAll.
  ///
  /// In en, this message translates to:
  /// **'Review All'**
  String get ankiReviewAll;

  /// No description provided for @ankiNoDecksTitle.
  ///
  /// In en, this message translates to:
  /// **'No Anki Decks Imported'**
  String get ankiNoDecksTitle;

  /// No description provided for @ankiNoDecksSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Import an .apkg file to start reviewing'**
  String get ankiNoDecksSubtitle;

  /// No description provided for @ankiImportDeck.
  ///
  /// In en, this message translates to:
  /// **'Import Deck'**
  String get ankiImportDeck;

  /// No description provided for @ankiQuotaRemaining.
  ///
  /// In en, this message translates to:
  /// **'Today: {newLeft} new, {reviewLeft} reviews left'**
  String ankiQuotaRemaining(int newLeft, int reviewLeft);

  /// No description provided for @ankiQuotaExhausted.
  ///
  /// In en, this message translates to:
  /// **'Daily limit reached — come back tomorrow'**
  String get ankiQuotaExhausted;

  /// No description provided for @ankiUninstallDeck.
  ///
  /// In en, this message translates to:
  /// **'Remove deck'**
  String get ankiUninstallDeck;

  /// No description provided for @ankiUninstallConfirmTitle.
  ///
  /// In en, this message translates to:
  /// **'Remove this deck?'**
  String get ankiUninstallConfirmTitle;

  /// No description provided for @ankiUninstallConfirmBody.
  ///
  /// In en, this message translates to:
  /// **'This deletes the deck\'s cards, review progress, and media files. This cannot be undone.'**
  String get ankiUninstallConfirmBody;

  /// No description provided for @ankiDeckRemoved.
  ///
  /// In en, this message translates to:
  /// **'Deck removed'**
  String get ankiDeckRemoved;

  /// No description provided for @coursesCouldNotLoadCourse.
  ///
  /// In en, this message translates to:
  /// **'Could not load course'**
  String get coursesCouldNotLoadCourse;

  /// No description provided for @coursesNoSectionsFound.
  ///
  /// In en, this message translates to:
  /// **'No course sections found.'**
  String get coursesNoSectionsFound;

  /// No description provided for @coursesCouldNotLoadSection.
  ///
  /// In en, this message translates to:
  /// **'Could not load section'**
  String get coursesCouldNotLoadSection;

  /// No description provided for @coursesNoUnitsAvailable.
  ///
  /// In en, this message translates to:
  /// **'No units available'**
  String get coursesNoUnitsAvailable;

  /// No description provided for @coursesLoadingCourses.
  ///
  /// In en, this message translates to:
  /// **'Loading courses...'**
  String get coursesLoadingCourses;

  /// No description provided for @coursesLessonTypeNormal.
  ///
  /// In en, this message translates to:
  /// **'Lesson'**
  String get coursesLessonTypeNormal;

  /// No description provided for @coursesLessonTypeListening.
  ///
  /// In en, this message translates to:
  /// **'Listening'**
  String get coursesLessonTypeListening;

  /// No description provided for @coursesLessonTypeReading.
  ///
  /// In en, this message translates to:
  /// **'Reading'**
  String get coursesLessonTypeReading;

  /// No description provided for @coursesLessonTypeReview.
  ///
  /// In en, this message translates to:
  /// **'Review'**
  String get coursesLessonTypeReview;

  /// No description provided for @coursesLessonTypeChallenge.
  ///
  /// In en, this message translates to:
  /// **'Challenge'**
  String get coursesLessonTypeChallenge;

  /// No description provided for @coursesPerfect.
  ///
  /// In en, this message translates to:
  /// **'Perfect'**
  String get coursesPerfect;

  /// No description provided for @coursesUnitProgress.
  ///
  /// In en, this message translates to:
  /// **'{completedCount}/{lessonsCount}'**
  String coursesUnitProgress(int completedCount, int lessonsCount);

  /// No description provided for @coursesChooseSection.
  ///
  /// In en, this message translates to:
  /// **'Choose a Section'**
  String get coursesChooseSection;

  /// No description provided for @dictionaryTitle.
  ///
  /// In en, this message translates to:
  /// **'Dictionary'**
  String get dictionaryTitle;

  /// No description provided for @dictionarySearchHint.
  ///
  /// In en, this message translates to:
  /// **'Search Turkish or English…'**
  String get dictionarySearchHint;

  /// No description provided for @dictionarySearchEmpty.
  ///
  /// In en, this message translates to:
  /// **'Search vocabulary, expressions, and grammar'**
  String get dictionarySearchEmpty;

  /// No description provided for @dictionaryNoMatches.
  ///
  /// In en, this message translates to:
  /// **'No matches'**
  String get dictionaryNoMatches;

  /// No description provided for @dictionaryKindWord.
  ///
  /// In en, this message translates to:
  /// **'Word'**
  String get dictionaryKindWord;

  /// No description provided for @dictionaryKindPhrase.
  ///
  /// In en, this message translates to:
  /// **'Phrase'**
  String get dictionaryKindPhrase;

  /// No description provided for @dictionaryKindGrammar.
  ///
  /// In en, this message translates to:
  /// **'Grammar'**
  String get dictionaryKindGrammar;

  /// No description provided for @dictionaryPlayPronunciation.
  ///
  /// In en, this message translates to:
  /// **'Play pronunciation'**
  String get dictionaryPlayPronunciation;

  /// No description provided for @onboardingReclaimingTitle.
  ///
  /// In en, this message translates to:
  /// **'Reclaiming Language Learning'**
  String get onboardingReclaimingTitle;

  /// No description provided for @onboardingBody.
  ///
  /// In en, this message translates to:
  /// **'Remember when learning was about knowledge, not maximizing ad revenue? No hearts. No energy. No pay-to-win. Just pure, open-source education.'**
  String get onboardingBody;

  /// No description provided for @onboardingStartLearning.
  ///
  /// In en, this message translates to:
  /// **'Start Learning'**
  String get onboardingStartLearning;

  /// No description provided for @profileTitle.
  ///
  /// In en, this message translates to:
  /// **'Profile'**
  String get profileTitle;

  /// No description provided for @profileShare.
  ///
  /// In en, this message translates to:
  /// **'Share'**
  String get profileShare;

  /// No description provided for @profileShareYourProgress.
  ///
  /// In en, this message translates to:
  /// **'Share your progress'**
  String get profileShareYourProgress;

  /// No description provided for @profileShareButton.
  ///
  /// In en, this message translates to:
  /// **'Share'**
  String get profileShareButton;

  /// No description provided for @profileSharing.
  ///
  /// In en, this message translates to:
  /// **'Sharing...'**
  String get profileSharing;

  /// No description provided for @profileShareFailed.
  ///
  /// In en, this message translates to:
  /// **'Could not share progress: {error}'**
  String profileShareFailed(Object error);

  /// No description provided for @profileLearnerFallback.
  ///
  /// In en, this message translates to:
  /// **'Learner'**
  String get profileLearnerFallback;

  /// No description provided for @profileAchievementsTitle.
  ///
  /// In en, this message translates to:
  /// **'Achievements'**
  String get profileAchievementsTitle;

  /// No description provided for @profileViewMore.
  ///
  /// In en, this message translates to:
  /// **'View {remainingCount} more'**
  String profileViewMore(int remainingCount);

  /// No description provided for @profileShowLess.
  ///
  /// In en, this message translates to:
  /// **'Show less'**
  String get profileShowLess;

  /// No description provided for @profileAchievementLevel.
  ///
  /// In en, this message translates to:
  /// **'Lv.{level}'**
  String profileAchievementLevel(int level);

  /// No description provided for @profileAchievementProgress.
  ///
  /// In en, this message translates to:
  /// **'{current}/{displayTarget}'**
  String profileAchievementProgress(int current, int displayTarget);

  /// No description provided for @profileLearningStatsTitle.
  ///
  /// In en, this message translates to:
  /// **'Learning Stats'**
  String get profileLearningStatsTitle;

  /// No description provided for @profileXpToday.
  ///
  /// In en, this message translates to:
  /// **'XP Today'**
  String get profileXpToday;

  /// No description provided for @profileStudyTime.
  ///
  /// In en, this message translates to:
  /// **'Study Time'**
  String get profileStudyTime;

  /// No description provided for @profileAccuracy.
  ///
  /// In en, this message translates to:
  /// **'Accuracy'**
  String get profileAccuracy;

  /// No description provided for @profileStudyTimeValue.
  ///
  /// In en, this message translates to:
  /// **'{minutes}\''**
  String profileStudyTimeValue(int minutes);

  /// No description provided for @profileAccuracyValue.
  ///
  /// In en, this message translates to:
  /// **'{accuracy}%'**
  String profileAccuracyValue(int accuracy);

  /// No description provided for @profileLast7Days.
  ///
  /// In en, this message translates to:
  /// **'Last 7 Days'**
  String get profileLast7Days;

  /// No description provided for @profileTotalStudyTime.
  ///
  /// In en, this message translates to:
  /// **'Total Study Time'**
  String get profileTotalStudyTime;

  /// No description provided for @profileOverallAccuracy.
  ///
  /// In en, this message translates to:
  /// **'Overall Accuracy'**
  String get profileOverallAccuracy;

  /// No description provided for @profileLessonsDone.
  ///
  /// In en, this message translates to:
  /// **'Lessons Done'**
  String get profileLessonsDone;

  /// No description provided for @profileReviewsDone.
  ///
  /// In en, this message translates to:
  /// **'Reviews Done'**
  String get profileReviewsDone;

  /// No description provided for @profileTotalStudyTimeValue.
  ///
  /// In en, this message translates to:
  /// **'{totalMinutes}m'**
  String profileTotalStudyTimeValue(int totalMinutes);

  /// No description provided for @profileOverallAccuracyValue.
  ///
  /// In en, this message translates to:
  /// **'{accuracy}%'**
  String profileOverallAccuracyValue(int accuracy);

  /// No description provided for @profileStatisticsTitle.
  ///
  /// In en, this message translates to:
  /// **'Statistics'**
  String get profileStatisticsTitle;

  /// No description provided for @profileDayStreak.
  ///
  /// In en, this message translates to:
  /// **'Day Streak'**
  String get profileDayStreak;

  /// No description provided for @profileTotalXp.
  ///
  /// In en, this message translates to:
  /// **'Total XP'**
  String get profileTotalXp;

  /// No description provided for @profileGems.
  ///
  /// In en, this message translates to:
  /// **'Gems'**
  String get profileGems;

  /// No description provided for @profileShareCardLearning.
  ///
  /// In en, this message translates to:
  /// **'{displayName} is learning'**
  String profileShareCardLearning(String displayName);

  /// No description provided for @profileShareCardDayStreak.
  ///
  /// In en, this message translates to:
  /// **'Day Streak'**
  String get profileShareCardDayStreak;

  /// No description provided for @profileShareCardTotalXp.
  ///
  /// In en, this message translates to:
  /// **'Total XP'**
  String get profileShareCardTotalXp;

  /// No description provided for @profileShareCardGems.
  ///
  /// In en, this message translates to:
  /// **'Gems'**
  String get profileShareCardGems;

  /// No description provided for @profileShareCardLessons.
  ///
  /// In en, this message translates to:
  /// **'Lessons'**
  String get profileShareCardLessons;

  /// No description provided for @profileShareCardJoinMe.
  ///
  /// In en, this message translates to:
  /// **'Join me on Varnamala!'**
  String get profileShareCardJoinMe;

  /// No description provided for @profileShareText.
  ///
  /// In en, this message translates to:
  /// **'Check out my progress on Varnamala!'**
  String get profileShareText;

  /// No description provided for @charactersScriptTitle.
  ///
  /// In en, this message translates to:
  /// **'{currentLanguage} Script'**
  String charactersScriptTitle(String currentLanguage);

  /// No description provided for @charactersVowelsTitle.
  ///
  /// In en, this message translates to:
  /// **'Vowels'**
  String get charactersVowelsTitle;

  /// No description provided for @charactersVowelsSubtitle.
  ///
  /// In en, this message translates to:
  /// **'{count} characters'**
  String charactersVowelsSubtitle(int count);

  /// No description provided for @charactersConsonantsTitle.
  ///
  /// In en, this message translates to:
  /// **'Consonants'**
  String get charactersConsonantsTitle;

  /// No description provided for @charactersConsonantsSubtitle.
  ///
  /// In en, this message translates to:
  /// **'{count} characters'**
  String charactersConsonantsSubtitle(int count);

  /// No description provided for @charactersLearnVowels.
  ///
  /// In en, this message translates to:
  /// **'Learn Vowels'**
  String get charactersLearnVowels;

  /// No description provided for @charactersLearnConsonants.
  ///
  /// In en, this message translates to:
  /// **'Learn Consonants'**
  String get charactersLearnConsonants;

  /// No description provided for @charactersRandomPractice.
  ///
  /// In en, this message translates to:
  /// **'Random Practice'**
  String get charactersRandomPractice;

  /// No description provided for @charactersVowelsModeTitle.
  ///
  /// In en, this message translates to:
  /// **'Vowels'**
  String get charactersVowelsModeTitle;

  /// No description provided for @charactersConsonantsModeTitle.
  ///
  /// In en, this message translates to:
  /// **'Consonants'**
  String get charactersConsonantsModeTitle;

  /// No description provided for @charactersRandomModeTitle.
  ///
  /// In en, this message translates to:
  /// **'Random Practice'**
  String get charactersRandomModeTitle;

  /// No description provided for @charactersNext.
  ///
  /// In en, this message translates to:
  /// **'Next'**
  String get charactersNext;

  /// No description provided for @contentUpdateTitle.
  ///
  /// In en, this message translates to:
  /// **'Course updated'**
  String get contentUpdateTitle;

  /// No description provided for @contentUpdateMessage.
  ///
  /// In en, this message translates to:
  /// **'The Turkish course has been updated with new words and lessons. You can start over or continue with your current progress.'**
  String get contentUpdateMessage;

  /// No description provided for @contentUpdateKeepProgress.
  ///
  /// In en, this message translates to:
  /// **'Keep progress'**
  String get contentUpdateKeepProgress;

  /// No description provided for @contentUpdateResetProgress.
  ///
  /// In en, this message translates to:
  /// **'Reset progress'**
  String get contentUpdateResetProgress;

  /// No description provided for @splashReclaiming.
  ///
  /// In en, this message translates to:
  /// **'Reclaiming Language Learning'**
  String get splashReclaiming;

  /// No description provided for @splashLearnTurkish.
  ///
  /// In en, this message translates to:
  /// **'Learn Turkish • Türkçe öğren'**
  String get splashLearnTurkish;

  /// No description provided for @splashFreeForever.
  ///
  /// In en, this message translates to:
  /// **'Free. Forever.'**
  String get splashFreeForever;

  /// No description provided for @splashAppName.
  ///
  /// In en, this message translates to:
  /// **'Varnamala'**
  String get splashAppName;

  /// No description provided for @splashSubtitle.
  ///
  /// In en, this message translates to:
  /// **'No hearts to lose. No energy to refill.\nJust pure learning.'**
  String get splashSubtitle;

  /// No description provided for @splashGetStarted.
  ///
  /// In en, this message translates to:
  /// **'GET STARTED'**
  String get splashGetStarted;

  /// No description provided for @splashTurkishVoiceMissingTitle.
  ///
  /// In en, this message translates to:
  /// **'Turkish voice data missing'**
  String get splashTurkishVoiceMissingTitle;

  /// No description provided for @splashTurkishVoiceMissingBody.
  ///
  /// In en, this message translates to:
  /// **'Google Text-to-speech is installed, but the Turkish voice pack is not downloaded yet.\n\nOpen system TTS settings → preferred engine = Google → install language data for Turkish (Türkçe).'**
  String get splashTurkishVoiceMissingBody;

  /// No description provided for @splashGoogleTtsMissingTitle.
  ///
  /// In en, this message translates to:
  /// **'Google TTS not available'**
  String get splashGoogleTtsMissingTitle;

  /// No description provided for @splashGoogleTtsMissingBody.
  ///
  /// In en, this message translates to:
  /// **'This device does not show Google Text-to-speech (or package visibility blocked engine discovery).\n\nInstall \"Speech Recognition & Synthesis from Google\", set it as the preferred engine, and download the Turkish voice.'**
  String get splashGoogleTtsMissingBody;

  /// No description provided for @splashGoogleTtsNotReadyTitle.
  ///
  /// In en, this message translates to:
  /// **'Google TTS not available'**
  String get splashGoogleTtsNotReadyTitle;

  /// No description provided for @splashGoogleTtsNotReadyBody.
  ///
  /// In en, this message translates to:
  /// **'Preferred system voice is not ready. Install Google TTS and the Turkish voice pack.'**
  String get splashGoogleTtsNotReadyBody;

  /// No description provided for @splashKeepCurrentVoice.
  ///
  /// In en, this message translates to:
  /// **'Keep current voice'**
  String get splashKeepCurrentVoice;

  /// No description provided for @splashTtsSettings.
  ///
  /// In en, this message translates to:
  /// **'TTS settings'**
  String get splashTtsSettings;

  /// No description provided for @splashInstallGoogleTts.
  ///
  /// In en, this message translates to:
  /// **'Install Google TTS'**
  String get splashInstallGoogleTts;

  /// No description provided for @splashCouldNotOpenStore.
  ///
  /// In en, this message translates to:
  /// **'Could not open the store. Install Google TTS manually.'**
  String get splashCouldNotOpenStore;

  /// No description provided for @aiTemplateIntro.
  ///
  /// In en, this message translates to:
  /// **'New Words'**
  String get aiTemplateIntro;

  /// No description provided for @aiTemplatePractice.
  ///
  /// In en, this message translates to:
  /// **'Practice'**
  String get aiTemplatePractice;

  /// No description provided for @aiTemplateReview.
  ///
  /// In en, this message translates to:
  /// **'Review'**
  String get aiTemplateReview;

  /// No description provided for @aiTemplateListening.
  ///
  /// In en, this message translates to:
  /// **'Listening'**
  String get aiTemplateListening;

  /// No description provided for @aiTemplateReading.
  ///
  /// In en, this message translates to:
  /// **'Reading'**
  String get aiTemplateReading;

  /// No description provided for @aiTemplateMastery.
  ///
  /// In en, this message translates to:
  /// **'Quiz'**
  String get aiTemplateMastery;

  /// No description provided for @aiTemplateMixed.
  ///
  /// In en, this message translates to:
  /// **'Mixed'**
  String get aiTemplateMixed;

  /// No description provided for @settingsUiLanguageTitle.
  ///
  /// In en, this message translates to:
  /// **'App Language'**
  String get settingsUiLanguageTitle;

  /// No description provided for @settingsUiLanguageSubtitle.
  ///
  /// In en, this message translates to:
  /// **'Choose the interface language'**
  String get settingsUiLanguageSubtitle;

  /// No description provided for @settingsUiLanguageSystem.
  ///
  /// In en, this message translates to:
  /// **'Follow system'**
  String get settingsUiLanguageSystem;
}

class _AppLocalizationsDelegate
    extends LocalizationsDelegate<AppLocalizations> {
  const _AppLocalizationsDelegate();

  @override
  Future<AppLocalizations> load(Locale locale) {
    return SynchronousFuture<AppLocalizations>(lookupAppLocalizations(locale));
  }

  @override
  bool isSupported(Locale locale) =>
      <String>['en', 'zh'].contains(locale.languageCode);

  @override
  bool shouldReload(_AppLocalizationsDelegate old) => false;
}

AppLocalizations lookupAppLocalizations(Locale locale) {
  // Lookup logic when only language code is specified.
  switch (locale.languageCode) {
    case 'en':
      return AppLocalizationsEn();
    case 'zh':
      return AppLocalizationsZh();
  }

  throw FlutterError(
      'AppLocalizations.delegate failed to load unsupported locale "$locale". This is likely '
      'an issue with the localizations generation tool. Please file an issue '
      'on GitHub with a reproducible sample app and the gen-l10n configuration '
      'that was used.');
}
