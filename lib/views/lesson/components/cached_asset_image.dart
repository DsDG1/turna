// Flutter imports:
import 'package:flutter/material.dart';

// Project imports:
import 'package:varnamala/views/theme.dart';

/// A memory-bounded [Image.asset] for interaction prompts.
///
/// Decodes the asset capped to the display width (clamped to 600 logical px)
/// so a multi-megapixel image is never decoded for a column-width slot. The
/// cache-width/height math uses the device pixel ratio so the decode matches
/// the physical display resolution.
///
/// Shared by [MultipleChoiceRenderer] and [MultiSelectRenderer] (previously
/// each inlined an identical `Builder` + `MediaQuery.devicePixelRatioOf`
/// block).
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
    return Image.asset(
      asset,
      fit: BoxFit.cover,
      cacheWidth: cacheWidth,
      cacheHeight: (maxHeight * dpr).round(),
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
      borderRadius: BorderRadius.circular(VarnamalaTheme.radiusMedium),
      child: CachedAssetImage(asset: asset, maxHeight: maxHeight),
    );
  }
}