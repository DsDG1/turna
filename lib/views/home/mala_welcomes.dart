// Dart imports:
import 'dart:async';

// Flutter imports:
import 'package:flutter/material.dart';

// Project imports:
import 'package:varnamala/gen/assets.gen.dart';

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
    _timer = Timer.periodic(const Duration(seconds: 3), (timer) {
      if (!mounted) return;
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
