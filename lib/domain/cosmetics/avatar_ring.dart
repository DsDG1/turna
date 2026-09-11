// Flutter imports:
import 'package:flutter/material.dart';
import 'package:turna/domain/cosmetics/cosmetic_item.dart';

/// Free default ring id — always treated as unlocked.
const String kAvatarRingMist = 'ring_mist';

const String kAvatarRingReed = 'ring_reed';
const String kAvatarRingLake = 'ring_lake';
const String kAvatarRingSunset = 'ring_sunset';
const String kAvatarRingAurora = 'ring_aurora';
const String kAvatarRingObsidian = 'ring_obsidian';

/// One equippable avatar ring (cosmetic only).
class AvatarRing {
  final String id;
  final int price;

  /// Catalog revision the item definition belongs to (entitlement rows
  /// persist it so future catalog reshuffles can be reasoned about).
  final int catalogVersion;

  /// Border color; `null` means no accent ring (default mist).
  /// Hex values match Turna wetland tokens (reed / teal) without importing UI.
  final Color? borderColor;

  /// Border width when [borderColor] is non-null.
  final double borderWidth;

  const AvatarRing({
    required this.id,
    required this.price,
    this.catalogVersion = 1,
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
  static const Color _clay = Color(0xFFB9684E);
  static const Color _amethyst = Color(0xFF76558D);
  static const Color _obsidian = Color(0xFF34404A);

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
    AvatarRing(
      id: kAvatarRingSunset,
      price: 120,
      catalogVersion: 2,
      borderColor: _clay,
      borderWidth: 3,
    ),
    AvatarRing(
      id: kAvatarRingAurora,
      price: 180,
      catalogVersion: 2,
      borderColor: _amethyst,
      borderWidth: 3,
    ),
    AvatarRing(
      id: kAvatarRingObsidian,
      price: 240,
      catalogVersion: 2,
      borderColor: _obsidian,
      borderWidth: 3.5,
    ),
  ];

  static const Set<CosmeticSurface> _avatarSurfaces = {
    CosmeticSurface.settings,
    CosmeticSurface.profile,
    CosmeticSurface.lessonComplete,
    CosmeticSurface.reviewComplete,
  };

  static final List<CosmeticItem> items = [
    for (final ring in rings)
      CosmeticItem(
        id: ring.id,
        slot: CosmeticSlot.avatarRing,
        price: ring.price,
        catalogVersion: ring.catalogVersion,
        surfaces: _avatarSurfaces,
        accentColor: ring.borderColor,
        icon: Icons.account_circle_rounded,
      ),
    CosmeticItem(
      id: CosmeticItems.profileMist,
      slot: CosmeticSlot.profileTheme,
      price: 70,
      surfaces: {CosmeticSurface.settings, CosmeticSurface.profile},
      accentColor: Color(0xFF1F727E),
      secondaryColor: Color(0xFF8CCAD0),
      icon: Icons.landscape_rounded,
    ),
    CosmeticItem(
      id: CosmeticItems.profileSunrise,
      slot: CosmeticSlot.profileTheme,
      price: 130,
      surfaces: {CosmeticSurface.settings, CosmeticSurface.profile},
      accentColor: Color(0xFFB9684E),
      secondaryColor: Color(0xFFE8C78D),
      icon: Icons.wb_twilight_rounded,
    ),
    CosmeticItem(
      id: CosmeticItems.completionReedBloom,
      slot: CosmeticSlot.completionEffect,
      price: 90,
      surfaces: {
        CosmeticSurface.settings,
        CosmeticSurface.lessonComplete,
        CosmeticSurface.reviewComplete,
      },
      accessibilityVariant: CosmeticAccessibilityVariant.staticAlternative,
      accentColor: Color(0xFF78C7B8),
      icon: Icons.spa_rounded,
    ),
    CosmeticItem(
      id: CosmeticItems.completionLakeGlow,
      slot: CosmeticSlot.completionEffect,
      price: 160,
      surfaces: {
        CosmeticSurface.settings,
        CosmeticSurface.lessonComplete,
        CosmeticSurface.reviewComplete,
      },
      accessibilityVariant: CosmeticAccessibilityVariant.staticAlternative,
      accentColor: Color(0xFF76558D),
      icon: Icons.auto_awesome_rounded,
    ),
  ];

  static List<CosmeticItem> itemsForSlot(CosmeticSlot slot) =>
      items.where((item) => item.slot == slot).toList(growable: false);

  static CosmeticItem? itemById(String id) {
    for (final item in items) {
      if (item.id == id) return item;
    }
    return null;
  }

  /// Catalog registration invariant: no paid item may be sold without a
  /// visible main-flow consumer.
  static bool get hasValidSurfaceContracts => items
      .where((item) => !item.isFree)
      .every((item) => item.surfaces.any(_isPrimarySurface));

  static bool _isPrimarySurface(CosmeticSurface surface) => switch (surface) {
        CosmeticSurface.profile ||
        CosmeticSurface.lessonComplete ||
        CosmeticSurface.reviewComplete =>
          true,
        CosmeticSurface.settings => false,
      };

  static AvatarRing? ringById(String id) {
    for (final ring in rings) {
      if (ring.id == id) return ring;
    }
    return null;
  }

  static AvatarRing get defaultRing => rings.first;
}
