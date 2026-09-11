import 'package:flutter/material.dart';

/// One equipped item per slot. Streak vouchers are consumables and therefore
/// deliberately do not appear here.
enum CosmeticSlot {
  avatarRing,
  profileTheme,
  cardBack,
  completionEffect,
  soundPack,
  mascotAccessory,
}

/// Surfaces on which a catalog item is actually rendered.
enum CosmeticSurface {
  settings,
  profile,
  lessonComplete,
  reviewComplete,
}

enum CosmeticAccessibilityVariant { standard, staticAlternative }

@immutable
class CosmeticItem {
  const CosmeticItem({
    required this.id,
    required this.slot,
    required this.price,
    required this.surfaces,
    this.catalogVersion = 2,
    this.accessibilityVariant = CosmeticAccessibilityVariant.standard,
    this.accentColor,
    this.secondaryColor,
    this.icon = Icons.auto_awesome_rounded,
  });

  final String id;
  final CosmeticSlot slot;
  final int catalogVersion;
  final int price;
  final Set<CosmeticSurface> surfaces;
  final CosmeticAccessibilityVariant accessibilityVariant;

  /// Code-native placeholder styling. Bitmap artwork can replace this later
  /// without changing entitlement or surface contracts.
  final Color? accentColor;
  final Color? secondaryColor;
  final IconData icon;

  bool get isFree => price <= 0;
}

abstract final class CosmeticItems {
  static const profileMist = 'theme_profile_mist';
  static const profileSunrise = 'theme_profile_sunrise';
  static const completionReedBloom = 'effect_reed_bloom';
  static const completionLakeGlow = 'effect_lake_glow';
}
