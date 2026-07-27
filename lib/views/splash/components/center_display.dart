import 'package:flutter/material.dart';

// Project imports:
import 'package:varnamala/l10n/app_localizations.dart';
import 'package:varnamala/views/app_fonts.dart';
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
    final l10n = AppLocalizations.of(context)!;
    _texts = [
      _TextItem(
        l10n.splashReclaiming,
        FontWeight.w600,
        (context) => VarnamalaTheme.textSecondaryColor(context),
        const Duration(milliseconds: 1000),
      ),
      _TextItem(
        l10n.splashLearnTurkish,
        FontWeight.w600,
        (context) => VarnamalaTheme.textSecondaryColor(context),
        const Duration(milliseconds: 1000),
      ),
      _TextItem(
        l10n.splashFreeForever,
        FontWeight.w700,
        (_) => VarnamalaTheme.error,
        const Duration(milliseconds: 2500),
      ),
    ];
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
          const RepaintBoundary(child: MalaWelcomes()),
          const SizedBox(height: 24),
          Text(
            AppLocalizations.of(context)!.splashAppName,
            style: AppFonts.nunito(
              fontSize: 36,
              fontWeight: FontWeight.w800,
              color: VarnamalaTheme.peacockTeal,
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
              AppLocalizations.of(context)!.splashSubtitle,
              textAlign: TextAlign.center,
              style: AppFonts.nunito(
                fontSize: 16,
                color: VarnamalaTheme.textHintColor(context),
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
