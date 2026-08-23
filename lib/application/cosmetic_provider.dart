// Flutter imports:
import 'package:flutter/foundation.dart';

// Package imports:
import 'package:injectable/injectable.dart';

// Project imports:
import 'package:turna/application/diagnostics/storage_write_telemetry.dart';
import 'package:turna/application/gems_provider.dart';
import 'package:turna/data/gem_ledger_dao.dart';
import 'package:turna/di/injection.dart';
import 'package:turna/domain/cosmetics/avatar_ring.dart';
import 'package:turna/domain/cosmetics/cosmetic_item.dart';
import 'package:turna/service/locator.dart';

/// Result of [CosmeticProvider.unlockAndEquip].
enum CosmeticActionResult {
  equipped,
  unlockedAndEquipped,
  insufficientGems,
  unknownId,
}

/// Slot-based cosmetic entitlements and equipment state.
@lazySingleton
class CosmeticProvider extends ChangeNotifier {
  CosmeticProvider(this.appPrefs, this._gemsProvider);

  final AppPrefs appPrefs;
  final GemsProvider _gemsProvider;

  /// Serializes unlock/equip writes (and pairs with gem spends) so two taps
  /// cannot double-charge for the same ring.
  Future<void> _opChain = Future.value();
  Set<String> _ledgerEntitlements = const {};

  Future<void> ensureInitialized() async {
    await _enqueue(() async {
      final keys = appPrefs.preferences.getKeys().getValue();
      if (!keys.contains(LocalStateKeys.cosmeticsEquippedAvatarRing)) {
        final legacy = appPrefs.preferences
            .getString(
              LocalStateKeys.cosmeticsEquippedRing,
              defaultValue: kAvatarRingMist,
            )
            .getValue();
        await _writeEquipment(
          CosmeticSlot.avatarRing,
          CosmeticCatalog.ringById(legacy) == null ? kAvatarRingMist : legacy,
        );
      }
      final ledger = _resolveLedger();
      if (ledger != null) {
        _ledgerEntitlements = await ledger.entitledItemIds();
        await _mirrorUnlocks();
      }
      notifyListeners();
    });
  }

  Set<String> get unlockedIds {
    final stored = appPrefs.preferences
        .getStringList(LocalStateKeys.cosmeticsUnlocked, defaultValue: const [])
        .getValue()
        .toSet();
    stored.addAll(_ledgerEntitlements);
    stored.addAll(
      CosmeticCatalog.items.where((item) => item.isFree).map((item) => item.id),
    );
    return stored;
  }

  String get equippedRingId {
    final id = appPrefs.preferences
        .getString(
          LocalStateKeys.cosmeticsEquippedAvatarRing,
          defaultValue: appPrefs.preferences
              .getString(
                LocalStateKeys.cosmeticsEquippedRing,
                defaultValue: kAvatarRingMist,
              )
              .getValue(),
        )
        .getValue();
    if (id.isEmpty) return kAvatarRingMist;
    return id;
  }

  AvatarRing get equippedRing =>
      CosmeticCatalog.ringById(equippedRingId) ?? CosmeticCatalog.defaultRing;

  Map<CosmeticSlot, String> get equippedIds => {
        for (final slot in CosmeticSlot.values)
          if (equippedId(slot) case final String id) slot: id,
      };

  String? equippedId(CosmeticSlot slot) {
    if (slot == CosmeticSlot.avatarRing) return equippedRingId;
    final value = appPrefs.preferences
        .getString(_equipmentKey(slot), defaultValue: '')
        .getValue();
    return value.isEmpty ? null : value;
  }

  CosmeticItem? equippedItem(CosmeticSlot slot) {
    final id = equippedId(slot);
    return id == null ? null : CosmeticCatalog.itemById(id);
  }

  bool isUnlocked(String id) {
    if (id == kAvatarRingMist) return true;
    return unlockedIds.contains(id);
  }

  bool isEquipped(String id) => equippedRingId == id;

  bool isItemEquipped(String id) {
    final item = CosmeticCatalog.itemById(id);
    return item != null && equippedId(item.slot) == id;
  }

  Future<void> equip(String id) async {
    await equipItem(id);
  }

  Future<void> equipItem(String id) async {
    await _enqueue(() async {
      final item = CosmeticCatalog.itemById(id);
      if (item == null || !isUnlocked(id)) return;
      await _writeEquipment(item.slot, id);
      notifyListeners();
    });
  }

  /// Unlock (if needed) then equip. Free rings skip the gem spend.
  ///
  /// Paid rings go through the transactional ledger (Plan 2 §8.4): the spend
  /// row and the entitlement commit atomically, so a crash can no longer
  /// produce "gems deducted but item locked". The legacy prefs unlock list is
  /// still mirrored for existing readers until the shop consumes the ledger
  /// directly.
  Future<CosmeticActionResult> unlockAndEquip(String id) async {
    if (CosmeticCatalog.ringById(id) == null) {
      return CosmeticActionResult.unknownId;
    }
    return unlockAndEquipItem(id);
  }

