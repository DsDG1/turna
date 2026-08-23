// Flutter imports:
import 'package:flutter/foundation.dart';

// Package imports:
import 'package:injectable/injectable.dart';

// Project imports:
import 'package:turna/application/gems_provider.dart';
import 'package:turna/data/gem_ledger_dao.dart';
import 'package:turna/di/injection.dart';
import 'package:turna/domain/cosmetics/avatar_ring.dart';
import 'package:turna/service/locator.dart';

/// Result of [CosmeticProvider.unlockAndEquip].
enum CosmeticActionResult {
  equipped,
  unlockedAndEquipped,
  insufficientGems,
  unknownId,
}

/// Local-only cosmetic unlocks (avatar rings). Spends gems via [GemsProvider].
@lazySingleton
class CosmeticProvider extends ChangeNotifier {
  CosmeticProvider(this.appPrefs, this._gemsProvider);

  final AppPrefs appPrefs;
  final GemsProvider _gemsProvider;

  /// Serializes unlock/equip writes (and pairs with gem spends) so two taps
  /// cannot double-charge for the same ring.
  Future<void> _opChain = Future.value();

  Set<String> get unlockedIds {
    final stored = appPrefs.preferences
        .getStringList(LocalStateKeys.cosmeticsUnlocked, defaultValue: const [])
        .getValue()
        .toSet();
    stored.add(kAvatarRingMist);
    return stored;
  }

  String get equippedRingId {
    final id = appPrefs.preferences
        .getString(
          LocalStateKeys.cosmeticsEquippedRing,
          defaultValue: kAvatarRingMist,
        )
        .getValue();
    if (id.isEmpty) return kAvatarRingMist;
    return id;
  }

  AvatarRing get equippedRing =>
      CosmeticCatalog.ringById(equippedRingId) ?? CosmeticCatalog.defaultRing;

  bool isUnlocked(String id) {
    if (id == kAvatarRingMist) return true;
    return unlockedIds.contains(id);
  }

  bool isEquipped(String id) => equippedRingId == id;

  Future<void> equip(String id) async {
    await _enqueue(() async {
      if (!isUnlocked(id)) return;
      if (CosmeticCatalog.ringById(id) == null) return;
      await appPrefs.preferences
          .setString(LocalStateKeys.cosmeticsEquippedRing, id);
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
    late CosmeticActionResult outcome;
    await _enqueue(() async {
      final ring = CosmeticCatalog.ringById(id);
      if (ring == null) {
        outcome = CosmeticActionResult.unknownId;
        return;
      }

      if (isUnlocked(id)) {
        await appPrefs.preferences
            .setString(LocalStateKeys.cosmeticsEquippedRing, id);
        notifyListeners();
        outcome = CosmeticActionResult.equipped;
        return;
      }

      if (ring.price > 0) {
        final ledger = _resolveLedger();
        if (ledger != null) {
          final result = await ledger.purchase(
            itemId: id,
            price: ring.price,
            currentBalance: _gemsProvider.balance,
            catalogVersion: ring.catalogVersion,
          );
          if (result == GemPurchaseResult.insufficientFunds) {
            outcome = CosmeticActionResult.insufficientGems;
            return;
          }
          // success / alreadyOwned both proceed: the entitlement exists.
          final spent = await _gemsProvider.spendGems(ring.price);
          if (!spent) {
            // Wallet could not be charged (raced with a concurrent spend):
            // refund the ledger spend so the projection stays honest.
            await ledger.record(
              kind: GemLedgerKind.refund,
              amount: ring.price,
              reason: 'refund:$id wallet spend failed',
              itemId: id,
            );
            outcome = CosmeticActionResult.insufficientGems;
            return;
          }
        } else {
          // No ledger available (tests / DB not ready): legacy path only.
          final spent = await _gemsProvider.spendGems(ring.price);
          if (!spent) {
            outcome = CosmeticActionResult.insufficientGems;
            return;
          }
        }
      }

      final next = unlockedIds..add(id);
      await appPrefs.preferences.setStringList(
        LocalStateKeys.cosmeticsUnlocked,
        next.toList(growable: false),
      );
      await appPrefs.preferences
          .setString(LocalStateKeys.cosmeticsEquippedRing, id);
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
      notifyListeners();
    });
  }

  /// After external prefs restore (export import / Fun Lab).
  void refreshFromPrefs() {
    notifyListeners();
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
