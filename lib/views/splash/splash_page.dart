// Flutter imports:
import 'package:auto_route/auto_route.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

// Project imports:
import 'package:varnamala/application/language_provider.dart';
import 'package:varnamala/di/injection.dart';
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
    if (!kIsWeb) {
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
    final (title, body) = switch (diag.preferredStatus) {
      TtsPreferredStatus.turkishVoiceMissing => (
          'Turkish voice data missing',
          'Google Text-to-speech is installed, but the Turkish voice pack '
              'is not downloaded yet.\n\n'
              'Open system TTS settings → preferred engine = Google → '
              'install language data for Turkish (Türkçe).',
        ),
      TtsPreferredStatus.googleMissing => (
          'Google TTS not available',
          'This device does not show Google Text-to-speech '
              '(or package visibility blocked engine discovery).\n\n'
              'Install "Speech Recognition & Synthesis from Google", set it '
              'as the preferred engine, and download the Turkish voice.',
        ),
      TtsPreferredStatus.ready => (
          'Google TTS not available',
          'Preferred system voice is not ready. Install Google TTS and '
              'the Turkish voice pack.',
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
            child: const Text('Keep current voice'),
          ),
          TextButton(
            onPressed: () =>
                Navigator.of(context).pop(_GoogleTtsPromptAction.openSettings),
            child: const Text('TTS settings'),
          ),
          TextButton(
            onPressed: () =>
                Navigator.of(context).pop(_GoogleTtsPromptAction.installGoogle),
            child: const Text('Install Google TTS'),
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
            const SnackBar(
              content: Text(
                'Could not open the store. Install Google TTS manually.',
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