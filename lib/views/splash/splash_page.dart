// Flutter imports:
import 'package:auto_route/auto_route.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

// Project imports:
import 'package:varnamala/application/language_provider.dart';
import 'package:varnamala/di/injection.dart';
import 'package:varnamala/l10n/app_strings.dart';
import 'package:varnamala/service/locator.dart';
import 'package:varnamala/service/tts_availability_checker.dart';
import 'package:varnamala/views/theme.dart';

import 'components/center_display.dart';
import 'components/get_started_button.dart';
import 'components/splash_background_painter.dart';

@RoutePage()
class SplashPage extends StatefulWidget {
  const SplashPage({Key? key}) : super(key: key);

  @override
  State<SplashPage> createState() => _SplashPageState();
}

class _SplashPageState extends State<SplashPage> {
  @override
  void initState() {
    super.initState();
    if (!kIsWeb && defaultTargetPlatform != TargetPlatform.ohos) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _checkTtsAvailability());
    }
  }

  Future<void> _checkTtsAvailability() async {
    if (!mounted) return;

    final prefs = getIt<AppPrefs>();
    final alreadyPrompted = prefs.preferences
        .getBool(LocalStateKeys.ttsAvailabilityPromptShown, defaultValue: false)
        .getValue();

    final checker = getIt<TtsAvailabilityChecker>();
    final languageCode = getIt<LanguageProvider>().ttsLanguageCode;

    // Preferred = Google TTS (Android) with installed Turkish voice data.
    // isPreferredSystemTtsAvailable already configures the Google engine via
    // resolveLanguageCode — do not call configureSystemEngine again here
    // (concurrent setEngine races crash flutter_tts on Android).
    final preferred = await checker.isPreferredSystemTtsAvailable(languageCode);
    if (preferred) return;

    if (!mounted || alreadyPrompted) return;

    final diag = await checker.diagnose(languageCode);
    if (!mounted) return;
    final l10n = AppStrings;
    final (title, body) = switch (diag.preferredStatus) {
      TtsPreferredStatus.turkishVoiceMissing => (
          AppStrings.splashTurkishVoiceMissingTitle,
          AppStrings.splashTurkishVoiceMissingBody,
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
      barrierDismissible: false,
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

    if (!mounted || action == null) return;

    switch (action) {
      case _GoogleTtsPromptAction.installGoogle:
        final opened = await checker.openGoogleTtsInstallPage();
        if (!opened && mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                AppStrings.splashCouldNotOpenStore,
              ),
            ),
          );
        }
      case _GoogleTtsPromptAction.openSettings:
        await checker.openSystemTtsSettings();
      case _GoogleTtsPromptAction.keepSystem:
        break;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: VarnamalaTheme.scaffoldBg(context),
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

enum _GoogleTtsPromptAction {
  installGoogle,
  openSettings,
  keepSystem,
}