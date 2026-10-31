// Gate tests for the 跟读 (mic recognition) master switch, ADR 0061: the
// switch is opt-in and default off, and a DI-less environment (unit tests
// without the provider graph) reads as off so read-aloud cards degrade
// instead of throwing — same defensive contract as the TTS gate tests.

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:streaming_shared_preferences/streaming_shared_preferences.dart';
import 'package:turna/application/read_aloud_gate.dart';
import 'package:turna/application/settings_provider.dart';
import 'package:turna/di/injection.dart';
import 'package:turna/service/locator.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late AppPrefs prefs;
  late SettingsProvider settings;

  setUp(() async {
    await getIt.reset();
    SharedPreferences.setMockInitialValues({});
    final streaming = await StreamingSharedPreferences.instance;
    prefs = AppPrefs(streaming);
    settings = SettingsProvider(prefs);
    getIt.registerSingleton<SettingsProvider>(settings);
  });

  tearDown(getIt.reset);

  test('default is off', () {
    expect(settings.readAloudExercisesEnabled, isFalse);
    expect(readAloudExercisesEnabled(), isFalse);
  });

  test('persisted on survives a provider rebuild', () async {
    await settings.setReadAloudExercisesEnabled(true);
    expect(readAloudExercisesEnabled(), isTrue);

    // A second provider over the same prefs (the restart equivalent).
    final reloaded = SettingsProvider(prefs);
    expect(reloaded.readAloudExercisesEnabled, isTrue);
  });

  test('reads off when SettingsProvider is not registered', () async {
    await getIt.reset();
    expect(readAloudExercisesEnabled(), isFalse);
  });

  test('reset learning defaults does not touch the switch', () async {
    await settings.setReadAloudExercisesEnabled(true);
    await settings.resetLearningDefaults();
    expect(settings.readAloudExercisesEnabled, isTrue);
  });
}
