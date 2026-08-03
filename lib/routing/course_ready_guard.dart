// Flutter imports:
import 'package:flutter/foundation.dart';

// Package imports:
import 'package:auto_route/auto_route.dart';
import 'package:injectable/injectable.dart';

// Project imports:
import 'package:turna/application/course_provider.dart';
import 'package:turna/routing/routing.gr.dart';

/// Redirects to [SplashRoute] when the course shells have not finished loading.
///
/// Minimal route-guard skeleton for Phase 18 — currently wired only on
/// [HomeRoute] so the mechanism is exercised without blocking splash or
/// settings. Phase 22 dictionary (and other deep links) can reuse this guard.
@lazySingleton
class CourseReadyGuard extends AutoRouteGuard {
  CourseReadyGuard(this._courseProvider);

  final CourseProvider _courseProvider;

  @override
  void onNavigation(NavigationResolver resolver, StackRouter router) {
    if (_courseProvider.isLoaded) {
      resolver.next(true);
      return;
    }

    // Course not ready: abort the original navigation and land on splash.
    // Splash is always allowed (no guard) and surfaces loading / get-started.
    resolver.next(false);
    router.replaceAll([const SplashRoute()]);
  }
}
