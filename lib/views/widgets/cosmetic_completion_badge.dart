import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:turna/application/accessibility_capabilities.dart';
import 'package:turna/application/cosmetic_provider.dart';
import 'package:turna/domain/cosmetics/cosmetic_item.dart';
import 'package:turna/l10n/app_strings.dart';

/// Completion-surface consumer for the equipped effect. Motion-sensitive
/// users receive the same identifiable badge with no tween.
class CosmeticCompletionBadge extends StatelessWidget {
  const CosmeticCompletionBadge({
    super.key,
    required this.fallbackIcon,
    required this.fallbackColor,
    this.size = 80,
    this.iconSize = 44,
  });

  final IconData fallbackIcon;
  final Color fallbackColor;
  final double size;
  final double iconSize;

  @override
  Widget build(BuildContext context) {
    CosmeticItem? effect;
    try {
      effect = Provider.of<CosmeticProvider>(context)
          .equippedItem(CosmeticSlot.completionEffect);
    } catch (_) {
      effect = null;
    }
    final reduceMotion = accessibilityOf(context).reduceMotion;
    final badge = _Badge(
      size: size,
      iconSize: iconSize,
      icon: effect?.icon ?? fallbackIcon,
      color: effect?.accentColor ?? fallbackColor,
      label: effect == null
          ? AppStrings.reviewCompletionTitle
          : AppStrings.cosmeticsItemTitle(effect.id),
      staticVariant: reduceMotion && effect != null,
    );
    if (effect == null || reduceMotion) return badge;
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0.82, end: 1),
      curve: Curves.easeOutBack,
      duration: const Duration(milliseconds: 520),
      builder: (_, value, child) => Transform.scale(scale: value, child: child),
      child: badge,
    );
  }
}

class _Badge extends StatelessWidget {
  const _Badge({
    required this.size,
    required this.iconSize,
    required this.icon,
    required this.color,
    required this.label,
    required this.staticVariant,
  });

  final double size;
  final double iconSize;
  final IconData icon;
  final Color color;
  final String label;
  final bool staticVariant;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: staticVariant ? '$label（静态效果）' : label,
      image: true,
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.14),
          shape: BoxShape.circle,
          border: Border.all(
            color: color,
            width: staticVariant ? 3 : 2,
          ),
          boxShadow: staticVariant
              ? const []
              : [
                  BoxShadow(
                    color: color.withValues(alpha: 0.24),
                    blurRadius: 18,
                  ),
                ],
        ),
        child: Icon(icon, size: iconSize, color: color),
      ),
    );
  }
}
