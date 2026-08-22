import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';

/// Platform-adaptive page route for the few internal/diagnostic pushes that
/// assemble their widget at runtime and therefore cannot be statically
/// registered in the AutoRoute table (plan D5, see
/// docs/platform-adaptive-page-transition-unification-plan.md).
///
/// It only selects an official Flutter route class per platform — no custom
/// transitions, curves, durations, or opacity. Production code must not
/// construct `MaterialPageRoute` / `CupertinoPageRoute` /
/// `PageRouteBuilder` anywhere else; the routing policy contract test
/// enforces this with this file as the only allowlisted location.
Route<T> platformPageRoute<T>({
  required BuildContext context,
  required WidgetBuilder builder,
  bool fullscreenDialog = false,
}) {
  switch (Theme.of(context).platform) {
    case TargetPlatform.iOS:
    case TargetPlatform.macOS:
      return CupertinoPageRoute<T>(
        builder: builder,
        fullscreenDialog: fullscreenDialog,
      );
    default:
      return MaterialPageRoute<T>(
        builder: builder,
        fullscreenDialog: fullscreenDialog,
      );
  }
}
