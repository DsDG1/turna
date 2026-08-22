// Flutter imports:
import 'package:flutter/material.dart';

// Package imports:
import 'package:provider/provider.dart';

// Project imports:
import 'package:turna/application/accessibility_provider.dart';

/// Translates [child] off the bottom edge when [hidden] is true.
///
/// Does not change layout extent — the home body padding stays put so
/// lists do not jump when the bar slides away.
class ScrollHideBar extends StatelessWidget {
  final bool hidden;
  final Widget child;

  const ScrollHideBar({
    required this.hidden,
    required this.child,
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    final a11y = context.watch<AccessibilityProvider>();
    final reduceMotion = MediaQuery.disableAnimationsOf(context) ||
        a11y.reducedMotion;

    return IgnorePointer(
      ignoring: hidden,
      child: AnimatedSlide(
        offset: hidden ? const Offset(0, 1.15) : Offset.zero,
        duration:
            reduceMotion ? Duration.zero : const Duration(milliseconds: 180),
        curve: Curves.easeOutCubic,
        child: child,
      ),
    );
  }
}
