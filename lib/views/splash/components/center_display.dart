// Dart imports:
import 'dart:async';

import 'package:flutter/material.dart';

// Project imports:
import 'package:turna/l10n/app_strings.dart';
import 'package:turna/views/app_fonts.dart';
import 'package:turna/views/home/turna_welcomes.dart';
import 'package:turna/views/theme.dart';

class CenterDisplay extends StatefulWidget {
  const CenterDisplay({Key? key}) : super(key: key);

  @override
  State<CenterDisplay> createState() => _CenterDisplayState();
}

class _CenterDisplayState extends State<CenterDisplay>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  int _currentIndex = 0;

  late final List<_TextItem> _texts;
  bool _textsInitialized = false;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 500),
    );
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_textsInitialized) return;
    _textsInitialized = true;
    final l10n = AppStrings;
    _texts = [
      _TextItem(
        AppStrings.splashReclaiming,
        FontWeight.w600,
        (context) => TurnaTheme.textSecondaryColor(context),
        const Duration(milliseconds: 1000),
      ),
      _TextItem(
        AppStrings.splashLearnTurkish,
        FontWeight.w600,
        (context) => TurnaTheme.textSecondaryColor(context),
        const Duration(milliseconds: 1000),
      ),
      _TextItem(
        AppStrings.splashFreeForever,
        FontWeight.w700,
        (_) => TurnaTheme.error,
        const Duration(milliseconds: 2500),
      ),
    ];
    _startCycle();
  }

  Timer? _cycleTimer;

  /// One wait step of the text cycle. The timer handle is kept so dispose
  /// can cancel an in-flight wait (widget tests otherwise end with a
  /// pending fake-async timer).
  Future<void> _wait(Duration duration) {
    final completer = Completer<void>();
    _cycleTimer = Timer(duration, completer.complete);
    return completer.future;
  }

  void _startCycle() async {
    while (mounted) {
      await _controller.forward();
      await _wait(_texts[_currentIndex].duration);
      if (!mounted) return;
      await _controller.reverse();
      if (!mounted) return;
      setState(() {
        _currentIndex = (_currentIndex + 1) % _texts.length;
      });
    }
  }

  @override
  void dispose() {
    _cycleTimer?.cancel();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final item = _texts[_currentIndex];
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const RepaintBoundary(child: TurnaWelcomes()),
          const SizedBox(height: 24),
          Text(
            AppStrings.splashAppName,
            style: AppFonts.nunito(
              fontSize: 36,
              fontWeight: FontWeight.w800,
              color: TurnaTheme.brandTeal,
              letterSpacing: 0.5,
            ),
          ),
          const SizedBox(height: 12),
          SizedBox(
            height: 40,
            child: RepaintBoundary(
              child: FadeTransition(
                opacity: _controller,
                child: Text(
                  item.text,
                  style: AppFonts.nunito(
                    fontSize: 18,
                    fontWeight: item.weight,
                    color: item.color(context),
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(height: 32),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 40.0),
            child: Text(
              AppStrings.splashSubtitle,
              textAlign: TextAlign.center,
              style: AppFonts.nunito(
                fontSize: 16,
                color: TurnaTheme.textHintColor(context),
                height: 1.5,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _TextItem {
  final String text;
  final FontWeight weight;
  final Color Function(BuildContext) color;
  final Duration duration;

  _TextItem(this.text, this.weight, this.color, this.duration);
}
