// Widget tests for the routed Settings landing (Plan §12): the landing page
// is a pure category list, every category is a real route pushed through the
// router, and external deep-links reach any category regardless of whether
// the Settings tab was visited before.

// Dart imports:
import 'dart:async';

// Flutter imports:
import 'package:flutter/material.dart';

// Package imports:
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:streaming_shared_preferences/streaming_shared_preferences.dart';
import 'package:flutter_tts/flutter_tts.dart';

// Project imports:
import 'package:turna/application/accessibility_provider.dart';
import 'package:turna/application/course_provider.dart';
import 'package:turna/application/language_provider.dart';
import 'package:turna/application/settings/settings_destination.dart';
import 'package:turna/application/settings_provider.dart';
import 'package:turna/application/streak_provider.dart';
import 'package:turna/application/theme_provider.dart';
import 'package:turna/di/injection.dart';
import 'package:turna/l10n/app_strings.dart';
import 'package:turna/routing/course_ready_guard.dart';
import 'package:turna/routing/routing.dart';
import 'package:turna/routing/routing.gr.dart';
import 'package:turna/service/locator.dart';
import 'package:turna/service/tab_router.dart';
import 'package:turna/service/tts_availability_checker.dart';
import 'package:turna/views/settings/settings_page.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late SettingsProvider settings;
  late AccessibilityProvider accessibility;
  late ThemeProvider theme;
  late LanguageProvider language;
  late AppRouter router;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    final sp = await StreamingSharedPreferences.instance;
    final prefs = AppPrefs(sp);
    // Splash (initial router page) resolves these post-frame in tests.
    getIt.registerSingleton<AppPrefs>(prefs);
    await prefs.preferences
        .setBool(LocalStateKeys.ttsAvailabilityPromptShown, true);
    settings = SettingsProvider(prefs);
    accessibility = AccessibilityProvider(prefs);
    theme = ThemeProvider(prefs);
    language = LanguageProvider(prefs);
    getIt.registerLazySingleton<TtsAvailabilityChecker>(
      () => TtsAvailabilityChecker(FlutterTts()),
    );
    getIt.registerLazySingleton<LanguageProvider>(
      () => LanguageProvider(prefs),
    );
    if (!getIt.isRegistered<TabRouter>()) {
      getIt.registerLazySingleton<TabRouter>(() => TabRouter());
    }
    // The learning page's streak-voucher tile resolves StreakProvider
    // through GetIt.
    if (!getIt.isRegistered<StreakProvider>()) {
      getIt.registerLazySingleton<StreakProvider>(() => StreakProvider(prefs));
    }
    router = AppRouter(CourseReadyGuard(CourseProvider()));
  });

  tearDown(() {
    router.dispose();
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
        ChangeNotifierProvider<LanguageProvider>.value(value: language),
      ],
      child: MaterialApp(home: child),
    );
  }

  Widget wrapRouter() {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider<SettingsProvider>.value(value: settings),
        ChangeNotifierProvider<AccessibilityProvider>.value(
          value: accessibility,
        ),
        ChangeNotifierProvider<ThemeProvider>.value(value: theme),
        ChangeNotifierProvider<LanguageProvider>.value(value: language),
      ],
      child: MaterialApp.router(routerConfig: router.config()),
    );
  }

  /// Mounts the router WITHOUT the splash page (its animation cycle timer
  /// would leave fake-async pending timers): pump once, then replace the
  /// initial route with the About settings page.
  Future<void> pumpOnAbout(WidgetTester tester) async {
    await tester.pumpWidget(wrapRouter());
    await tester.pump();
    await router.replaceAll([const AboutSettingsRoute()]);
    await tester.pumpAndSettle();
  }

  testWidgets('landing shows personal summary, quick states and destinations',
      (tester) async {
    await tester.pumpWidget(wrap(const SettingsPage()));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('settings-personal-summary')), findsOneWidget);
    expect(find.text(AppStrings.settingsLandingQuickTitle), findsOneWidget);
    expect(find.text(AppStrings.settingsGroupLearning), findsOneWidget);
    expect(find.text(AppStrings.settingsGroupDataSystem), findsOneWidget);

    // Lightweight current values; no destination page needs to be opened.
    expect(find.text('Turkish'), findsOneWidget);
    expect(find.text(AppStrings.settingsThemeSystem), findsOneWidget);
    expect(find.text(AppStrings.settingsLandingReminderOff), findsOneWidget);
    expect(find.text(AppStrings.settingsTextSizeValue(100)), findsOneWidget);

    // The seven formal destinations.
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
  });

  testWidgets('landing adapts to 200 percent text without overflow',
      (tester) async {
    await tester.pumpWidget(
      wrap(
        const MediaQuery(
          data: MediaQueryData(textScaler: TextScaler.linear(2)),
          child: SettingsPage(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.text(AppStrings.settingsLandingQuickTitle), findsOneWidget);
  });

  testWidgets('landing list has a stable PageStorageKey for scroll restore',
      (tester) async {
    await tester.pumpWidget(wrap(const SettingsPage()));
    await tester.pumpAndSettle();
    expect(
      find.byKey(const PageStorageKey<String>('settings-landing-list')),
      findsOneWidget,
    );
  });

  testWidgets('appearance page holds audio, not a11y toggles', (tester) async {
    await pumpOnAbout(tester);
    unawaited(router.push(SettingsDestination.appearanceAndSound.route));
    await tester.pumpAndSettle();

    expect(find.text(AppStrings.settingsAudioSectionTitle), findsOneWidget);
    expect(find.text(AppStrings.settingsA11ySectionTitle), findsNothing);
  });

  testWidgets('accessibility page holds reading/sensory toggles',
      (tester) async {
    await pumpOnAbout(tester);
    unawaited(router.push(SettingsDestination.accessibility.route));
    await tester.pumpAndSettle();

    expect(find.text(AppStrings.settingsA11ySectionTitle), findsOneWidget);
    expect(find.text(AppStrings.settingsAudioSectionTitle), findsNothing);
  });

  testWidgets(
      'advanced hub shows four entries; legacy tunables live on their own route',
      (tester) async {
    await pumpOnAbout(tester);
    unawaited(router.push(SettingsDestination.advanced.route));
    await tester.pumpAndSettle();

    expect(find.text(AppStrings.settingsAdvancedAiConnectionTitle),
        findsOneWidget);
    expect(find.text(AppStrings.settingsAdvancedStorageTitle), findsOneWidget);
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
    expect(
        find.text(AppStrings.settingsLegacyResetDefaultsTitle), findsWidgets);

    // Back returns to the advanced hub, not the landing list.
    await tester.pageBack();
    await tester.pumpAndSettle();
    expect(find.text(AppStrings.settingsAdvancedAiConnectionTitle),
        findsOneWidget);
  });

  testWidgets('system back from a category pops the routed page',
      (tester) async {
    // The learning page needs the full AnkiDeckManager graph from GetIt;
    // navigation semantics are identical for every category, so the
    // accessibility page (same scaffold, no extra DI) stands in here.
    await pumpOnAbout(tester);
    unawaited(router.push(SettingsDestination.accessibility.route));
    await tester.pumpAndSettle();
    expect(find.text(AppStrings.settingsA11ySectionTitle), findsOneWidget);

    await router.maybePop();
    await tester.pumpAndSettle();
    expect(find.text(AppStrings.settingsA11ySectionTitle), findsNothing);
  });

  testWidgets('openSettings switches tab and pushes the target route',
      (tester) async {
    await pumpOnAbout(tester);

    final ctx = tester.element(find.byType(Navigator).first);
    // openSettings awaits the pushed route's pop future by design; callers
    // that only need the navigation started (like this test) fire-and-pump.
    unawaited(openSettings(ctx, SettingsDestination.dataAndBackup));
    await tester.pumpAndSettle();

    expect(
      find.text(AppStrings.settingsExportDataTitle),
      findsOneWidget,
      reason: 'deep link should land directly on the data & backup page',
    );
    expect(find.text(AppStrings.settingsLearningRecordsTitle), findsOneWidget);
    expect(find.text(AppStrings.settingsDangerZoneTitle), findsOneWidget);
    expect(find.text(AppStrings.accountResetTitle), findsOneWidget);
  });
}
