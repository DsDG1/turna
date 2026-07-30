// Dart imports:
import 'dart:io';

// Flutter imports:
import 'package:flutter/material.dart';

// Project imports:
import 'package:varnamala/application/audio_controller.dart';
import 'package:varnamala/di/injection.dart';
import 'package:varnamala/domain/audio/anki_audio_resolver.dart';
import 'package:varnamala/views/lesson/components/interactions/interaction_renderer.dart';

/// Renders Anki deck media (`anki://<importId>/<file>` references) attached
/// to an objectively-graded interaction (MCQ / FillBlank): one speaker
/// button per audio reference and one thumbnail per image reference.
///
/// Audio plays through [AudioController.speakWord], which resolves `anki://`
/// refs to their on-disk copy. Images are resolved to local file paths up
/// front; refs whose file was never copied (or whose deck was uninstalled)
/// degrade silently to nothing.
class AnkiMediaStrip extends StatefulWidget {
  final List<String> audioAssets;
  final List<String> imageAssets;

  const AnkiMediaStrip({
    super.key,
    this.audioAssets = const [],
    this.imageAssets = const [],
  });

  @override
  State<AnkiMediaStrip> createState() => _AnkiMediaStripState();
}

class _AnkiMediaStripState extends State<AnkiMediaStrip> {
  final AnkiAudioResolver _mediaResolver = AnkiAudioResolver();
  List<String> _imagePaths = const [];

  @override
  void initState() {
    super.initState();
    _resolveImages();
  }

  Future<void> _resolveImages() async {
    final paths = <String>[];
    for (final asset in widget.imageAssets) {
      if (!AnkiAudioResolver.isAnkiAsset(asset)) continue;
      final path = await _mediaResolver.resolveMediaPath(asset);
      if (path != null) paths.add(path);
    }
    if (!mounted) return;
    setState(() => _imagePaths = paths);
  }

  @override
  Widget build(BuildContext context) {
    final audios = widget.audioAssets.where(AnkiAudioResolver.isAnkiAsset);
    if (audios.isEmpty && _imagePaths.isEmpty) return const SizedBox.shrink();

    return Column(
      children: [
        for (final ref in audios)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: SpeakerButton(
              onPressed: () => getIt<AudioController>().speakWord(ref),
            ),
          ),
        for (final path in _imagePaths)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: Image.file(
                File(path),
                height: 160,
                fit: BoxFit.contain,
                errorBuilder: (_, __, ___) => const SizedBox.shrink(),
              ),
            ),
          ),
      ],
    );
  }
}
