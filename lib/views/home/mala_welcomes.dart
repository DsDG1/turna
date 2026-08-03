// Dart imports:
import 'dart:async';

// Flutter imports:
import 'package:flutter/material.dart';

// Package imports:
import 'package:provider/provider.dart';

// Project imports:
import 'package:turna/application/accessibility_provider.dart';
import 'package:turna/gen/assets.gen.dart';

class MalaWelcomes extends StatefulWidget {
  const MalaWelcomes({super.key});

  @override
  State<MalaWelcomes> createState() => _MalaWelcomesState();
}

class _MalaWelcomesState extends State<MalaWelcomes> {
  final List<String> images = [
    Assets.images.mala.malaExcited.path,
    Assets.images.mala.malaWave.path,
    Assets.images.mala.malaLusty.path
  ];
  int _currentIndex = 0;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    // Pre-decode all three images so the 3-second swap never stalls on a
    // first-frame decode (the previous code re-loaded each image on swap).
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      for (final path in images) {
        precacheImage(AssetImage(path), context);
      }
    });
    // Focus mode disables the rotating welcome animation (sensory-quiet).
    _timer = Timer.periodic(const Duration(seconds: 3), (timer) {
      if (!mounted) return;
      if (context.read<AccessibilityProvider>().focusMode) return;
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
      height: 250,
      child: RepaintBoundary(
        child: AnimatedSwitcher(
          duration: const Duration(milliseconds: 500),
          //
          child: Image.asset(
            images[_currentIndex],
            key: ValueKey<String>(images[_currentIndex]),
            height: 250,
            fit: BoxFit.contain,
            cacheHeight: (250 * MediaQuery.devicePixelRatioOf(context)).round(),
          ),
        ),
      ),
    );
  }
}