  Future<CosmeticActionResult> unlockAndEquipItem(String id) async {
    late CosmeticActionResult outcome;
    await _enqueue(() async {
      final item = CosmeticCatalog.itemById(id);
      if (item == null) {
        outcome = CosmeticActionResult.unknownId;
        return;
      }

      if (isUnlocked(id)) {
        await _writeEquipment(item.slot, id);
        notifyListeners();
        outcome = CosmeticActionResult.equipped;
        return;
      }

      if (item.price > 0) {
        final ledger = _resolveLedger();
        if (ledger != null) {
          final result = await ledger.purchase(
            itemId: id,
            price: item.price,
            currentBalance: _gemsProvider.balance,
            catalogVersion: item.catalogVersion,
          );
          if (result == GemPurchaseResult.insufficientFunds) {
            outcome = CosmeticActionResult.insufficientGems;
            return;
          }
          // The purchase transaction already contains the spend fact. Mirror
          // its projection into prefs; never append a second wallet spend.
          await _gemsProvider.refreshFromLedger();
          _ledgerEntitlements = await ledger.entitledItemIds();
        } else {
          // No ledger available (tests / DB not ready): legacy path only.
          final spent = await _gemsProvider.spendGems(item.price);
          if (!spent) {
            outcome = CosmeticActionResult.insufficientGems;
            return;
          }
        }
      }

      await _mirrorUnlocks(extra: {id});
      await _writeEquipment(item.slot, id);
      notifyListeners();
      outcome = CosmeticActionResult.unlockedAndEquipped;
    });
    return outcome;
  }

  GemLedgerDao? _resolveLedger() {
    if (!getIt.isRegistered<GemLedgerDao>()) return null;
    try {
      return getIt<GemLedgerDao>();
    } catch (_) {
      return null;
    }
  }

  /// Account reset: clear unlocks and equip default mist ring.
  Future<void> resetCosmetics() async {
    await _enqueue(() async {
      await appPrefs.preferences
          .setStringList(LocalStateKeys.cosmeticsUnlocked, const <String>[]);
      await appPrefs.preferences.setString(
        LocalStateKeys.cosmeticsEquippedRing,
        kAvatarRingMist,
      );
      for (final slot in CosmeticSlot.values) {
        await appPrefs.preferences.remove(_equipmentKey(slot));
      }
      await _writeEquipment(CosmeticSlot.avatarRing, kAvatarRingMist);
      _ledgerEntitlements = const {};
      notifyListeners();
    });
  }

  /// After external prefs restore (export import / Fun Lab).
  void refreshFromPrefs() {
    notifyListeners();
  }

  Future<void> _mirrorUnlocks({Set<String> extra = const {}}) async {
    final next = appPrefs.preferences
        .getStringList(LocalStateKeys.cosmeticsUnlocked, defaultValue: const [])
        .getValue()
        .toSet()
      ..addAll(_ledgerEntitlements)
      ..addAll(extra);
    await appPrefs.preferences.setStringList(
      LocalStateKeys.cosmeticsUnlocked,
      next.toList(growable: false),
    );
  }

  static String _equipmentKey(CosmeticSlot slot) => switch (slot) {
        CosmeticSlot.avatarRing => LocalStateKeys.cosmeticsEquippedAvatarRing,
        CosmeticSlot.profileTheme =>
          LocalStateKeys.cosmeticsEquippedProfileTheme,
        CosmeticSlot.cardBack => LocalStateKeys.cosmeticsEquippedCardBack,
        CosmeticSlot.completionEffect =>
          LocalStateKeys.cosmeticsEquippedCompletionEffect,
        CosmeticSlot.soundPack => LocalStateKeys.cosmeticsEquippedSoundPack,
        CosmeticSlot.mascotAccessory =>
          LocalStateKeys.cosmeticsEquippedMascotAccessory,
      };

  Future<void> _writeEquipment(CosmeticSlot slot, String id) async {
    final key = _equipmentKey(slot);
    final stopwatch = Stopwatch()..start();
    await appPrefs.preferences.setString(key, id);
    stopwatch.stop();
    StorageWriteTelemetry.instance.record(
      key: key,
      estimatedBytes: id.codeUnits.length,
      elapsed: stopwatch.elapsed,
    );
  }

  Future<void> _enqueue(Future<void> Function() op) {
    _opChain = _opChain.then((_) => op()).catchError((Object e) {
      assert(() {
        // ignore: avoid_print
        print('CosmeticProvider op failed: $e');
        return true;
      }());
    });
    return _opChain;
  }
}
