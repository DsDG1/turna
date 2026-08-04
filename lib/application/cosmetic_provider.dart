// Flutter imports:
import 'package:flutter/foundation.dart';

// Package imports:
import 'package:injectable/injectable.dart';

// Project imports:
import 'package:turna/application/gems_provider.dart';
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
        final spent = await _gemsProvider.spendGems(ring.price);
        if (!spent) {
          outcome = CosmeticActionResult.insufficientGems;
          return;
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
