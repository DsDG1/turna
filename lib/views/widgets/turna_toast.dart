// Dart imports:
import 'dart:async';

// Flutter imports:
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

// Project imports:
import 'package:turna/views/theme.dart';

/// Lightweight pill / capsule toast component (胶囊气泡提示).
///
/// Supports two presentation modes:
/// 1. [TurnaToast.show] — Native [SnackBar] with floating pill/stadium styling.
/// 2. [TurnaToast.showBubble] — Overlay-based floating pill bubble with smooth
///    fade + scale transitions (iOS HUD / WeChat pill style).
class TurnaToast {
  TurnaToast._();

  /// Show a floating pill toast via [ScaffoldMessenger].
  static void show(
    BuildContext context,
    String message, {
    IconData? icon,
    Color? iconColor,
    Duration duration = const Duration(milliseconds: 2000),
    SnackBarAction? action,
  }) {
    HapticFeedback.lightImpact();
    final messenger = ScaffoldMessenger.maybeOf(context);
    if (messenger == null) return;

    messenger.hideCurrentSnackBar();
    messenger.showSnackBar(
      SnackBar(
        behavior: SnackBarBehavior.floating,
        shape: const StadiumBorder(),
        elevation: 6,
        duration: duration,
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 11),
        action: action,
        content: Row(
          mainAxisSize: MainAxisSize.min,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            if (icon != null) ...[
              Icon(
                icon,
                size: 18,
                color: iconColor ?? TurnaTheme.brandReed,
              ),
              const SizedBox(width: 8),
            ],
            Flexible(
              child: Text(
                message,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 13.5,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 0.2,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Convenience method for success feedback (green checkmark pill).
  static void success(
    BuildContext context,
    String message, {
    Duration duration = const Duration(milliseconds: 2000),
  }) {
    show(
      context,
      message,
      icon: Icons.check_circle_rounded,
      iconColor: const Color(0xFF4ADE80),
      duration: duration,
    );
  }

  /// Convenience method for info feedback (teal info pill).
  static void info(
    BuildContext context,
    String message, {
    Duration duration = const Duration(milliseconds: 2000),
  }) {
    show(
      context,
      message,
      icon: Icons.info_outline_rounded,
      iconColor: TurnaTheme.brandReed,
      duration: duration,
    );
  }

  /// Convenience method for warning feedback (amber warning pill).
  static void warning(
    BuildContext context,
    String message, {
    Duration duration = const Duration(milliseconds: 2500),
  }) {
    show(
      context,
      message,
      icon: Icons.warning_amber_rounded,
      iconColor: const Color(0xFFFBBF24),
      duration: duration,
    );
  }

  /// Convenience method for error feedback (red alert pill).
  static void error(
    BuildContext context,
    String message, {
    Duration duration = const Duration(milliseconds: 3000),
  }) {
    show(
      context,
      message,
      icon: Icons.error_outline_rounded,
      iconColor: const Color(0xFFF87171),
      duration: duration,
    );
  }

  /// Show a floating pill bubble via [Overlay] with pure Fade + Scale animation.
  ///
  /// This bypasses [Scaffold] and renders directly in the overlay tree with
  /// a rounded pill shape and smooth micro-interaction.
  static void showBubble(
    BuildContext context,
    String message, {
    IconData? icon,
    Color? iconColor,
    Duration duration = const Duration(milliseconds: 1800),
    double bottomOffset = 90.0,
  }) {
    HapticFeedback.lightImpact();
    final overlayState = Overlay.maybeOf(context, rootOverlay: true);
    if (overlayState == null) {
      show(context, message, icon: icon, iconColor: iconColor, duration: duration);
      return;
    }

    late OverlayEntry entry;
    entry = OverlayEntry(
      builder: (context) => _FloatingPillBubble(
        message: message,
        icon: icon,
        iconColor: iconColor,
        duration: duration,
        bottomOffset: bottomOffset,
        onDismissed: () => entry.remove(),
      ),
    );

    overlayState.insert(entry);
  }
}

class _FloatingPillBubble extends StatefulWidget {
  final String message;
  final IconData? icon;
  final Color? iconColor;
  final Duration duration;
  final double bottomOffset;
  final VoidCallback onDismissed;

  const _FloatingPillBubble({
    required this.message,
    required this.duration,
    required this.bottomOffset,
    required this.onDismissed,
    this.icon,
    this.iconColor,
  });

  @override
  State<_FloatingPillBubble> createState() => _FloatingPillBubbleState();
}

class _FloatingPillBubbleState extends State<_FloatingPillBubble>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _fadeAnimation;
  late final Animation<double> _scaleAnimation;
  Timer? _dismissTimer;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 220),
      reverseDuration: const Duration(milliseconds: 200),
    );

    _fadeAnimation = CurvedAnimation(
      parent: _controller,
      curve: Curves.easeOut,
      reverseCurve: Curves.easeIn,
    );

    _scaleAnimation = Tween<double>(begin: 0.88, end: 1.0).animate(
      CurvedAnimation(
        parent: _controller,
        curve: Curves.easeOutBack,
        reverseCurve: Curves.easeIn,
      ),
    );

    _controller.forward();

    _dismissTimer = Timer(widget.duration, () async {
      if (!mounted) return;
      await _controller.reverse();
      if (mounted) {
        widget.onDismissed();
      }
    });
  }

  @override
  void dispose() {
    _dismissTimer?.cancel();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bg = isDark ? const Color(0xEE2A3D4A) : const Color(0xEE1C2730);

    return Positioned(
      bottom: widget.bottomOffset + MediaQuery.of(context).padding.bottom,
      left: 24,
      right: 24,
      child: Center(
        child: AnimatedBuilder(
          animation: _controller,
          builder: (context, child) {
            return FadeTransition(
              opacity: _fadeAnimation,
              child: ScaleTransition(
                scale: _scaleAnimation,
                child: child,
              ),
            );
          },
          child: Material(
            color: Colors.transparent,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
              decoration: BoxDecoration(
                color: bg,
                borderRadius: BorderRadius.circular(24),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.22),
                    blurRadius: 16,
                    offset: const Offset(0, 6),
                  ),
                ],
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  if (widget.icon != null) ...[
                    Icon(
                      widget.icon,
                      size: 17,
                      color: widget.iconColor ?? TurnaTheme.brandReed,
                    ),
                    const SizedBox(width: 8),
                  ],
                  Flexible(
                    child: Text(
                      widget.message,
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 13.5,
                        fontWeight: FontWeight.w600,
                        letterSpacing: 0.2,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
