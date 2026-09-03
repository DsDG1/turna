// Dart imports:
import 'dart:async';

// Flutter imports:
import 'package:flutter/material.dart';

// Package imports:
import 'package:provider/provider.dart';

// Project imports:
import 'package:turna/application/accessibility_provider.dart';
import 'package:turna/gen/assets.gen.dart';

/// Rotating Turna mascot display on splash and home views.
class TurnaWelcomes extends StatefulWidget {
  const TurnaWelcomes({this.height = 250, super.key});

  /// Rendered height in logical pixels. The asset is rasterized at
  /// device-pixel resolution for this height, so smaller hero usages stay
  /// crisp without oversampling the 250px splash size.
  final double height;

  @override
  State<TurnaWelcomes> createState() => _TurnaWelcomesState();
}

class _TurnaWelcomesState extends State<TurnaWelcomes> {
  final List<String> images = [
    Assets.images.turna.turnaWaving.path,
    Assets.images.turna.turnaReading.path,
    Assets.images.turna.turnaCelebrate.path,
  ];
  int _currentIndex = 0;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      for (final path in images) {
        precacheImage(AssetImage(path), context);
      }
    });
    // Focus mode disables rotating animation for sensory-quiet preference.
    _timer = Timer.periodic(const Duration(seconds: 3), (timer) {
      if (!mounted) return;
      final a11y = context.read<AccessibilityProvider>();
      if (a11y.focusMode || a11y.reducedMotion) return;
      setState(() {
        _currentIndex = (_currentIndex + 1) % images.length;
      });
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: widget.height,
      child: RepaintBoundary(
        child: AnimatedSwitcher(
          duration: const Duration(milliseconds: 500),
          child: Image.asset(
            images[_currentIndex],
            key: ValueKey<String>(images[_currentIndex]),
            height: widget.height,
            fit: BoxFit.contain,
            cacheHeight:
                (widget.height * MediaQuery.devicePixelRatioOf(context)).round(),
          ),
        ),
      ),
    );
  }
}
