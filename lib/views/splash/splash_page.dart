// Flutter imports:
import 'package:auto_route/auto_route.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

// Project imports:
import 'package:turna/application/course_provider.dart';
import 'package:turna/application/game_provider.dart';
import 'package:turna/application/language_provider.dart';
import 'package:turna/di/injection.dart';
import 'package:turna/l10n/app_strings.dart';
import 'package:turna/routing/routing.gr.dart';
import 'package:turna/service/locator.dart';
import 'package:turna/service/tts_availability_checker.dart';
import 'package:turna/core/theme.dart';
import 'package:turna/views/widgets/turna_snack_bar.dart';

import 'components/center_display.dart';
import 'components/get_started_button.dart';
import 'components/splash_background_painter.dart';

/// Returns true when a TTS dialog was shown (counts against the session
/// modal budget). Dismissing the barrier keeps the system voice.
Future<bool> maybePromptTtsAvailability(BuildContext context) async {
  if (kIsWeb) return false;
  final prefs = getIt<AppPrefs>();
  final alreadyPrompted = prefs.preferences
      .getBool(LocalStateKeys.ttsAvailabilityPromptShown, defaultValue: false)
      .getValue();
  if (alreadyPrompted) return false;

  final checker = getIt<TtsAvailabilityChecker>();
  final languageCode = getIt<LanguageProvider>().ttsLanguageCode;
  final preferred = await checker.isPreferredSystemTtsAvailable(languageCode);
  if (preferred || !context.mounted) return false;

  final diag = await checker.diagnose(languageCode);
  if (!context.mounted) return false;
  final languageName = getIt<LanguageProvider>().displayName;
  final (title, body) = switch (diag.preferredStatus) {
    TtsPreferredStatus.voiceMissing => (
        AppStrings.splashVoiceMissingTitle(languageName),
        AppStrings.splashVoiceMissingBody(languageName),
      ),
    TtsPreferredStatus.googleMissing => (
        AppStrings.splashGoogleTtsMissingTitle,
        AppStrings.splashGoogleTtsMissingBody,
      ),
    TtsPreferredStatus.ready => (
        AppStrings.splashGoogleTtsNotReadyTitle,
        AppStrings.splashGoogleTtsNotReadyBody,
      ),
  };

  final action = await showDialog<_GoogleTtsPromptAction>(
    context: context,
    barrierDismissible: true,
    builder: (context) => AlertDialog(
      title: Text(title),
      content: Text(body),
      actions: [
        TextButton(
          onPressed: () =>
              Navigator.of(context).pop(_GoogleTtsPromptAction.keepSystem),
          child: Text(AppStrings.splashKeepCurrentVoice),
        ),
        TextButton(
          onPressed: () =>
              Navigator.of(context).pop(_GoogleTtsPromptAction.openSettings),
          child: Text(AppStrings.splashTtsSettings),
        ),
        TextButton(
          onPressed: () =>
              Navigator.of(context).pop(_GoogleTtsPromptAction.installGoogle),
          child: Text(AppStrings.splashInstallGoogleTts),
        ),
      ],
    ),
  );

  await prefs.setBool(
    LocalStateKeys.ttsAvailabilityPromptShown,
    value: true,
  );

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

enum _GoogleTtsPromptAction {
  installGoogle,
  openSettings,
  keepSystem,
}

@RoutePage()
class SplashPage extends StatefulWidget {
  const SplashPage({super.key});

  @override
  State<SplashPage> createState() => _SplashPageState();
}

class _SplashPageState extends State<SplashPage> {
  bool _navigating = false;

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
      game = null;
      course = null;
    }
    final initialized = game?.initialized ?? false;
    final loaded = course?.isLoaded ?? false;
    if (initialized && loaded && !_navigating) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _maybeSkip());
    }
    return Scaffold(
      backgroundColor: TurnaTheme.scaffoldBg(context),
      body: Stack(
        children: [
          CustomPaint(
            painter: SplashBackgroundPainter(),
            size: Size.infinite,
          ),
          SafeArea(
            child: Column(
              children: [
                const Expanded(child: CenterDisplay()),
                Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (course?.bootFailed ?? false) ...[
                        Padding(
                          padding: const EdgeInsets.fromLTRB(24, 0, 24, 12),
                          child: Text(
                            AppStrings.splashCourseLoadFailed,
                            textAlign: TextAlign.center,
                            style: Theme.of(context)
                                .textTheme
                                .bodyMedium
                                ?.copyWith(
                                  color: TurnaTheme.textSecondaryColor(context),
                                ),
                          ),
                        ),
                      ],
                      GetStartedButton(context),
                      const SizedBox(height: 16),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
