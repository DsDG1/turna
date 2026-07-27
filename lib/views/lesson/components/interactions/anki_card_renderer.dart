// Flutter imports:
import 'dart:io';

import 'package:flutter/material.dart';

// Package imports:
import 'package:audioplayers/audioplayers.dart';
import 'package:injectable/injectable.dart';

// Project imports:
import 'package:varnamala/domain/audio/anki_audio_resolver.dart';
import 'package:varnamala/domain/course/interaction.dart';
import 'package:varnamala/l10n/app_localizations.dart';
import 'package:varnamala/views/lesson/components/interactions/interaction_renderer.dart';
import 'package:varnamala/views/theme.dart';

/// Anki-style flip card renderer. Shows the front, user taps "Show Answer",
/// then grades with Again/Hard/Good/Easy buttons (SM-2 quality 1/3/4/5).
///
/// Correctness mapping for the LessonViewModel:
/// - Again (quality 1) → correct = false
/// - Hard (quality 3) → correct = true
/// - Good (quality 4) → correct = true
/// - Easy (quality 5) → correct = true
@injectable
class AnkiCardRenderer extends InteractionRenderer {
  @override
  Type get handlesType => AnkiCard;

  @override
  Widget build(
    Interaction interaction,
    InteractionState state,
    OnInteractionSubmit onSubmit,
  ) {
    final i = interaction as AnkiCard;
    return _AnkiCardBody(
      front: i.front,
      back: i.back,
      hint: i.hint,
      imageAssets: i.imageAssets,
      audioAssets: i.audioAssets,
      state: state,
      onSubmit: onSubmit,
    );
  }
}

class _AnkiCardBody extends StatefulWidget {
  final String front;
  final String back;
  final String? hint;
  final List<String> imageAssets;
  final List<String> audioAssets;
  final InteractionState state;
  final OnInteractionSubmit onSubmit;

  const _AnkiCardBody({
    required this.front,
    required this.back,
    this.hint,
    required this.imageAssets,
    required this.audioAssets,
    required this.state,
    required this.onSubmit,
  });

  @override
  State<_AnkiCardBody> createState() => _AnkiCardBodyState();
}

