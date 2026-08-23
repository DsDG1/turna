// Widget test: settings landing uses the typed 7-destination IA (Plan 2 §5)
// with the new groups, hides the removed AI-tools category, splits
// appearance/sound from accessibility, and supports deep navigation via
// SettingsNavController.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:streaming_shared_preferences/streaming_shared_preferences.dart';
import 'package:turna/application/accessibility_provider.dart';
import 'package:turna/application/settings/settings_destination.dart';
import 'package:turna/application/settings_provider.dart';
import 'package:turna/application/theme_provider.dart';
import 'package:turna/di/injection.dart';
import 'package:turna/l10n/app_strings.dart';
import 'package:turna/application/language_provider.dart';
import 'package:turna/service/locator.dart';
import 'package:turna/service/tts_availability_checker.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:turna/views/settings/settings_page.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late SettingsProvider settings;
  late AccessibilityProvider accessibility;
  late ThemeProvider theme;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    final sp = await StreamingSharedPreferences.instance;
    final prefs = AppPrefs(sp);
    settings = SettingsProvider(prefs);
    accessibility = AccessibilityProvider(prefs);
    theme = ThemeProvider(prefs);
    // The appearance page's TTS engine tile resolves these from getIt.
    getIt.registerLazySingleton<TtsAvailabilityChecker>(
      () => TtsAvailabilityChecker(FlutterTts()),
    );
    getIt.registerLazySingleton<LanguageProvider>(
      () => LanguageProvider(prefs),
    );
  });

  tearDown(() {
    if (getIt.isRegistered<TtsAvailabilityChecker>()) {
      getIt.reset();
    }
  });

  Widget wrap(Widget child) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider<SettingsProvider>.value(value: settings),
        ChangeNotifierProvider<AccessibilityProvider>.value(
          value: accessibility,
        ),
        ChangeNotifierProvider<ThemeProvider>.value(value: theme),
      ],
      child: MaterialApp(home: child),
    );
  }

  testWidgets('landing shows the 7 formal destinations in 4 groups',
      (tester) async {
    await tester.pumpWidget(wrap(const SettingsPage()));
    await tester.pumpAndSettle();

    expect(find.text(AppStrings.settingsGroupPersonal), findsOneWidget);
    expect(find.text(AppStrings.settingsGroupLearning), findsOneWidget);
    expect(find.text(AppStrings.settingsGroupDataSystem), findsOneWidget);
    expect(find.text(AppStrings.settingsGroupProduct), findsOneWidget);

    // The seven formal destinations (account, learning, appearance&sound,
    // accessibility, data&backup, advanced, about).
    expect(find.text(AppStrings.settingsCategoryAccount), findsOneWidget);
    expect(find.text(AppStrings.settingsCategoryLearning), findsOneWidget);
    expect(
      find.text(AppStrings.settingsCategoryAppearanceSound),
      findsOneWidget,
    );
    expect(find.text(AppStrings.settingsCategoryAccessibility), findsOneWidget);
    expect(find.text(AppStrings.settingsCategoryDataBackup), findsOneWidget);
    expect(find.text(AppStrings.settingsCategoryAdvanced), findsOneWidget);
    expect(find.text(AppStrings.settingsCategoryAbout), findsOneWidget);

    // Removed categories must not exist anywhere on the landing page.
    expect(find.textContaining('AI 工具'), findsNothing);
    expect(find.text('趣味实验室'), findsNothing);
  });

  testWidgets('appearance&sound and accessibility are separate sub-pages',
      (tester) async {
    await tester.pumpWidget(wrap(const SettingsPage()));
    await tester.pumpAndSettle();

    // Appearance & sound holds theme + audio; not the a11y toggles.
    final appearance = find.text(AppStrings.settingsCategoryAppearanceSound);
    await tester.ensureVisible(appearance);
    await tester.tap(appearance);
    await tester.pumpAndSettle();
    expect(find.text(AppStrings.settingsAudioSectionTitle), findsOneWidget);
    expect(find.text(AppStrings.settingsA11ySectionTitle), findsNothing);

    // Back to landing, then accessibility holds the reading/sensory toggles.
    await tester.tap(find.byIcon(Icons.arrow_back_rounded));
    await tester.pumpAndSettle();

    final a11y = find.text(AppStrings.settingsCategoryAccessibility);
    await tester.ensureVisible(a11y);
    await tester.tap(a11y);
    await tester.pumpAndSettle();
    expect(find.text(AppStrings.settingsA11ySectionTitle), findsOneWidget);
    expect(find.text(AppStrings.settingsAudioSectionTitle), findsNothing);

    await tester.tap(find.byIcon(Icons.arrow_back_rounded));
    await tester.pumpAndSettle();
    expect(find.text(AppStrings.settingsTitle), findsOneWidget);
  });

  testWidgets('advanced hub shows four entries and in-page legacy page',
      (tester) async {
    await tester.pumpWidget(wrap(const SettingsPage()));
    await tester.pumpAndSettle();

    final advanced = find.text(AppStrings.settingsCategoryAdvanced);
    await tester.ensureVisible(advanced);
    await tester.tap(advanced);
    await tester.pumpAndSettle();

    expect(find.text(AppStrings.settingsAdvancedAiConnectionTitle),
        findsOneWidget);
    expect(
        find.text(AppStrings.settingsAdvancedStorageTitle), findsOneWidget);
    expect(find.text(AppStrings.settingsAdvancedSystemHealthTitle),
        findsOneWidget);
    expect(find.text(AppStrings.settingsAdvancedLegacyTitle), findsOneWidget);

    // The legacy tunables live on the second-level page, not the hub.
    expect(find.text(AppStrings.settingsLegacyDecryptTitle), findsNothing);

    final legacy = find.text(AppStrings.settingsAdvancedLegacyTitle);
    await tester.ensureVisible(legacy);
    await tester.tap(legacy);
    await tester.pumpAndSettle();
    expect(find.text(AppStrings.settingsLegacyDecryptTitle), findsOneWidget);
    expect(
        find.text(AppStrings.settingsLegacyCaptureDelayTitle), findsOneWidget);
    expect(find.text(AppStrings.settingsLegacyForceDisableJsTitle),
        findsOneWidget);
    expect(
        find.text(AppStrings.settingsLegacyLiteThresholdTitle), findsOneWidget);
    expect(find.text(AppStrings.settingsLegacyResetDefaultsTitle),
        findsWidgets);

    // Back returns to the advanced hub, not the landing list.
    await tester.tap(find.byIcon(Icons.arrow_back_rounded));
    await tester.pumpAndSettle();
    expect(find.text(AppStrings.settingsAdvancedAiConnectionTitle),
        findsOneWidget);
  });

  testWidgets('external SettingsNavRequest opens the destination directly',
      (tester) async {
    final controller = SettingsNavController();
    getIt.registerSingleton<SettingsNavController>(controller);
    addTearDown(() => getIt.reset());

    await tester.pumpWidget(wrap(const SettingsPage()));
    await tester.pumpAndSettle();

    controller.open(const SettingsNavRequest(
      destination: SettingsDestination.advanced,
      anchor: SettingsAdvancedAnchor.legacyCompatibility,
    ));
    await tester.pumpAndSettle();

    // Landed on Advanced -> 旧版与兼容性 without any manual taps.
    expect(find.text(AppStrings.settingsLegacyDecryptTitle), findsOneWidget);
  });
}
