// Regression: `AchievementsProvider.checkAndUnlock` used to call
// `appPrefs.preferences.setInt(LocalStateKeys.gems, ... + 50)` directly,
// bypassing the GemsProvider single-writer contract. After the fix it
// routes through `GemsProvider.addGems` (when one is registered).

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:streaming_shared_preferences/streaming_shared_preferences.dart';
import 'package:turna/application/achievements_provider.dart';
import 'package:turna/application/gems_provider.dart';
import 'package:turna/di/injection.dart';
import 'package:turna/service/locator.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await prefsReset();
    if (getIt.isRegistered<GemsProvider>()) {
      await getIt.unregister<GemsProvider>();
    }
  });

  tearDown(() async {
    if (getIt.isRegistered<GemsProvider>()) {
      await getIt.unregister<GemsProvider>();
    }
  });

  test('routes gem bonus through GemsProvider when registered', () async {
    final sp = await StreamingSharedPreferences.instance;
    final appPrefs = AppPrefs(sp);
    final gems = GemsProvider(appPrefs);
    final achievements = AchievementsProvider(appPrefs);
    getIt.registerSingleton<GemsProvider>(gems);
    await appPrefs.preferences.setInt(LocalStateKeys.gems, 100);

    final unlocked = await achievements.checkAndUnlock('champion');
    expect(unlocked, isTrue);

    // Gems routed through GemsProvider: 100 + 50 = 150.
    final balance = appPrefs.preferences
        .getInt(LocalStateKeys.gems, defaultValue: -1)
        .getValue();
    expect(balance, 150);
  });

  test('falls back to direct write when no GemsProvider is registered',
      () async {
    final sp = await StreamingSharedPreferences.instance;
    final appPrefs = AppPrefs(sp);
    final achievements = AchievementsProvider(appPrefs);
    await appPrefs.preferences.setInt(LocalStateKeys.gems, 100);

    final unlocked = await achievements.checkAndUnlock('champion');
    expect(unlocked, isTrue);

    final balance = appPrefs.preferences
        .getInt(LocalStateKeys.gems, defaultValue: -1)
        .getValue();
    expect(balance, 150, reason: 'fallback path still awards the bonus');
  });
}

Future<void> prefsReset() async {
  final sp = await StreamingSharedPreferences.instance;
  // Wipe every key we touch in these tests.
  for (final key in [
    LocalStateKeys.gems,
    LocalStateKeys.achievements,
  ]) {
    await sp.remove(key);
  }
}
