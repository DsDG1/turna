// Flutter imports:
import 'package:flutter/foundation.dart';

/// Session state for the "return to beginner guide" floating bubble.
///
/// Armed when the user taps 「去体验」 on [BeginnerGuidePage]. The bubble is
/// rendered at the app root (MaterialApp builder) so it survives tab switches
/// and pushed routes. Dismiss clears the bubble without navigating; return
/// navigates back according to [guidePopped].
class GuideReturnController extends ChangeNotifier {
  bool _visible = false;
  bool _guidePopped = false;

  bool get visible => _visible;

  /// True when the guide was closed before the jump (tab destinations).
  /// False when the guide remains under the pushed route.
  bool get guidePopped => _guidePopped;

  /// Show the return bubble after a 「去体验」 jump.
  void arm({required bool guidePopped}) {
    _visible = true;
    _guidePopped = guidePopped;
    notifyListeners();
  }

  /// Hide the bubble without navigating (user tapped ✕).
  void dismiss() {
    if (!_visible && !_guidePopped) return;
    _visible = false;
    _guidePopped = false;
    notifyListeners();
  }

  /// Clear state when the user is already back on the guide.
  void clear() => dismiss();
}
