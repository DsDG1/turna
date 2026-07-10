// Tests for the service-locator / DI bootstrapping contract.
//
// `SettingsProvider` is NOT annotated with @lazySingleton and is instead
// registered manually in main.dart AFTER setupLocator(). This is why
// AudioController guards every access with `getIt.isRegistered<SettingsProvider>()`.
// These tests pin the current contract so the Phase 3 refactor (moving
// SettingsProvider into the Injectable graph) has a regression guard and a
// clear place to update.

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:streaming_shared_preferences/streaming_shared_preferences.dart';
import 'package:varnamala/application/settings_provider.dart';
import 'package:varnamala/di/injection.dart';
import 'package:varnamala/service/locator.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late StreamingSharedPreferences sp;

  setUp(() async {
    await getIt.reset();
    SharedPreferences.setMockInitialValues({});
    sp = await StreamingSharedPreferences.instance;
  });

  tearDown(() async {
    await getIt.reset();
  });

  /// Mirrors the registration order in main.dart + setupLocator, skipping the
  /// course-database preload (platform channels unavailable in unit tests).
  Future<void> bootstrapWithoutDb() async {
    // configureDependencies() now registers SettingsProvider itself via the
    // @lazySingleton annotation, so it is part of the Injectable graph.
    configureDependencies();
    getIt.registerLazySingleton<AppPrefs>(() => AppPrefs(sp));
    getIt.registerLazySingleton<FlutterTts>(() => FlutterTts());
  }

  test('SettingsProvider is registered as a lazySingleton in the Injectable '
      'graph (no longer a manual main.dart registration)', () async {
    await bootstrapWithoutDb();
    expect(getIt.isRegistered<SettingsProvider>(), isTrue);
    expect(getIt.isRegistered<AppPrefs>(), isTrue);
  });

  test('SettingsProvider resolves to a single instance (singleton identity)',
      () async {
    await bootstrapWithoutDb();
    expect(
      identical(getIt<SettingsProvider>(), getIt<SettingsProvider>()),
      isTrue,
    );
  });

  test('SettingsProvider reads persisted settings from the AppPrefs it owns',
      () async {
    // Persist a non-default ttsSpeed before bootstrapping.
    await sp.setDouble(LocalStateKeys.ttsSpeed, 1.5);
    await sp.setBool(LocalStateKeys.soundEffects, false);
    await bootstrapWithoutDb();

    final settings = getIt<SettingsProvider>();
    expect(settings.ttsSpeed, 1.5);
    expect(settings.soundEffectsEnabled, isFalse);
  });

  test('AudioController no longer needs the isRegistered guard once '
      'SettingsProvider is in the graph', () async {
    // Contract guard: after the Phase 3 refactor lands, this assertion
    // documents that SettingsProvider is always registered before any
    // AudioController is constructed. Today the guard exists; once
    // SettingsProvider moves into injection.config.dart, getIt<SettingsProvider>()
    // must still resolve here without throwing.
    await bootstrapWithoutDb();
    expect(() => getIt<SettingsProvider>(), returnsNormally);
  });
}