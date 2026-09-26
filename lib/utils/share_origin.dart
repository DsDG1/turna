// Flutter imports:
import 'package:flutter/widgets.dart';

/// Global rect anchoring the platform share sheet (share_plus'
/// `sharePositionOrigin`), which iPad requires — without it the
/// UIActivityViewController throws and no sheet appears.
///
/// Returns the render box of [context] in global coordinates; when the
/// context has no sized render box, falls back to the full screen. Returns
/// null for an unmounted context (callers can then skip or rely on their
/// clipboard fallback).
Rect? shareOriginFor(BuildContext context) {
  if (!context.mounted) return null;
  final renderObject = context.findRenderObject();
  if (renderObject is RenderBox && renderObject.hasSize) {
    return renderObject.localToGlobal(Offset.zero) & renderObject.size;
  }
  final size = MediaQuery.maybeSizeOf(context);
  if (size == null) return null;
  return Offset.zero & size;
}
