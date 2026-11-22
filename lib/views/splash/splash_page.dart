// Flutter imports:
import 'package:auto_route/auto_route.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

// Project imports:
import 'package:turna/application/course_provider.dart';
import 'package:turna/application/game_provider.dart';
import 'package:turna/application/language_provider.dart';
import 'package:turna/core/logger.dart';
import 'package:turna/core/ohos_target.dart';
import 'package:turna/core/spacing.dart';
import 'package:turna/core/text_styles.dart';
import 'package:turna/core/theme.dart';
import 'package:turna/core/turna_icon_id.dart';
import 'package:turna/di/injection.dart';
import 'package:turna/l10n/app_strings.dart';
import 'package:turna/routing/routing.gr.dart';
import 'package:turna/service/app_startup.dart';
import 'package:turna/service/locator.dart';
import 'package:turna/service/tts_availability_checker.dart';
import 'package:turna/views/widgets/ambient_backdrop.dart';
import 'package:turna/views/widgets/optional_provider.dart';
import 'package:turna/views/widgets/practice_empty_state.dart';
import 'package:turna/views/widgets/turna_geometry.dart';
import 'package:turna/views/widgets/turna_icon.dart';
import 'package:turna/views/widgets/turna_loader.dart';
import 'package:turna/views/widgets/turna_page_content.dart';
import 'package:turna/views/widgets/turna_sheet.dart';
import 'package:turna/views/widgets/turna_snack_bar.dart';

