// Dart imports:
import 'dart:ui';

// Flutter imports:
import 'package:flutter/material.dart';

// Package imports:
import 'package:provider/provider.dart';

// Project imports:
import 'package:turna/application/accessibility_provider.dart';
import 'package:turna/l10n/app_strings.dart';
import 'package:turna/views/theme.dart';

/// Floating rounded-glass tab bar (iOS 26 / M3 Expressive, restrained).
///
/// Sits above the home indicator with side insets so page content can peek
/// through. High-contrast / focus-mode skip the blur and use a solid fill.
class BottomNavigator extends StatelessWidget {
  static const double capsuleHeight = 60;
  static const double sideInset = 16;
  static const double bottomGap = 8;
  static const double topShadowPad = 8;
  static const double capsuleRadius = 28;

  /// Extra body padding so scrollables clear the floating capsule
  /// (excludes the system home-indicator inset, which [MediaQuery.padding]
  /// already carries).
  static const double overlayExtent =
      capsuleHeight + bottomGap + topShadowPad;

  final Function(int) onPress;
  final int currentIndex;

  const BottomNavigator({
    required this.currentIndex,
    required this.onPress,
    Key? key,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final bottomPadding = MediaQuery.viewPaddingOf(context).bottom;
    final a11y = context.watch<AccessibilityProvider>();
    final reduceMotion = MediaQuery.disableAnimationsOf(context) ||
        a11y.reducedMotion;
    final solidGlass = a11y.highContrast || a11y.focusMode;
    final useBlur = !solidGlass;

    final radius = BorderRadius.circular(capsuleRadius);
    final fill = solidGlass
        ? TurnaTheme.bottomNavBg(context)
        : TurnaTheme.floatingBarFill(context);

    Widget capsule = DecoratedBox(
      decoration: BoxDecoration(
        color: fill,
        borderRadius: radius,
        border: Border.all(
          color: solidGlass
              ? TurnaTheme.statCardBorder(context)
              : TurnaTheme.glassBorder(context),
          width: solidGlass ? 1.5 : 1,
        ),
      ),
      child: SizedBox(
        height: capsuleHeight,
        child: Row(
          children: [
            _NavItem(
              outlined: Icons.school_outlined,
              filled: Icons.school_rounded,
              label: AppStrings.commonNavLearn,
              isSelected: currentIndex == 0,
              reduceMotion: reduceMotion,
              onTap: () => onPress(0),
            ),
            _NavItem(
              outlined: Icons.extension_outlined,
              filled: Icons.extension_rounded,
              label: AppStrings.commonNavPlay,
              isSelected: currentIndex == 1,
              reduceMotion: reduceMotion,
              onTap: () => onPress(1),
            ),
            _NavItem(
              outlined: Icons.person_outline_rounded,
              filled: Icons.person_rounded,
              label: AppStrings.commonNavProfile,
              isSelected: currentIndex == 2,
              reduceMotion: reduceMotion,
              onTap: () => onPress(2),
            ),
            _NavItem(
              outlined: Icons.settings_outlined,
              filled: Icons.settings_rounded,
              label: AppStrings.commonNavSettings,
              isSelected: currentIndex == 3,
              reduceMotion: reduceMotion,
              onTap: () => onPress(3),
            ),
          ],
        ),
      ),
    );
    if (useBlur) {
      capsule = BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 22, sigmaY: 22),
        child: capsule,
      );
    }
    capsule = ClipRRect(borderRadius: radius, child: capsule);

    return Padding(
      padding: EdgeInsets.fromLTRB(
        sideInset,
        topShadowPad,
        sideInset,
        bottomGap + bottomPadding,
      ),
      child: DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: radius,
          boxShadow: TurnaTheme.glassShadow(context, TurnaTheme.brandTeal),
        ),
        child: RepaintBoundary(child: capsule),
      ),
    );
  }
}

class _NavItem extends StatelessWidget {
  final IconData outlined;
  final IconData filled;
  final String label;
  final bool isSelected;
  final bool reduceMotion;
  final VoidCallback onTap;

  const _NavItem({
    required this.outlined,
    required this.filled,
    required this.label,
    required this.isSelected,
    required this.reduceMotion,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final duration =
        reduceMotion ? Duration.zero : const Duration(milliseconds: 220);
    const selectedColor = TurnaTheme.brandTeal;
    final idleColor = TurnaTheme.textHintColor(context);

    return Expanded(
      child: Semantics(
        button: true,
        selected: isSelected,
        label: label,
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: onTap,
            customBorder: const StadiumBorder(),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                AnimatedContainer(
                  duration: duration,
                  curve: Curves.easeOutCubic,
                  padding:
                      const EdgeInsets.symmetric(horizontal: 14, vertical: 5),
                  decoration: BoxDecoration(
                    color: isSelected
                        ? selectedColor.withValues(alpha: 0.16)
                        : Colors.transparent,
                    borderRadius:
                        BorderRadius.circular(TurnaTheme.radiusRound),
                  ),
                  child: Icon(
                    isSelected ? filled : outlined,
                    size: 24,
                    color: isSelected ? selectedColor : idleColor,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight:
                        isSelected ? FontWeight.w700 : FontWeight.w500,
                    color: isSelected ? selectedColor : idleColor,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
