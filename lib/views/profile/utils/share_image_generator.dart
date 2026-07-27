// Dart imports:
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

// Flutter imports:
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

// Package imports:
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

/// Captures a [ShareProgressCard] to a PNG and shares it via the platform sheet.
///
/// Attach [boundaryKey] to a *laid-out* (painted) [ShareProgressCard] — e.g. the
/// visible preview inside the share sheet — wrapped in a [RepaintBoundary]. Do
/// NOT wrap the capture target in [Offstage]: an offstage subtree is never
/// laid out or painted, so its [RenderRepaintBoundary] has no context and
/// [RenderRepaintBoundary.toImage] cannot capture it.
class ShareProgressImageGenerator {
  final GlobalKey _boundaryKey = GlobalKey();

  /// The key the caller must attach to a laid-out [RepaintBoundary] wrapping the
  /// card to capture. Exposed so the visible preview card can double as the
  /// capture target (no separate offstage widget needed).
  GlobalKey get boundaryKey => _boundaryKey;

  /// Renders the capture target to a PNG and opens the platform share sheet.
  ///
  /// [shareText] is the localized text passed to the platform share sheet.
  Future<void> captureAndShare({required String shareText}) async {
    final boundary = _boundaryKey.currentContext?.findRenderObject()
        as RenderRepaintBoundary?;

    if (boundary == null) {
      throw StateError(
        'ShareProgressCard is not laid out yet. '
        'Make sure boundaryKey is attached to a laid-out RepaintBoundary.',
      );
    }

    // Ensure the current frame has finished laying out + painting the boundary
    // before rasterizing it, so the capture is not taken mid-build.
    await WidgetsBinding.instance.endOfFrame;

    // Cap the raster pixel ratio to 3.0: on high-DPR devices (4x) capturing at
    // the native ratio produces very large images and the PNG encode becomes
    // a visible jank source. 3.0 is visually crisp while keeping the encode
    // bounded.
    final views = WidgetsBinding.instance.platformDispatcher.views;
    final deviceRatio = views.isEmpty ? 1.0 : views.first.devicePixelRatio;
    final pixelRatio = deviceRatio < 3.0 ? deviceRatio : 3.0;

    final ui.Image image = await boundary.toImage(pixelRatio: pixelRatio);
    final ByteData? byteData =
        await image.toByteData(format: ui.ImageByteFormat.png);
    if (byteData == null) {
      throw StateError('Failed to encode share image to PNG (toByteData null).');
    }
    final Uint8List pngBytes = byteData.buffer.asUint8List();

    final tempDir = await getTemporaryDirectory();
    final file = File('${tempDir.path}/varnamala_progress.png');
    await file.writeAsBytes(pngBytes);

    await Share.shareXFiles(
      [XFile(file.path)],
      text: shareText,
    );
  }
}
