import 'package:auto_route/auto_route.dart';
import 'package:flutter/foundation.dart';
import 'package:turna/routing/routing.gr.dart';

/// Release gate for internal / diagnostics routes (plan 34 R8-1).
///
/// Official-Anki reviewer and source-management pages stay flag-gated
/// diagnostics surfaces. The mapping page is a product import step
/// (doc 42 P2) and is not in [guardedRouteNames].
///
/// Diagnostics builds opt in explicitly via the
/// `TURNA_OFFICIAL_ANKI_DIAGNOSTICS` dart-define.
class DiagnosticsReleaseGuard extends AutoRouteGuard {
  const DiagnosticsReleaseGuard();

  static const Set<String> guardedRouteNames = {
    'OfficialAnkiReviewerRoute',
    // OfficialAnkiMappingRoute is the import-wizard mapping page (doc 42 P2),
    // not a diagnostics surface.
    // OfficialAnkiReviewRoute was deleted with the orphan review page
    // (doc 39 P1-A); the page lives on only as a test/support fixture.
    // OfficialAnkiMigrationPreviewRoute was deleted with the preview
    // cluster (doc 39 P1-B).
    'OfficialAnkiSourceManagementRoute',
  };

  /// Whether diagnostics surfaces are reachable in this build at all.
  static bool get diagnosticsEnabled {
    if (kDebugMode) return true;
    return const bool.fromEnvironment(
      'TURNA_OFFICIAL_ANKI_DIAGNOSTICS',
    );
  }

  static bool get isReleaseBlocked => !diagnosticsEnabled;

  static bool guards(String routeName) =>
      isReleaseBlocked && guardedRouteNames.contains(routeName);

  @override
  void onNavigation(NavigationResolver resolver, StackRouter router) {
    final name = resolver.route.name;
    if (guards(name)) {
      // Deep links land here too — abort the navigation and land on home
      // instead of showing internal surfaces in a release build.
      resolver.next(false);
      router.replaceAll([const HomeRoute()]);
      return;
    }
    resolver.next();
  }
}
