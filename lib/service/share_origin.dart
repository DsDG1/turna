// Flutter imports:
import 'package:flutter/widgets.dart';

/// Screen-space rect for share_plus `sharePositionOrigin`.
///
/// UIKit presents the iPad share sheet as a popover and requires a source
/// rect — without one the popover anchors at (0,0). iPhone ignores it.
/// Anchors to the calling widget when laid out, otherwise to the screen.
Rect? shareOriginFromContext(BuildContext? context) {
  final box = context?.findRenderObject();
  if (box is RenderBox && box.hasSize) {
    return box.localToGlobal(Offset.zero) & box.size;
  }
  final views = WidgetsBinding.instance.platformDispatcher.views;
  if (views.isEmpty) return null;
  final view = views.first;
  return Offset.zero & (view.physicalSize / view.devicePixelRatio);
}
