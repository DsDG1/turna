// Flutter imports:
import 'package:flutter/material.dart';

// Project imports:
import 'package:turna/domain/cosmetics/avatar_ring.dart';
import 'package:turna/views/theme.dart';

/// Circular avatar shell with a simple accent ring.
///
/// Structure (no animation): outer accent stroke → 1px [gapColor] seam → fill.
/// Mist rings stay neutral and quiet; reed/lake use catalog colors.
class AvatarWithRing extends StatelessWidget {
  const AvatarWithRing({
    super.key,
    required this.radius,
    required this.child,
    this.ring,
    this.backgroundColor,
    this.gapColor,
  });

  final double radius;
  final Widget child;
  final AvatarRing? ring;
  final Color? backgroundColor;

  /// Color of the 1px seam under the accent ring (usually card / scaffold).
  /// When null, uses [TurnaTheme.cardBg].
  final Color? gapColor;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final accent = ring?.borderColor;
    final isAccent = accent != null;

    // Mist: slightly more visible than a hairline divider.
    final ringColor = accent ??
        (isDark
            ? TurnaTheme.brandSky.withValues(alpha: 0.45)
            : TurnaTheme.textHint.withValues(alpha: 0.55));
    final ringWidth = isAccent ? (ring?.borderWidth ?? 2.5) : 1.5;
    final seam = gapColor ?? TurnaTheme.cardBg(context);
    const seamWidth = 1.5;

    final diameter = radius * 2;
    // Outer size includes ring + seam so the fill stays at [radius].
    final outer = diameter + (ringWidth + seamWidth) * 2;

    return SizedBox(
      width: outer,
      height: outer,
      child: DecoratedBox(
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          border: Border.all(color: ringColor, width: ringWidth),
        ),
        child: Padding(
          padding: EdgeInsets.all(seamWidth),
          child: DecoratedBox(
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: seam,
            ),
            child: Padding(
              // Thin inner hairline so fill doesn't glue to the seam.
              padding: const EdgeInsets.all(0.5),
              child: DecoratedBox(
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: backgroundColor ??
                      TurnaTheme.brandTeal.withValues(alpha: 0.12),
                ),
                child: ClipOval(
                  child: Center(child: child),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
