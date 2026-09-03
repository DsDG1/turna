// Flutter imports:
import 'dart:math' as math;
import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';

// Package imports:
import 'package:provider/provider.dart';

// Project imports:
import 'package:turna/application/accessibility_provider.dart';
import 'package:turna/l10n/app_strings.dart';
import 'package:turna/views/home/motion/turna_motion.dart';
import 'package:turna/views/theme.dart';

/// Floating rounded frosted-glass tab bar.
///
/// Sits above the home indicator with side insets so page content can peek
/// through. The default path blurs the backdrop through a [BackdropFilter]
/// clipped to the capsule, with a translucent fill on top; the blurred strip
/// is small (~64px tall) and isolated by a [RepaintBoundary], keeping the
/// per-frame backdrop sampling acceptable. High-contrast / focus-mode keep
/// the solid fill and skip the blur.
class BottomNavigator extends StatelessWidget {
  static const double capsuleHeight = 64;
  static const double sideInset = 16;
  static const double bottomGap = 8;
  static const double topShadowPad = 8;
  static const double capsuleRadius = 28;

  /// Backdrop blur strength for the frosted capsule (modest sigma keeps the
  /// filter cheap; stronger values add little at this strip height).
  static const double frostSigma = 16;

  /// Extra body padding so scrollables clear the floating capsule
  /// (excludes the system home-indicator inset, which [MediaQuery.padding]
  /// already carries).
  static const double overlayExtent = capsuleHeight + bottomGap + topShadowPad;

  final Function(int) onPress;
  final int currentIndex;

  const BottomNavigator({
    required this.currentIndex,
    required this.onPress,
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    final bottomPadding = MediaQuery.viewPaddingOf(context).bottom;
    final a11y = context.watch<AccessibilityProvider>();
    final reduceMotion =
        MediaQuery.disableAnimationsOf(context) || a11y.reducedMotion;
    final solidGlass = a11y.highContrast || a11y.focusMode;

    final radius = BorderRadius.circular(capsuleRadius);
    final fill = solidGlass
        ? TurnaTheme.bottomNavBg(context)
        : TurnaTheme.floatingBarFill(context);

    final items = LayoutBuilder(
      builder: (context, constraints) {
        const itemCount = 4;
        final itemWidth = constraints.maxWidth / itemCount;
        final lensInset = itemWidth < 72 ? 5.0 : 8.0;

        return Stack(
          children: [
            AnimatedPositioned(
              duration: TurnaMotion.scaled(TurnaMotion.smooth, reduceMotion),
              curve: TurnaMotion.lensGlide,
              left: currentIndex * itemWidth + lensInset,
              top: 6,
              bottom: 6,
              width: itemWidth - lensInset * 2,
              child: _LensSlide(
                index: currentIndex,
                reduceMotion: reduceMotion,
                child: _SelectionLens(solid: solidGlass),
              ),
            ),
            Positioned.fill(
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
          ],
        );
      },
    );

    final surface = DecoratedBox(
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
        child: solidGlass
            ? items
            : Stack(
                children: [
                  Positioned.fill(
                    child: IgnorePointer(
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          borderRadius: radius,
                          gradient: LinearGradient(
                            begin: Alignment.topCenter,
                            end: Alignment.bottomCenter,
                            colors: [
                              Colors.white.withValues(
                                alpha: Theme.of(context).brightness ==
                                        Brightness.dark
                                    ? 0.08
                                    : 0.20,
                              ),
                              Colors.white.withValues(alpha: 0),
                            ],
                            stops: const [0.0, 0.52],
                          ),
                        ),
                      ),
                    ),
                  ),
                  Positioned.fill(child: items),
                ],
              ),
      ),
    );

    final capsule = ClipRRect(
      borderRadius: radius,
      child: solidGlass
          ? surface
          : BackdropFilter(
              filter: ImageFilter.blur(
                sigmaX: frostSigma,
                sigmaY: frostSigma,
              ),
              child: surface,
            ),
    );

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
          boxShadow: TurnaTheme.floatingBarShadow(context),
        ),
        child: RepaintBoundary(child: capsule),
      ),
    );
  }
}

/// Squash-stretch for the gliding selection lens: stretches along the travel
/// axis mid-flight and settles at rest. Same duration as the position slide,
/// driven as an arc (scale 1 → peak → 1) so it starts and ends at rest.
class _LensSlide extends StatefulWidget {
  final int index;
  final bool reduceMotion;
  final Widget child;

  const _LensSlide({
    required this.index,
    required this.reduceMotion,
    required this.child,
  });

  @override
  State<_LensSlide> createState() => _LensSlideState();
}

class _LensSlideState extends State<_LensSlide>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: TurnaMotion.smooth,
  );

  @override
  void didUpdateWidget(covariant _LensSlide oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.index != oldWidget.index && !widget.reduceMotion) {
      _controller.forward(from: 0);
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        final arc = math.sin(math.pi * _controller.value);
        return Transform.scale(
          scaleX: 1 + 0.10 * arc,
          scaleY: 1 - 0.06 * arc,
          child: child,
        );
      },
      child: widget.child,
    );
  }
}

class _SelectionLens extends StatelessWidget {
  final bool solid;

  const _SelectionLens({required this.solid});

  @override
  Widget build(BuildContext context) {
    const selectedColor = TurnaTheme.brandTeal;
    final radius = BorderRadius.circular(22);

    return DecoratedBox(
      decoration: BoxDecoration(
        color: solid ? selectedColor.withValues(alpha: 0.18) : null,
        borderRadius: radius,
        border: Border.all(
          color: solid
              ? selectedColor.withValues(alpha: 0.28)
              : Colors.white.withValues(
                  alpha: Theme.of(context).brightness == Brightness.dark
                      ? 0.14
                      : 0.34,
                ),
        ),
        gradient: solid
            ? null
            : LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [
                  Colors.white.withValues(
                    alpha: Theme.of(context).brightness == Brightness.dark
                        ? 0.08
                        : 0.22,
                  ),
                  selectedColor.withValues(alpha: 0.10),
                ],
              ),
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
    final duration = TurnaMotion.scaled(TurnaMotion.fast, reduceMotion);
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
                Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 5,
                  ),
                  child: AnimatedSwitcher(
                    duration: duration,
                    switchInCurve: Curves.easeOutCubic,
                    switchOutCurve: Curves.easeInCubic,
                    transitionBuilder: (child, animation) {
                      // The incoming child matches the new state; it springs
                      // in while outgoing icons shrink away.
                      final incoming =
                          (child.key as ValueKey<bool>).value == isSelected;
                      return FadeTransition(
                        opacity: animation,
                        child: ScaleTransition(
                          scale: incoming
                              ? Tween<double>(begin: 0.78, end: 1.0).animate(
                                  CurvedAnimation(
                                    parent: animation,
                                    curve: TurnaMotion.springIn,
                                  ),
                                )
                              : Tween<double>(begin: 1.0, end: 0.82)
                                  .animate(animation),
                          child: child,
                        ),
                      );
                    },
                    child: Icon(
                      isSelected ? filled : outlined,
                      key: ValueKey(isSelected),
                      size: 24,
                      color: isSelected ? selectedColor : idleColor,
                    ),
                  ),
                ),
                const SizedBox(height: 2),
                AnimatedDefaultTextStyle(
                  duration: duration,
                  curve: TurnaMotion.easeOut,
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: isSelected ? FontWeight.w600 : FontWeight.w500,
                    color: isSelected ? selectedColor : idleColor,
                  ),
                  child: Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
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
