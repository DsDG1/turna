import 'package:drift/drift.dart' show Variable;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:streaming_shared_preferences/streaming_shared_preferences.dart';
import 'package:turna/application/cosmetic_provider.dart';
import 'package:turna/application/gems_provider.dart';
import 'package:turna/data/course_database.dart';
import 'package:turna/data/gem_ledger_dao.dart';
import 'package:turna/di/injection.dart';
import 'package:turna/domain/cosmetics/avatar_ring.dart';
import 'package:turna/domain/cosmetics/cosmetic_item.dart';
import 'package:turna/service/locator.dart';

import '../helpers/in_memory_course_db.dart';

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
    await sp.remove(LocalStateKeys.cosmeticsEquippedAvatarRing);
    await sp.remove(LocalStateKeys.cosmeticsEquippedProfileTheme);
    await sp.remove(LocalStateKeys.cosmeticsEquippedCompletionEffect);
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

    test('legacy equipped ring migrates idempotently to slot key', () async {
      await prefs.preferences.setString(
        LocalStateKeys.cosmeticsEquippedRing,
        kAvatarRingReed,
      );
      await cosmetics.ensureInitialized();
      await cosmetics.ensureInitialized();

      expect(cosmetics.equippedRingId, kAvatarRingReed);
      expect(
        prefs.preferences
            .getString(
              LocalStateKeys.cosmeticsEquippedAvatarRing,
              defaultValue: '',
            )
            .getValue(),
        kAvatarRingReed,
      );
    });

    test('profile theme and completion effect buy and equip by slot',
        () async {
      await gems.addGems(300);
      expect(
        await cosmetics.unlockAndEquipItem(CosmeticItems.profileSunrise),
        CosmeticActionResult.unlockedAndEquipped,
      );
      expect(
        await cosmetics
            .unlockAndEquipItem(CosmeticItems.completionReedBloom),
        CosmeticActionResult.unlockedAndEquipped,
      );

      expect(
        cosmetics.equippedId(CosmeticSlot.profileTheme),
        CosmeticItems.profileSunrise,
      );
      expect(
        cosmetics.equippedId(CosmeticSlot.completionEffect),
        CosmeticItems.completionReedBloom,
      );
      expect(balance(), 80);
    });
  });

  test('every paid catalog item declares a primary-flow surface', () {
    expect(CosmeticCatalog.rings, hasLength(greaterThanOrEqualTo(6)));
    expect(
      CosmeticCatalog.itemsForSlot(CosmeticSlot.profileTheme),
      hasLength(greaterThanOrEqualTo(2)),
    );
    expect(
      CosmeticCatalog.itemsForSlot(CosmeticSlot.completionEffect),
      hasLength(greaterThanOrEqualTo(2)),
    );
    expect(CosmeticCatalog.hasValidSurfaceContracts, isTrue);
  });

  group('GemsProvider and Ledger synchronization', () {
    late CourseDatabase db;
    late GemLedgerDao ledger;
    late GemsProvider ledgerGems;

    setUp(() async {
      ensureSqliteLibForTestHost();
      db = CourseDatabase(NativeDatabase.memory());
      ledger = GemLedgerDao(db);
      if (getIt.isRegistered<GemLedgerDao>()) {
        await getIt.unregister<GemLedgerDao>();
      }
      getIt.registerSingleton<GemLedgerDao>(ledger);
      ledgerGems = GemsProvider(prefs);
    });

    tearDown(() async {
      ledgerGems.dispose();
      if (getIt.isRegistered<GemLedgerDao>()) {
        await getIt.unregister<GemLedgerDao>();
      }
      await db.close();
    });

    Future<int> countRows({required String kind, String? reasonPrefix}) async {
      final where =
          reasonPrefix == null ? 'kind = ?' : "kind = ? AND reason LIKE ? || '%'";
      final variables = <Object?>[
        kind,
        if (reasonPrefix != null) reasonPrefix,
      ];
      final rows = await db
          .customSelect(
            'SELECT COUNT(*) AS n FROM gem_ledger WHERE $where',
            variables: variables
                .map((value) => Variable<String>(value! as String))
                .toList(),
          )
          .get();
      return rows.single.read<int>('n');
    }

    test('startup migrates prefs and duplicate event id never double-credits',
        () async {
      await prefs.preferences.setInt(LocalStateKeys.gems, 20);
      await ledgerGems.ensureGemsInitialized();

      const eventId = 'earn:lesson:intro:2026-08-23';
      await ledgerGems.earnGems(GemEvent.lessonComplete, eventId: eventId);
      await ledgerGems.earnGems(GemEvent.lessonComplete, eventId: eventId);

      expect(ledgerGems.balance, 25);
      expect(await ledger.projectedBalance(), 25);
      expect(await countRows(kind: GemLedgerKind.earn.name), 1);
    });

    test('prefs above ledger creates explicit adjustment and converges',
        () async {
      await prefs.preferences.setInt(LocalStateKeys.gems, 20);
      await ledgerGems.ensureGemsInitialized();
      await prefs.preferences.setInt(LocalStateKeys.gems, 80);

      await ledgerGems.ensureGemsInitialized();

      expect(ledgerGems.lastReconciliationDifference, 60);
      expect(ledgerGems.balance, 80);
      expect(await ledger.projectedBalance(), 80);
      expect(
        await countRows(
          kind: GemLedgerKind.adjustment.name,
          reasonPrefix: 'reconcile:prefs_above_ledger',
        ),
        1,
      );
    });

    test('ledger above prefs wins and leaves a zero-value adjustment audit row',
        () async {
      await prefs.preferences.setInt(LocalStateKeys.gems, 20);
      await ledgerGems.ensureGemsInitialized();
      await ledgerGems.addGems(15);
      await prefs.preferences.setInt(LocalStateKeys.gems, 3);

      await ledgerGems.ensureGemsInitialized();

      expect(ledgerGems.lastReconciliationDifference, -32);
      expect(ledgerGems.balance, 35);
      expect(await ledger.projectedBalance(), 35);
      expect(
        await countRows(
          kind: GemLedgerKind.adjustment.name,
          reasonPrefix: 'reconcile:ledger_above_prefs',
        ),
        1,
      );
    });

    test('atomic cosmetic purchase is mirrored once, not charged twice',
        () async {
      await prefs.preferences.setInt(LocalStateKeys.gems, 100);
      await ledgerGems.ensureGemsInitialized();
      final cosmetics = CosmeticProvider(prefs, ledgerGems);

      expect(
        await cosmetics.unlockAndEquip(kAvatarRingReed),
        CosmeticActionResult.unlockedAndEquipped,
      );

      expect(ledgerGems.balance, 60);
      expect(await ledger.projectedBalance(), 60);
      expect(await countRows(kind: GemLedgerKind.spend.name), 1);
      expect(await ledger.hasEntitlement(kAvatarRingReed), isTrue);
      cosmetics.dispose();
    });
  });
}
