// Consolidated tests for Gamification providers: GemsProvider and CosmeticProvider.

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:streaming_shared_preferences/streaming_shared_preferences.dart';
import 'package:turna/application/cosmetic_provider.dart';
import 'package:turna/application/gems_provider.dart';
import 'package:turna/di/injection.dart';
import 'package:turna/domain/cosmetics/avatar_ring.dart';
import 'package:turna/service/locator.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late AppPrefs prefs;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    final sp = await StreamingSharedPreferences.instance;
    prefs = AppPrefs(sp);
    await sp.remove(LocalStateKeys.gems);
    await sp.remove(LocalStateKeys.achievements);
    await sp.remove(LocalStateKeys.cosmeticsUnlocked);
    await sp.remove(LocalStateKeys.cosmeticsEquippedRing);
    if (getIt.isRegistered<GemsProvider>()) {
      await getIt.unregister<GemsProvider>();
    }
  });

  tearDown(() async {
    if (getIt.isRegistered<GemsProvider>()) {
      await getIt.unregister<GemsProvider>();
    }
  });

  int balance() =>
      prefs.preferences.getInt(LocalStateKeys.gems, defaultValue: -1).getValue();

  group('GemsProvider.spendGems', () {
    test('spendGems succeeds when balance is sufficient', () async {
      final gems = GemsProvider(prefs);
      await gems.addGems(50);
      final ok = await gems.spendGems(40);
      expect(ok, isTrue);
      expect(balance(), 10);
    });

    test('spendGems fails when balance is insufficient', () async {
      final gems = GemsProvider(prefs);
      await gems.addGems(10);
      final ok = await gems.spendGems(40);
      expect(ok, isFalse);
      expect(balance(), 10);
    });

    test('spendGems rejects non-positive amounts', () async {
      final gems = GemsProvider(prefs);
      await gems.addGems(10);
      expect(await gems.spendGems(0), isFalse);
      expect(await gems.spendGems(-5), isFalse);
      expect(balance(), 10);
    });

    test('concurrent spends cannot drive balance negative', () async {
      final gems = GemsProvider(prefs);
      await gems.addGems(50);
      final results = await Future.wait([
        gems.spendGems(40),
        gems.spendGems(40),
      ]);
      final successCount = results.where((ok) => ok).length;
      expect(successCount, 1);
      expect(balance(), 10);
    });
  });

  group('CosmeticProvider', () {
    late GemsProvider gems;
    late CosmeticProvider cosmetics;

    setUp(() async {
      await prefs.preferences.setInt(LocalStateKeys.gems, 0);
      await prefs.preferences
          .setStringList(LocalStateKeys.cosmeticsUnlocked, const <String>[]);
      await prefs.preferences.setString(
        LocalStateKeys.cosmeticsEquippedRing,
        kAvatarRingMist,
      );
      gems = GemsProvider(prefs);
      cosmetics = CosmeticProvider(prefs, gems);
    });

    test('mist ring is always unlocked and free to equip', () async {
      expect(cosmetics.isUnlocked(kAvatarRingMist), isTrue);
      final result = await cosmetics.unlockAndEquip(kAvatarRingMist);
      expect(result, CosmeticActionResult.equipped);
      expect(cosmetics.equippedRingId, kAvatarRingMist);
      expect(balance(), 0);
    });

    test('unlock reed spends 40 gems and equips', () async {
      await gems.addGems(50);
      final result = await cosmetics.unlockAndEquip(kAvatarRingReed);
      expect(result, CosmeticActionResult.unlockedAndEquipped);
      expect(cosmetics.isUnlocked(kAvatarRingReed), isTrue);
      expect(cosmetics.equippedRingId, kAvatarRingReed);
      expect(balance(), 10);
    });

    test('insufficient gems cannot unlock lake', () async {
      await gems.addGems(20);
      final result = await cosmetics.unlockAndEquip(kAvatarRingLake);
      expect(result, CosmeticActionResult.insufficientGems);
      expect(cosmetics.isUnlocked(kAvatarRingLake), isFalse);
      expect(cosmetics.equippedRingId, kAvatarRingMist);
      expect(balance(), 20);
    });

    test('re-equip unlocked ring does not charge again', () async {
      await gems.addGems(100);
      await cosmetics.unlockAndEquip(kAvatarRingReed);
      expect(balance(), 60);
      await cosmetics.unlockAndEquip(kAvatarRingMist);
      final again = await cosmetics.unlockAndEquip(kAvatarRingReed);
      expect(again, CosmeticActionResult.equipped);
      expect(balance(), 60);
    });

    test('resetCosmetics clears unlocks and restores mist', () async {
      await gems.addGems(100);
      await cosmetics.unlockAndEquip(kAvatarRingLake);
      expect(cosmetics.equippedRingId, kAvatarRingLake);

      await cosmetics.resetCosmetics();
      expect(cosmetics.equippedRingId, kAvatarRingMist);
      expect(cosmetics.isUnlocked(kAvatarRingLake), isFalse);
      expect(balance(), 20);
    });

    test('unknown id returns unknownId', () async {
      final result = await cosmetics.unlockAndEquip('ring_nope');
      expect(result, CosmeticActionResult.unknownId);
    });
  });
}
