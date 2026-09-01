// Flutter imports:
import 'package:flutter/material.dart';

// Package imports:
import 'package:provider/provider.dart';

// Project imports:
import 'package:turna/application/accessibility_provider.dart';

/// The global accessibility capability contract (Plan 2 §4.3).
///
/// Components declare which capabilities they consume instead of reaching
/// into an arbitrary provider: every key surface (settings, review, AI,
/// Playground, cosmetics) can be audited and tested against this interface.
/// [AccessibilityProvider] is the single production implementation; tests
/// inject fakes to pin each capability's effect.
abstract interface class AccessibilityCapabilities {
  /// Text scale factor as a percentage (100–200).
  double get textScalePercent;

  /// Reduce motion: no decorative transitions, tweens or particles.
  bool get reduceMotion;

  /// High contrast: reinforced boundaries, never color-only signals.
  bool get highContrast;

  /// Quiet feedback: suppress sound effects and haptics.
  bool get quietFeedback;

  /// Focus mode: hide non-essential decorations and recommendations.
  bool get focusMode;

  /// All capabilities at their neutral defaults (tests / missing provider).
  static const AccessibilityCapabilities defaults =
      _DefaultAccessibilityCapabilities();
}

/// Adapter exposing [AccessibilityProvider] under the contract.
class AccessibilityCapabilitiesImpl implements AccessibilityCapabilities {
  const AccessibilityCapabilitiesImpl(this._provider);

  final AccessibilityProvider _provider;

  @override
  double get textScalePercent => _provider.textScale.toDouble();

  @override
  bool get reduceMotion => _provider.reducedMotion;

  @override
  bool get highContrast => _provider.highContrast;

  @override
  bool get quietFeedback => _provider.sensoryReduce;

  @override
  bool get focusMode => _provider.focusMode;
}

/// Resolve the capability contract from a build context: production reads
/// the scoped [AccessibilityProvider]; the neutral default keeps contexts
/// without the provider (tests, previews) crash-free.
AccessibilityCapabilities accessibilityOf(BuildContext context) {
  try {
    return AccessibilityCapabilitiesImpl(context.read<AccessibilityProvider>());
  } catch (_) {
    return AccessibilityCapabilities.defaults;
  }
}

/// Card text scale in percent (100–200), resolved reactively for card
/// renderers (WebView tracks, practice fallback): production selects the
/// scoped [AccessibilityProvider] so zoom changes rebuild the card; contexts
/// without the provider (tests, previews) stay at the neutral 100%.
int cardTextScaleOf(BuildContext context) {
  try {
    return context.select<AccessibilityProvider, int>((p) => p.cardTextScale);
  } catch (_) {
    return 100;
  }
}

class _DefaultAccessibilityCapabilities implements AccessibilityCapabilities {
  const _DefaultAccessibilityCapabilities();

  @override
  double get textScalePercent => 100;
  @override
  bool get reduceMotion => false;
  @override
  bool get highContrast => false;
  @override
  bool get quietFeedback => false;
  @override
  bool get focusMode => false;
}
