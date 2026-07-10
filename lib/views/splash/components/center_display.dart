import 'package:flutter/material.dart';

// Package imports:
import 'package:google_fonts/google_fonts.dart';

// Project imports:
import 'package:varnamala/views/home/mala_welcomes.dart';
import 'package:varnamala/views/theme.dart';

class CenterDisplay extends StatefulWidget {
  const CenterDisplay({Key? key}) : super(key: key);

  @override
  State<CenterDisplay> createState() => _CenterDisplayState();
}

class _CenterDisplayState extends State<CenterDisplay>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  int _currentIndex = 0;

  final List<_TextItem> _texts = [
    _TextItem(
      'Reclaiming Language Learning',
      FontWeight.w600,
      VarnamalaTheme.textSecondary,
      const Duration(milliseconds: 1000),
    ),
    _TextItem(
      'Learn Swahili \u2022 Jifunze',
      FontWeight.w600,
      VarnamalaTheme.textSecondary,
      const Duration(milliseconds: 1000),
    ),
    _TextItem(
      'Free. Forever.',
      FontWeight.w700,
      VarnamalaTheme.error,
      const Duration(milliseconds: 2500),
    ),
  ];

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 500),
    );
    _startCycle();
  }

  void _startCycle() async {
    while (mounted) {
      await _controller.forward();
      await Future.delayed(_texts[_currentIndex].duration);
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
          const MalaWelcomes(),
          const SizedBox(height: 24),
          Text(
            'Varnamala',
            style: GoogleFonts.nunito(
              fontSize: 36,
              fontWeight: FontWeight.w800,
              color: VarnamalaTheme.peacockTeal,
              letterSpacing: 0.5,
            ),
          ),
          const SizedBox(height: 12),
          SizedBox(
            height: 40,
            child: FadeTransition(
              opacity: _controller,
              child: Text(
                item.text,
                style: GoogleFonts.nunito(
                  fontSize: 18,
                  fontWeight: item.weight,
                  color: item.color,
                ),
              ),
            ),
          ),
          const SizedBox(height: 32),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 40.0),
            child: Text(
              "No hearts to lose. No energy to refill.\nJust pure learning.",
              textAlign: TextAlign.center,
              style: GoogleFonts.nunito(
                fontSize: 16,
                color: VarnamalaTheme.textHint,
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
  final Color color;
  final Duration duration;

  _TextItem(this.text, this.weight, this.color, this.duration);
}
