// Flutter imports:
import 'package:flutter/material.dart';

/// Free default ring id — always treated as unlocked.
const String kAvatarRingMist = 'ring_mist';

const String kAvatarRingReed = 'ring_reed';
const String kAvatarRingLake = 'ring_lake';

/// One equippable avatar ring (cosmetic only).
class AvatarRing {
  final String id;
  final int price;

  /// Border color; `null` means no accent ring (default mist).
  /// Hex values match Turna wetland tokens (reed / teal) without importing UI.
  final Color? borderColor;

  /// Border width when [borderColor] is non-null.
  final double borderWidth;

  const AvatarRing({
    required this.id,
    required this.price,
    this.borderColor,
    this.borderWidth = 2,
  });

  bool get isFree => price <= 0;
}

/// Static catalog for step-1 avatar rings (no network, no bitmap assets).
class CosmeticCatalog {
  CosmeticCatalog._();

  /// brandReed `#78C7B8`
  static const Color _reed = Color(0xFF78C7B8);

  /// brandTeal `#1F727E`
  static const Color _teal = Color(0xFF1F727E);

  static const List<AvatarRing> rings = [
    AvatarRing(id: kAvatarRingMist, price: 0),
    AvatarRing(
      id: kAvatarRingReed,
      price: 40,
      borderColor: _reed,
      borderWidth: 2.5,
    ),
    AvatarRing(
      id: kAvatarRingLake,
      price: 80,
      borderColor: _teal,
      borderWidth: 2.5,
    ),
  ];

  static AvatarRing? ringById(String id) {
    for (final ring in rings) {
      if (ring.id == id) return ring;
    }
    return null;
  }

  static AvatarRing get defaultRing => rings.first;
}