/// Returns true when a TTS dialog was shown (counts against the session
/// modal budget). Dismissing the barrier keeps the system voice.
Future<bool> maybePromptTtsAvailability(
  BuildContext context, {
  @visibleForTesting
  Duration androidRetryDelay = const Duration(milliseconds: 350),
}) async {
  if (kIsWeb) return false;
  final language = readOptionalProvider<LanguageProvider>(context);
  if (language == null ||
      !getIt.isRegistered<AppPrefs>() ||
      !getIt.isRegistered<TtsAvailabilityChecker>()) {
    return false;
  }
  final prefs = getIt<AppPrefs>();
  final alreadyPrompted = prefs.preferences
      .getBool(LocalStateKeys.ttsAvailabilityPromptShown, defaultValue: false)
      .getValue();
  if (alreadyPrompted) return false;

  final checker = getIt<TtsAvailabilityChecker>();
  final languageCode = language.ttsLanguageCode;
  final languageName = language.displayName;
  var diag = await checker.diagnose(languageCode);
  if (!context.mounted) return false;

  // On Android cold start, switching from the OEM default engine to Google TTS
  // (com.google.android.tts) can fail its first bind or expose an empty voice
  // table for a brief moment while the Google service initializes. Retry once
  // before concluding Google TTS or the voice pack is missing.
  if (!isHarmonyOsTarget &&
      defaultTargetPlatform == TargetPlatform.android &&
      diag.preferredStatus != TtsPreferredStatus.ready &&
      androidRetryDelay > Duration.zero) {
    await Future<void>.delayed(androidRetryDelay);
    if (!context.mounted) return false;
    if (!checker.isEngineConfigured || !diag.hasGoogleEngine) {
      await checker.configureSystemEngine(force: true);
    } else {
      checker.invalidateDiagnostics();
    }
    diag = await checker.diagnose(languageCode);
    if (!context.mounted) return false;
  }

  if (diag.preferredStatus == TtsPreferredStatus.ready) return false;

  if (isHarmonyOsTarget) {
    // The companion build cannot act on this report: there is no store to open
    // and no engine to select, and the device publishes its own voice list
    // which we verified has no downloadable Turkish pack. So the dialog only
    // states the fact and lets the user dismiss it.
    final voices = AppStrings.voiceListLabel(
      await checker.listVoiceLanguages(),
    );
    if (!context.mounted) return false;
    final (title, body) = switch (diag.preferredStatus) {
      TtsPreferredStatus.ready => (
        AppStrings.splashOhosNoVoiceTitle,
        AppStrings.splashOhosNoVoiceBody(voices),
      ),
      TtsPreferredStatus.voiceMissing => (
        AppStrings.splashOhosVoiceMissingTitle(languageName),
        AppStrings.splashOhosVoiceMissingBody(languageName, voices),
      ),
      TtsPreferredStatus.googleMissing => (
        AppStrings.splashOhosNoVoiceTitle,
        AppStrings.splashOhosNoVoiceBody(voices),
      ),
    };
    await showTurnaInfoDialog(
      context: context,
      title: title,
      message: body,
      doneLabel: AppStrings.splashAcknowledge,
    );
    await prefs.setBool(LocalStateKeys.ttsAvailabilityPromptShown, value: true);
    return true;
  }

  final (title, body) = switch (diag.preferredStatus) {
    TtsPreferredStatus.voiceMissing => (
      AppStrings.splashVoiceMissingTitle(languageName),
      AppStrings.splashVoiceMissingBody(languageName),
    ),
    TtsPreferredStatus.googleMissing => (
      AppStrings.splashGoogleTtsMissingTitle,
      AppStrings.splashGoogleTtsMissingBody(languageName),
    ),
    TtsPreferredStatus.ready => (
      AppStrings.splashGoogleTtsNotReadyTitle,
      AppStrings.splashGoogleTtsNotReadyBody(languageName),
    ),
  };

  final action = await showTurnaFormDialog<_GoogleTtsPromptAction>(
    context: context,
    title: title,
    barrierDismissible: true,
    body: Builder(
      builder: (dialogContext) => Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            body,
            style: AppTextStyles.bodyText(dialogContext)
                .copyWith(color: TurnaTheme.textSecondaryColor(dialogContext)),
          ),
          const SizedBox(height: AppSpacing.md),
          OutlinedButton.icon(
            onPressed: () =>
                Navigator.of(dialogContext)
                    .pop(_GoogleTtsPromptAction.openSettings),
            icon: const TurnaIcon(TurnaIconId.speakVoice, size: 18),
            label: Text(AppStrings.splashTtsSettings),
          ),
        ],
      ),
    ),
    actions: [
      TurnaSheetAction(
        label: AppStrings.splashKeepCurrentVoice,
        onPressed: () =>
            Navigator.of(context).pop(_GoogleTtsPromptAction.keepSystem),
      ),
      TurnaSheetAction(
        label: AppStrings.splashInstallGoogleTts,
        primary: true,
        onPressed: () =>
            Navigator.of(context).pop(_GoogleTtsPromptAction.installGoogle),
      ),
    ],
  );

  await prefs.setBool(LocalStateKeys.ttsAvailabilityPromptShown, value: true);

  if (!context.mounted) return true;
  switch (action) {
    case _GoogleTtsPromptAction.installGoogle:
      final opened = await checker.openGoogleTtsInstallPage();
      if (!opened && context.mounted) {
        TurnaSnackBar.show(context, AppStrings.splashCouldNotOpenStore);
      }
    case _GoogleTtsPromptAction.openSettings:
      await checker.openSystemTtsSettings();
    case _GoogleTtsPromptAction.keepSystem:
    case null:
      break;
  }
  return true;
}

/// Label shown while the course is not loaded yet.
/// Null once the course is up, or when boot failed (the retry copy takes over).
String? splashStartupStatusLabel(
  TurnaStartupPhase phase, {
  required bool courseLoaded,
  required bool bootFailed,
}) {
  if (courseLoaded || bootFailed) return null;
  if (phase == TurnaStartupPhase.validating) {
    return AppStrings.splashPhaseValidating;
  }
  return AppStrings.splashPhaseSeeding;
}

enum _GoogleTtsPromptAction { installGoogle, openSettings, keepSystem }

/// Startup gate — NOT a welcome screen.
///
/// It holds navigation only while the course shells load and provides retry
/// after a failed boot. The geometric brand composition never adds an
/// artificial delay or a "get started" step: the learner goes straight to
/// [HomeRoute] when the providers are ready (see [_SplashPageState._maybeSkip]).
@RoutePage()
class SplashPage extends StatefulWidget {
  const SplashPage({super.key});

