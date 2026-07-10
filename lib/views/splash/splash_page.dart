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
    // Respect the user's explicit choice: if they already chose offline, do
    // not ask again.
    if (settings.ttsEngine == TtsEngine.offline) return;

    final prefs = getIt<AppPrefs>();
    final alreadyPrompted = prefs.preferences
        .getBool(LocalStateKeys.ttsAvailabilityPromptShown, defaultValue: false)
        .getValue();

    final checker = getIt<TtsAvailabilityChecker>();
    final languageCode = getIt<LanguageProvider>().ttsLanguageCode;
    final available = await checker.isSystemTtsAvailable(languageCode);

    if (available) {
      await checker.configureSystemEngine();
      return;
    }

    if (!mounted || alreadyPrompted) return;

    final shouldSwitch = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        title: const Text('Local voice not available'),
        content: const Text(
          'Your device does not have a local Swahili text-to-speech voice. '
          'Would you like to switch to the offline Piper voice?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Keep system'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Switch'),
          ),
        ],
      ),
    );

    if (shouldSwitch == true) {
      await settings.setTtsEngine(TtsEngine.offline);
    }

    await prefs.setBool(
      LocalStateKeys.ttsAvailabilityPromptShown,
      value: true,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
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
