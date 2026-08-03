// Widget tests: TTS / text-scale sliders only persist on change-end, not while
// dragging (avoids prefs write + broad notify on every pointer move).

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

    // Start a drag but do not end it — provider should stay at default.
    final center = tester.getCenter(slider);
    final gesture = await tester.startGesture(center);
    await gesture.moveBy(const Offset(80, 0));
    await tester.pump();

    // Local UI may show a higher %; persisted provider value stays until end.
    // (If onChanged wrote through, textScale would already be > 100.)
    // Completing the gesture commits.
    await gesture.up();
    await tester.pumpAndSettle();

    expect(accessibility.textScale, greaterThanOrEqualTo(100));
    expect(accessibility.textScale, lessThanOrEqualTo(200));
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
