// Flutter imports:
import 'package:flutter/foundation.dart';

/// Index constants for the bottom-nav tabs owned by [HomePage].
class TabDestination {
  static const int learn = 0;
  static const int play = 1;
  static const int profile = 2;
  static const int settings = 3;
}

/// Lightweight singleton that owns the active bottom-nav tab index.
///
/// [HomePage] listens to [index] and reflects changes in its IndexedStack, so
/// any caller (e.g. a lesson dialog pushed above Home) can switch tabs via
/// `getIt<TabRouter>().switchTo(...)` without holding a reference to the
/// home state. Kept framework-only (no deps) so it can be registered manually
/// in `setupLocator` without triggering injectable codegen.
class TabRouter {
  final ValueNotifier<int> _index = ValueNotifier<int>(TabDestination.learn);

  ValueListenable<int> get index => _index;

  void switchTo(int tabIndex) {
    if (_index.value == tabIndex) return;
    _index.value = tabIndex;
  }

  void dispose() => _index.dispose();
}