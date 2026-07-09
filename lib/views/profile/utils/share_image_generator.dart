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

// Project imports:
import 'package:words625/core/enums.dart';
import 'package:words625/domain/auth/local_user.dart';
import 'package:words625/views/profile/widgets/share_progress_card.dart';

/// Captures a [ShareProgressCard] to a PNG and shares it via the platform sheet.
class ShareProgressImageGenerator {
  final GlobalKey _boundaryKey = GlobalKey();

  /// Builds an offstage capture target that can be rendered into an image.
  ///
  /// Place this widget in the widget tree before calling [captureAndShare].
  /// It is sized to zero so it does not affect layout.
  Widget captureTarget({
    required SerializableFirebaseUser user,
    required int streak,
    required int totalXp,
    required int gems,
    required int completedLessons,
    required int perfectLessons,
    required TargetLanguage targetLanguage,
  }) {
    return Offstage(
      child: RepaintBoundary(
        key: _boundaryKey,
        child: ShareProgressCard(
          user: user,
          streak: streak,
          totalXp: totalXp,
          gems: gems,
          completedLessons: completedLessons,
          perfectLessons: perfectLessons,
          targetLanguage: targetLanguage,
        ),
      ),
    );
  }

  /// Renders the capture target to a PNG and opens the platform share sheet.
  Future<void> captureAndShare() async {
    final boundary = _boundaryKey.currentContext?.findRenderObject()
        as RenderRepaintBoundary?;

    if (boundary == null) {
      throw StateError(
        'ShareProgressCard is not laid out yet. '
        'Make sure captureTarget() is in the widget tree.',
      );
    }

    final ui.Image image = await boundary.toImage(pixelRatio: 3.0);
    final ByteData? byteData =
        await image.toByteData(format: ui.ImageByteFormat.png);
    final Uint8List pngBytes = byteData!.buffer.asUint8List();

    final tempDir = await getTemporaryDirectory();
    final file = File('${tempDir.path}/varnamala_progress.png');
    await file.writeAsBytes(pngBytes);

    await Share.shareXFiles(
      [XFile(file.path)],
      text: 'Check out my progress on Varnamala!',
    );
  }
}
