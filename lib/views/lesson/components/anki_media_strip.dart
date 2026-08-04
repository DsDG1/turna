// Dart imports:
import 'dart:io';

// Flutter imports:
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

// Project imports:
import 'package:turna/application/audio_controller.dart';
import 'package:turna/di/injection.dart';
import 'package:turna/domain/audio/anki_audio_resolver.dart';
import 'package:turna/l10n/app_strings.dart';
import 'package:turna/views/theme.dart';

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
  final Future<String?> Function(String ref)? resolveMediaPath;
  final Future<bool> Function(String ref)? playAudio;

  const AnkiMediaStrip({
    super.key,
    this.audioAssets = const [],
    this.imageAssets = const [],
    this.resolveMediaPath,
    this.playAudio,
  });

  @override
  State<AnkiMediaStrip> createState() => _AnkiMediaStripState();
}

class _AnkiMediaStripState extends State<AnkiMediaStrip> {
  final AnkiAudioResolver _mediaResolver = AnkiAudioResolver();
  List<String> _imagePaths = const [];
  List<({String ref, bool available})> _audios = const [];
  int _resolveGeneration = 0;

  @override
  void initState() {
    super.initState();
    _resolveMedia();
  }

  @override
  void didUpdateWidget(covariant AnkiMediaStrip oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!listEquals(oldWidget.audioAssets, widget.audioAssets) ||
        !listEquals(oldWidget.imageAssets, widget.imageAssets)) {
      _resolveMedia();
    }
  }

  Future<void> _resolveMedia() async {
    final generation = ++_resolveGeneration;
    final resolve = widget.resolveMediaPath ?? _mediaResolver.resolveMediaPath;
    final images = <String>[];
    for (final asset in widget.imageAssets) {
      if (!AnkiAudioResolver.isAnkiAsset(asset)) continue;
      final path = await _resolveSafely(resolve, asset);
      if (path != null) images.add(path);
    }
    final audios = <({String ref, bool available})>[];
    for (final asset in widget.audioAssets) {
      if (!AnkiAudioResolver.isAnkiAsset(asset)) continue;
      audios.add(
        (ref: asset, available: await _resolveSafely(resolve, asset) != null),
      );
    }
    if (!mounted || generation != _resolveGeneration) return;
    setState(() {
      _imagePaths = images;
      _audios = audios;
    });
  }

  Future<String?> _resolveSafely(
    Future<String?> Function(String) resolve,
    String ref,
  ) async {
    try {
      return await resolve(ref);
    } catch (_) {
      return null;
    }
  }

  Future<void> _play(String ref) async {
    final play = widget.playAudio ?? getIt<AudioController>().playAnkiMedia;
    var started = false;
    try {
      started = await play(ref);
    } catch (_) {
      started = false;
    }
    if (!started && mounted) {
      ScaffoldMessenger.maybeOf(context)?.showSnackBar(
        SnackBar(content: Text(AppStrings.lessonAudioPlaybackFailed)),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_audios.isEmpty && _imagePaths.isEmpty) return const SizedBox.shrink();

    return Column(
      children: [
        if (_audios.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Wrap(
              spacing: 8,
              runSpacing: 8,
              alignment: WrapAlignment.center,
              children: [
                for (var index = 0; index < _audios.length; index++)
                  Tooltip(
                    message: _audios[index].available
                        ? '${AppStrings.lessonPlayAudioLabel} ${index + 1}'
                        : AppStrings.lessonAudioMissing,
                    child: IconButton.filledTonal(
                      key: ValueKey('anki-audio-$index'),
                      onPressed: _audios[index].available
                          ? () => _play(_audios[index].ref)
                          : null,
                      color: TurnaTheme.brandTeal,
                      icon: const Icon(Icons.volume_up_rounded),
                    ),
                  ),
              ],
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
