// Unit tests for GemsProvider.spendGems.

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:streaming_shared_preferences/streaming_shared_preferences.dart';
import 'package:turna/application/gems_provider.dart';
import 'package:turna/service/locator.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late AppPrefs prefs;
  late GemsProvider gems;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    final sp = await StreamingSharedPreferences.instance;
    prefs = AppPrefs(sp);
    await prefs.preferences.setInt(LocalStateKeys.gems, 0);
    gems = GemsProvider(prefs);
  });

  int balance() =>
      prefs.preferences.getInt(LocalStateKeys.gems, defaultValue: -1).getValue();

  test('spendGems succeeds when balance is sufficient', () async {
    await gems.addGems(50);
    final ok = await gems.spendGems(40);
    expect(ok, isTrue);
    expect(balance(), 10);
  });

  test('spendGems fails when balance is insufficient', () async {
    await gems.addGems(10);
    final ok = await gems.spendGems(40);
    expect(ok, isFalse);
    expect(balance(), 10);
  });

  test('spendGems rejects non-positive amounts', () async {
    await gems.addGems(10);
    expect(await gems.spendGems(0), isFalse);
    expect(await gems.spendGems(-5), isFalse);
    expect(balance(), 10);
  });

  test('concurrent spends cannot drive balance negative', () async {
    await gems.addGems(50);
    // Two spends of 40 against 50 — only one should succeed.
    final results = await Future.wait([
      gems.spendGems(40),
      gems.spendGems(40),
    ]);
    final successCount = results.where((ok) => ok).length;
    expect(successCount, 1);
    expect(balance(), 10);
  });
}