class _AnkiCardBodyState extends State<_AnkiCardBody>
    with SingleTickerProviderStateMixin {
  bool _revealed = false;
  late AnimationController _flipController;
  late Animation<double> _flipAnimation;

  final AnkiAudioResolver _mediaResolver = AnkiAudioResolver();
  AudioPlayer? _mediaPlayer;

  /// Local file paths of media that actually exists on disk. `anki://`
  /// references whose file was never copied (or failed) degrade silently to
  /// text-only rendering.
  List<String> _imagePaths = const [];
  List<String> _audioPaths = const [];

  @override
  void initState() {
    super.initState();
    _flipController = AnimationController(
      duration: const Duration(milliseconds: 300),
      vsync: this,
    );
    _flipAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(parent: _flipController, curve: Curves.easeInOut),
    );
    _resolveMedia();
  }

  Future<void> _resolveMedia() async {
    Future<List<String>> resolveAll(List<String> assets) async {
      final paths = <String>[];
      for (final asset in assets) {
        final path = await _mediaResolver.resolveMediaPath(asset);
        if (path != null) paths.add(path);
      }
      return paths;
    }

    final images = await resolveAll(widget.imageAssets);
    final audios = await resolveAll(widget.audioAssets);
    if (!mounted) return;
    setState(() {
      _imagePaths = images;
      _audioPaths = audios;
    });
  }

  Future<void> _playMedia(String path) async {
    final player = _mediaPlayer ??= AudioPlayer();
    await player.stop();
    await player.play(DeviceFileSource(path));
  }

  @override
  void dispose() {
    _mediaPlayer?.dispose();
    _flipController.dispose();
    super.dispose();
  }

  void _reveal() {
    setState(() => _revealed = true);
    _flipController.forward();
  }

  void _grade(int quality) {
    // quality >= 3 is considered correct (Hard/Good/Easy)
    final correct = quality >= 3;
    widget.onSubmit(correct, userAnswerText: _gradeLabel(quality));
  }

  String _gradeLabel(int quality) {
    return switch (quality) {
      1 => 'Again',
      3 => 'Hard',
      4 => 'Good',
      5 => 'Easy',
      _ => 'Good',
    };
  }

  @override
  Widget build(BuildContext context) {
    return InteractionBody(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SectionCaption(AppLocalizations.of(context)!.lessonFlipCardCaption),
          // Front / Back card area
          AnimatedBuilder(
            animation: _flipAnimation,
            builder: (context, child) {
              final angle = _flipAnimation.value * 3.14159;
              final showFront = angle < 1.5708; // pi/2
              return Transform(
                alignment: Alignment.center,
                transform: Matrix4.identity()
                  ..setEntry(3, 2, 0.001)
                  ..rotateY(angle),
                child: showFront
                    ? _buildFront(context)
                    : Transform(
                        alignment: Alignment.center,
                        transform: Matrix4.identity()..rotateY(3.14159),
                        child: _buildBack(context),
                      ),
              );
            },
          ),
          const SizedBox(height: 24),
          // Hint (shown before reveal)
          if (!_revealed && widget.hint != null && widget.hint!.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(bottom: 16),
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  color: VarnamalaTheme.warning.withValues(alpha: 0.1),
                  borderRadius:
                      BorderRadius.circular(VarnamalaTheme.radiusSmall),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.lightbulb_outline,
                        size: 16, color: VarnamalaTheme.warning),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        widget.hint!,
                        style: TextStyle(
                          fontSize: 13,
                          color: VarnamalaTheme.textSecondaryColor(context),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          // Action buttons
          if (!widget.state.submitted) ...[
            if (!_revealed)
              LessonCheckButton(
                label: AppLocalizations.of(context)!.lessonShowAnswer,
                enabled: true,
                onPressed: _reveal,
              )
            else
              _buildGradeButtons(context),
          ],
        ],
      ),
    );
  }

  Widget _buildFront(BuildContext context) {
    return Container(
      constraints: const BoxConstraints(minHeight: 200),
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: VarnamalaTheme.cardBg(context),
        borderRadius: BorderRadius.circular(VarnamalaTheme.radiusLarge),
        border: Border.all(
          color: VarnamalaTheme.peacockTeal.withValues(alpha: 0.3),
          width: 2,
        ),
        boxShadow: [
          BoxShadow(
            color: VarnamalaTheme.peacockTeal.withValues(alpha: 0.08),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.style_rounded,
            size: 32,
            color: VarnamalaTheme.peacockTeal.withValues(alpha: 0.5),
          ),
          const SizedBox(height: 16),
          Text(
            widget.front,
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.w700,
                  color: VarnamalaTheme.textPrimaryColor(context),
                ),
          ),
          _buildMedia(context),
          const SizedBox(height: 12),
          Text(
            AppLocalizations.of(context)!.lessonTapToReveal,
            style: const TextStyle(
              fontSize: 13,
              color: VarnamalaTheme.textHint,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBack(BuildContext context) {
    return Container(
      constraints: const BoxConstraints(minHeight: 200),
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: VarnamalaTheme.peacockTeal.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(VarnamalaTheme.radiusLarge),
        border: Border.all(
          color: VarnamalaTheme.peacockTeal.withValues(alpha: 0.5),
          width: 2,
        ),
        boxShadow: [
          BoxShadow(
            color: VarnamalaTheme.peacockTeal.withValues(alpha: 0.12),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.check_circle_outline,
            size: 28,
            color: VarnamalaTheme.peacockTeal.withValues(alpha: 0.6),
          ),
          const SizedBox(height: 16),
          Text(
            widget.back,
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.w700,
                  color: VarnamalaTheme.textPrimaryColor(context),
                ),
          ),
          _buildMedia(context),
        ],
      ),
    );
  }

  /// Resolved media (images + audio play buttons) shared by both card faces.
  /// Empty when the card has no media or the files are missing on disk.
  Widget _buildMedia(BuildContext context) {
    if (_imagePaths.isEmpty && _audioPaths.isEmpty) {
      return const SizedBox.shrink();
    }
    return Padding(
      padding: const EdgeInsets.only(top: 16),
      child: Column(
        children: [
          for (final path in _imagePaths)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxHeight: 160),
                child: Image.file(
                  File(path),
                  fit: BoxFit.contain,
                  errorBuilder: (_, __, ___) => const SizedBox.shrink(),
                ),
              ),
            ),
          if (_audioPaths.isNotEmpty)
            Wrap(
              spacing: 8,
              children: [
                for (var i = 0; i < _audioPaths.length; i++)
                  IconButton(
                    icon: const Icon(Icons.volume_up_rounded),
                    color: VarnamalaTheme.peacockTeal,
                    tooltip: 'Play audio ${i + 1}',
                    onPressed: () => _playMedia(_audioPaths[i]),
                  ),
              ],
            ),
        ],
      ),
    );
  }

  Widget _buildGradeButtons(BuildContext context) {
    return Column(
      children: [
        Text(
          AppLocalizations.of(context)!.lessonHowWellDidYouKnow,
          style: TextStyle(
            fontSize: 14,
            color: VarnamalaTheme.textSecondaryColor(context),
          ),
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: _GradeButton(
                label: AppLocalizations.of(context)!.lessonAgain,
                color: VarnamalaTheme.error,
                onPressed: () => _grade(1),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: _GradeButton(
                label: AppLocalizations.of(context)!.lessonHard,
                color: VarnamalaTheme.warning,
                onPressed: () => _grade(3),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: _GradeButton(
                label: AppLocalizations.of(context)!.lessonGood,
                color: VarnamalaTheme.success,
                onPressed: () => _grade(4),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: _GradeButton(
                label: AppLocalizations.of(context)!.lessonEasy,
                color: VarnamalaTheme.peacockTeal,
                onPressed: () => _grade(5),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _GradeButton extends StatelessWidget {
  final String label;
  final Color color;
  final VoidCallback onPressed;

  const _GradeButton({
    required this.label,
    required this.color,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 48,
      child: ElevatedButton(
        onPressed: onPressed,
        style: ElevatedButton.styleFrom(
          backgroundColor: color.withValues(alpha: 0.12),
          foregroundColor: color,
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
            side: BorderSide(color: color.withValues(alpha: 0.4)),
          ),
        ),
        child: Text(
          label,
          style: const TextStyle(
            fontWeight: FontWeight.w700,
            fontSize: 13,
          ),
        ),
      ),
    );
  }
}
