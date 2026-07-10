// Flutter imports:
import 'package:auto_route/auto_route.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

// Project imports:
import 'package:varnamala/application/language_provider.dart';
import 'package:varnamala/application/settings_provider.dart';
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

    final settings = getIt<SettingsProvider>();
    // Respect explicit offline choice — do not nag about Google TTS.
    if (settings.ttsEngine == TtsEngine.offline) return;

    final prefs = getIt<AppPrefs>();
    final alreadyPrompted = prefs.preferences
        .getBool(LocalStateKeys.ttsAvailabilityPromptShown, defaultValue: false)
        .getValue();

    final checker = getIt<TtsAvailabilityChecker>();
    final languageCode = getIt<LanguageProvider>().ttsLanguageCode;

    // Preferred = Google TTS (Android) with a usable locale — not OEM-only.
    final preferred = await checker.isPreferredSystemTtsAvailable(languageCode);
    if (preferred) {
      await checker.configureSystemEngine();
      return;
    }

    if (!mounted || alreadyPrompted) return;

    final action = await showDialog<_GoogleTtsPromptAction>(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        title: const Text('Google TTS not available'),
        content: const Text(
          'This device does not have Google Text-to-speech installed '
          '(or it is not enabled). For best Swahili pronunciation, install '
          '"Speech Recognition & Synthesis from Google", then set it as the '
          'preferred engine and download the Swahili voice if offered.\n\n'
          'Offline Piper is a temporary alternative only.',
        ),
        actions: [
          TextButton(
            onPressed: () =>
                Navigator.of(context).pop(_GoogleTtsPromptAction.keepSystem),
            child: const Text('Keep current voice'),
          ),
          TextButton(
            onPressed: () =>
                Navigator.of(context).pop(_GoogleTtsPromptAction.useOffline),
            child: const Text('Use offline Piper'),
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
                'Could not open the store. Install Google TTS manually, '
                'or use Offline Piper for now.',
              ),
            ),
          );
        }
      case _GoogleTtsPromptAction.openSettings:
        await checker.openSystemTtsSettings();
      case _GoogleTtsPromptAction.useOffline:
        await settings.setTtsEngine(TtsEngine.offline);
      case _GoogleTtsPromptAction.keepSystem:
        // Leave TtsEngine.system; OEM engine may still speak.
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
  useOffline,
  keepSystem,
}
