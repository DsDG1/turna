import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:streaming_shared_preferences/streaming_shared_preferences.dart';
import 'package:varnamala/application/settings_provider.dart';
import 'package:varnamala/service/locator.dart';
import 'package:varnamala/views/settings/widgets/settings_common.dart';
import 'package:varnamala/views/settings/widgets/settings_sound_section.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late AppPrefs prefs;
  late SettingsProvider settings;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    final sp = await StreamingSharedPreferences.instance;
    prefs = AppPrefs(sp);
    settings = SettingsProvider(prefs);
  });

  testWidgets('sound and haptic toggles update SettingsProvider',
      (tester) async {
    await tester.pumpWidget(
      ChangeNotifierProvider<SettingsProvider>.value(
        value: settings,
        child: MaterialApp(
          home: Scaffold(
            body: SettingsCard(
              children: [
                SettingsToggleTile(
                  icon: Icons.music_note_rounded,
                  title: 'Sound effects',
                  subtitle: 'Play sounds',
                  valueSelector: (p) => p.soundEffectsEnabled,
                  onChanged: (p, v) => p.setSoundEffects(v),
                ),
                SettingsToggleTile(
                  icon: Icons.vibration_rounded,
                  title: 'Haptic feedback',
                  subtitle: 'Vibrate',
                  valueSelector: (p) => p.hapticFeedbackEnabled,
                  onChanged: (p, v) => p.setHapticFeedback(v),
                ),
              ],
            ),
          ),
        ),
      ),
    );

    expect(find.text('Sound effects'), findsOneWidget);
    expect(find.text('Haptic feedback'), findsOneWidget);
    expect(settings.soundEffectsEnabled, isTrue);

    await tester.tap(find.byType(Switch).first);
    await tester.pumpAndSettle();
    expect(settings.soundEffectsEnabled, isFalse);
  });
}
