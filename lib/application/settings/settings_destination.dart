// Flutter imports:
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

// Project imports:
import 'package:turna/di/injection.dart';
import 'package:turna/service/tab_router.dart';

/// Strongly-typed settings destinations (Plan 2 §5.3).
///
/// Category identity must not depend on display order: inserting, removing or
/// reordering home-page tiles must never shift another category's identity the
/// way the legacy integer `_category` indices did.
enum SettingsDestination {
  account,
  learning,
  appearanceAndSound,
  accessibility,
  dataAndBackup,
  advanced,
  about,
  /// Debug-only developer lab. Never surfaced in release/profile builds.
  developer,
}

/// Second-level anchors inside [SettingsDestination.advanced], so external
/// callers can deep-link to e.g. Advanced -> AI connection in one hop.
enum SettingsAdvancedAnchor {
  aiConnection,
  storagePerformance,
  systemHealth,
  legacyCompatibility,
}

/// An immutable navigation request into the Settings tab.
class SettingsNavRequest {
  const SettingsNavRequest({required this.destination, this.anchor});

  final SettingsDestination destination;
  final SettingsAdvancedAnchor? anchor;

  @override
  bool operator ==(Object other) =>
      other is SettingsNavRequest &&
      other.destination == destination &&
      other.anchor == anchor;

  @override
  int get hashCode => Object.hash(destination, anchor);
}

/// Bridges external callers (dialogs, banners, empty states) with the
/// Settings tab's in-page navigator.
///
/// [SettingsPage] lives inside the Home `IndexedStack` and is switched to via
/// [TabRouter], so sub-page navigation stays in-page (see the routing note in
/// settings_page.dart). Callers that live outside the Settings subtree use
/// [openSettings], which first switches the Home tab and then delivers the
/// request here; the page reacts to [requests] and shows the destination.
class SettingsNavController extends ChangeNotifier {
  SettingsNavRequest? _pending;

  /// The latest request not yet consumed by the page. Cleared when the page
  /// applies it, so re-sending an identical request re-opens the destination.
  SettingsNavRequest? consumePending() {
    final request = _pending;
    _pending = null;
    return request;
  }

  void open(SettingsNavRequest request) {
    _pending = request;
    notifyListeners();
  }
}

SettingsNavController _ensureController() {
  if (!getIt.isRegistered<SettingsNavController>()) {
    if (kDebugMode) {
      debugPrint('SettingsNavController not registered; using ephemeral '
          'instance. Call setupLocator/registerSettingsNav first.');
    }
    return SettingsNavController();
  }
  return getIt<SettingsNavController>();
}

/// Unified entry point for opening a settings sub-page from anywhere in the
/// app (Plan 2 §5.3): switches the Home tab to Settings and navigates the
/// in-page navigator to [destination]. Business code must never poke integer
/// category indices.
Future<void> openSettings(
  BuildContext context,
  SettingsDestination destination, {
  SettingsAdvancedAnchor? anchor,
}) async {
  final controller = _ensureController();
  controller.open(SettingsNavRequest(destination: destination, anchor: anchor));
  getIt<TabRouter>().switchTo(TabDestination.settings);
}
