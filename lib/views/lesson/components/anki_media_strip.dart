// Dart imports:
import 'dart:io';

// Flutter imports:
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

// Project imports:
import 'package:turna/application/anki_official/official_anki_composition.dart';
import 'package:turna/application/anki_official/render/official_anki_media_resolver.dart';
import 'package:turna/application/audio_controller.dart';
import 'package:turna/application/course_pack/course_pack_media.dart';
import 'package:turna/di/injection.dart';
import 'package:turna/l10n/app_strings.dart';
import 'package:turna/core/theme.dart';
import 'package:turna/views/widgets/turna_snack_bar.dart';

/// Renders imported media (`turnapack://<code>/<file>` or bare Official Anki v2
/// media filenames) attached to an objectively-graded interaction (MCQ /
/// FillBlank): one speaker button per audio reference and one thumbnail per
/// image reference.
///
/// Audio plays through [AudioController] and images resolve to local file
/// paths up front; missing files degrade silently to nothing.
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

  /// Returns `true` for `turnapack://` refs and bare media filenames
  /// (non-empty, containing neither `'/'` nor `'://'`, e.g. `foo.jpg` /
  /// `bar.mp3` produced by Official Anki v2).
  static bool isResolvableMedia(String? ref) {
    if (ref == null) return false;
    final trimmed = ref.trim();
    if (trimmed.isEmpty) return false;
    if (CoursePackMedia.isPackAsset(trimmed)) return true;
    return _isBareMediaName(trimmed);
  }

  static bool _isBareMediaName(String asset) {
    if (asset.isEmpty || asset.contains('://') || asset.contains('/')) {
      return false;
    }
    final dot = asset.lastIndexOf('.');
    return dot > 0 && dot < asset.length - 1;
  }

  @override
  State<AnkiMediaStrip> createState() => _AnkiMediaStripState();
}

class _AnkiMediaStripState extends State<AnkiMediaStrip> {
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
    final resolve = widget.resolveMediaPath ?? _resolveDefaultMediaPath;
    final images = <String>[];
    for (final asset in widget.imageAssets) {
      if (!AnkiMediaStrip.isResolvableMedia(asset)) continue;
      final path = await _resolveSafely(resolve, asset);
      if (path != null) images.add(path);
    }
    final audios = <({String ref, bool available})>[];
    for (final asset in widget.audioAssets) {
      if (!AnkiMediaStrip.isResolvableMedia(asset)) continue;
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

  Future<String?> _resolveDefaultMediaPath(String ref) async {
    if (CoursePackMedia.isPackAsset(ref)) {
      return CoursePackMedia.resolveFile(ref);
    }
    // Bare official-collection filename (`hello.mp3`): the official Anki
    // importer projects media names, not scheme refs, so it resolves against
    // the collection's media folder instead.
    if (getIt.isRegistered<AudioController>()) {
      return getIt<AudioController>().resolveOfficialMediaPath(ref);
    }
    return officialAnkiMediaCandidateFile(
      ref,
      OfficialAnkiCompositionRoot.locatorPaths,
    )?.path;
  }

  Future<String?> _resolveSafely(
    Future<String?> Function(String) resolve,
    String ref,
  ) async {
    try {
      return await resolve(ref);
    } catch (_) {
      // Best-effort media resolution: missing or unreadable media degrades
      // silently to an unavailable button or hidden thumbnail.
      return null;
    }
  }

  Future<void> _play(String ref) async {
    final play = widget.playAudio ?? _playDefault;
    var started = false;
    try {
      started = await play(ref);
    } catch (_) {
      // Best-effort audio playback: failure surfaces via the snackbar below.
      started = false;
    }
    if (!started && mounted) {
      TurnaSnackBar.maybeShow(context, AppStrings.lessonAudioPlaybackFailed);
    }
  }

  Future<bool> _playDefault(String ref) {
    if (!getIt.isRegistered<AudioController>()) {
      return Future.value(false);
    }
    final audio = getIt<AudioController>();
    if (CoursePackMedia.isPackAsset(ref)) {
      return audio.playCoursePackMedia(ref);
    }
    return audio.playOfficialMediaFile(ref);
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
                    // 「湿地雾光」音频键语言: teal 描边圆（与 SpeakerButton
                    // 同视觉), 不再用 filledTonal 的另一套底色。
                    child: IconButton(
                      key: ValueKey('anki-audio-$index'),
                      onPressed: _audios[index].available
                          ? () => _play(_audios[index].ref)
                          : null,
                      color: TurnaTheme.brandTeal,
                      style: IconButton.styleFrom(
                        foregroundColor: TurnaTheme.brandTeal,
                        side: const BorderSide(
                          color: TurnaTheme.brandTeal,
                          width: 1.5,
                        ),
                        shape: const CircleBorder(),
                        backgroundColor: Colors.transparent,
                      ),
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
              borderRadius: BorderRadius.circular(TurnaTheme.radiusMedium),
              // Decode cap (same formula as CachedAssetImage): deck media is
              // routinely multi-megapixel; without it a 160-logical-px
              // thumbnail decodes at full resolution into memory.
              child: Image.file(
                File(path),
                height: 160,
                cacheHeight:
                    (160 * MediaQuery.devicePixelRatioOf(context)).round(),
                cacheWidth: (MediaQuery.sizeOf(context).width.clamp(0, 600) *
                        MediaQuery.devicePixelRatioOf(context))
                    .round(),
                fit: BoxFit.contain,
                errorBuilder: (_, __, ___) => const SizedBox.shrink(),
              ),
            ),
          ),
      ],
    );
  }
}