  @override
  State<SplashPage> createState() => _SplashPageState();
}

class _SplashPageState extends State<SplashPage> {
  bool _navigating = false;

  /// One-shot: a gate that never opens is otherwise invisible — the splash
  /// simply spins, which is how a first-install deadlock went unnoticed.
  bool _loggedBlocked = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _maybeSkip());
  }

  void _maybeSkip() {
    if (!mounted || _navigating) return;
    GameProvider? game;
    CourseProvider? course;
    try {
      game = context.read<GameProvider>();
      course = context.read<CourseProvider>();
    } catch (_) {
      // Optional provider guard: SplashPage can be pumped in isolated tests.
      return;
    }
    if (game.initialized && course.isLoaded) {
      _navigating = true;
      context.router.replaceAll([const HomeRoute()]);
    }
  }

  @override
  Widget build(BuildContext context) {
    GameProvider? game;
    CourseProvider? course;
    try {
      game = context.watch<GameProvider>();
      course = context.watch<CourseProvider>();
    } catch (_) {
      // Optional provider guard: SplashPage can be pumped in isolated tests.
      game = null;
      course = null;
    }
    final initialized = game?.initialized ?? false;
    final loaded = course?.isLoaded ?? false;
    if (loaded && !initialized && !_loggedBlocked) {
      _loggedBlocked = true;
      logger.w(
        'Splash held: course is loaded but GameProvider.initialized is false. '
        'Nothing seeds that flag from this screen — it must be seeded during '
        'startup (see continueTurnaStartup).',
      );
    }
    if (initialized && loaded && !_navigating) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _maybeSkip());
    }
    final bootFailed = course?.bootFailed ?? false;
    // The logo source PNG is a 1024×1024 store render (~4 MB decoded); cap
    // the decode to the 76 dp box at the device ratio so splash never
    // decodes the full-size bitmap.
    final logoPx = (76 * MediaQuery.devicePixelRatioOf(context)).round();
    return AmbientBackdrop(
      baseColor: TurnaTheme.scaffoldBg(context),
      child: Scaffold(
        backgroundColor: Colors.transparent,
        body: TurnaGeometryBackdrop(
          kind: TurnaGeometryKind.arch,
          alignment: Alignment.bottomCenter,
          size: (MediaQuery.sizeOf(context).width * 0.95).clamp(240.0, 420.0),
          intensity: 0.72,
          child: SafeArea(
            child: Center(
              child: TurnaPageContent(
                maxWidth: 420,
                padding: const EdgeInsets.all(AppSpacing.xl),
                child: bootFailed
                    ? PracticeEmptyState(
                        title: AppStrings.splashCourseLoadFailed,
                        actionLabel: AppStrings.commonRetry,
                        onAction: () => continueTurnaStartup(retrySeed: true),
                      )
                    : Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          TurnaGeometry(
                            kind: TurnaGeometryKind.journey,
                            size: 164,
                            child: Container(
                              width: 84,
                              height: 84,
                              padding: const EdgeInsets.all(AppSpacing.xs),
                              decoration: TurnaTheme.glassDecoration(
                                context,
                                TurnaTheme.brandTeal,
                                level: GlassLevel.l1Subtle,
                              ),
                              child: ClipRRect(
                                borderRadius: TurnaTheme.borderRadius,
                                child: Image.asset(
                                  'assets/images/app_logo.png',
                                  width: 76,
                                  height: 76,
                                  cacheWidth: logoPx,
                                  cacheHeight: logoPx,
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(height: AppSpacing.xl),
                          ListenableBuilder(
                            listenable: turnaStartupProgress,
                            builder: (context, _) {
                              final label = splashStartupStatusLabel(
                                turnaStartupProgress.phase,
                                courseLoaded: course?.isLoaded ?? false,
                                bootFailed: course?.bootFailed ?? false,
                              );
                              return TurnaLoader.page(label: label);
                            },
                          ),
                        ],
                      ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
