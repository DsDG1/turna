// Widget tests: TTS / text-scale sliders persist on change-end only. While
// dragging, text-scale mirrors each snapped step into the provider in memory
// (live preview) but never writes prefs.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:streaming_shared_preferences/streaming_shared_preferences.dart';
import 'package:turna/application/accessibility_provider.dart';
import 'package:turna/application/settings_provider.dart';
import 'package:turna/service/locator.dart';
import 'package:turna/views/settings/widgets/settings_accessibility_section.dart';
import 'package:turna/views/settings/widgets/settings_common.dart';
import 'package:turna/views/settings/widgets/settings_learning_section.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late AppPrefs prefs;
  late SettingsProvider settings;
  late AccessibilityProvider accessibility;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    final sp = await StreamingSharedPreferences.instance;
    prefs = AppPrefs(sp);
    settings = SettingsProvider(prefs);
    accessibility = AccessibilityProvider(prefs);
  });

  testWidgets('text scale slider persists only after drag ends',
      (tester) async {
    await tester.pumpWidget(
      ChangeNotifierProvider<AccessibilityProvider>.value(
        value: accessibility,
        child: const MaterialApp(
          home: Scaffold(
            body: SettingsCard(
              children: [SettingsTextScaleTile()],
            ),
          ),
        ),
      ),
    );

    expect(accessibility.textScale, 100);

    final slider = find.byType(Slider);
    expect(slider, findsOneWidget);

    // Start a drag but do not end it.
    final center = tester.getCenter(slider);
    final gesture = await tester.startGesture(center);
    await gesture.moveBy(const Offset(80, 0));
    await tester.pump();

    // Live preview: the in-memory value follows the gesture immediately…
    expect(accessibility.textScale, greaterThan(100));
    // …but prefs are only written when the drag ends, never mid-gesture.
    expect(
      prefs.preferences
          .getInt(LocalStateKeys.textScale, defaultValue: 100)
          .getValue(),
      100,
    );

    // Completing the gesture commits.
    await gesture.up();
    await tester.pumpAndSettle();

    expect(accessibility.textScale, greaterThanOrEqualTo(100));
    expect(accessibility.textScale, lessThanOrEqualTo(200));
    expect(
      prefs.preferences
          .getInt(LocalStateKeys.textScale, defaultValue: 100)
          .getValue(),
      accessibility.textScale,
    );
  });

  testWidgets('TTS speed tile rebuilds label from SettingsProvider',
      (tester) async {
    await settings.setTtsSpeed(1.5);

    await tester.pumpWidget(
      ChangeNotifierProvider<SettingsProvider>.value(
        value: settings,
        child: const MaterialApp(
          home: Scaffold(
            body: SettingsCard(
              children: [SettingsTtsSpeedTile()],
            ),
          ),
        ),
      ),
    );

    // Label uses one-decimal formatting via AppStrings.
    expect(find.textContaining('1.5'), findsWidgets);

    await settings.setTtsSpeed(0.5);
    await tester.pump();
    expect(find.textContaining('0.5'), findsWidgets);
  });
}
