// Dart imports:
import 'dart:io';

// Flutter imports:
import 'package:flutter/material.dart';

// Project imports:
import 'package:turna/application/course_pack/course_pack_media.dart';
import 'package:turna/views/theme.dart';

/// A memory-bounded image for interaction prompts.
///
/// Bundled assets use [Image.asset]. Imported `.turnapack` media
/// (`turnapack://<code>/file`) resolves to an on-disk file.
///
/// Decodes the image capped to the display width (clamped to 600 logical px)
/// so a multi-megapixel image is never decoded for a column-width slot.
class CachedAssetImage extends StatelessWidget {
  final String asset;
  final double maxHeight;

  const CachedAssetImage({
    super.key,
    required this.asset,
    this.maxHeight = 300,
  });

  @override
  Widget build(BuildContext context) {
    final dpr = MediaQuery.devicePixelRatioOf(context);
    final cacheWidth =
        (MediaQuery.sizeOf(context).width.clamp(0, 600) * dpr).round();
    final cacheHeight = (maxHeight * dpr).round();
    if (CoursePackMedia.isPackAsset(asset)) {
      return FutureBuilder<String?>(
        future: CoursePackMedia.resolveFile(asset),
        builder: (context, snapshot) {
          final path = snapshot.data;
          if (path == null) return const SizedBox.shrink();
          return Image.file(
            File(path),
            fit: BoxFit.cover,
            cacheWidth: cacheWidth,
            cacheHeight: cacheHeight,
            errorBuilder: (_, __, ___) => const SizedBox.shrink(),
          );
        },
      );
    }
    return Image.asset(
      asset,
      fit: BoxFit.cover,
      cacheWidth: cacheWidth,
      cacheHeight: cacheHeight,
    );
  }
}

/// Convenience wrapper that clips the [CachedAssetImage] to the theme's medium
/// radius — the shared visual treatment used by the prompt image renderers.
class RoundedCachedAssetImage extends StatelessWidget {
  final String asset;
  final double maxHeight;

  const RoundedCachedAssetImage({
    super.key,
    required this.asset,
    this.maxHeight = 300,
  });

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(TurnaTheme.radiusMedium),
      child: CachedAssetImage(asset: asset, maxHeight: maxHeight),
    );
  }
}
