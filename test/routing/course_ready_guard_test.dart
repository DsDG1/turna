// Unit tests for [CourseReadyGuard] redirect semantics.

import 'package:auto_route/auto_route.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:varnamala/application/course_provider.dart';
import 'package:varnamala/routing/course_ready_guard.dart';

/// Minimal stand-in so we do not need a full [CourseProvider] load path.
class _StubCourseProvider extends CourseProvider {
  _StubCourseProvider({required bool loaded}) : _loaded = loaded;

  final bool _loaded;

  @override
  bool get isLoaded => _loaded;
}

class _FakeResolver implements NavigationResolver {
  bool? nextValue;
  bool nextCalled = false;

  @override
  void next([bool continueNavigation = true]) {
    nextCalled = true;
    nextValue = continueNavigation;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeStackRouter implements StackRouter {
  final List<PageRouteInfo> replaced = [];

  @override
  Future<void> replaceAll(
    List<PageRouteInfo> routes, {
    OnNavigationFailure? onFailure,
    bool updateExistingRoutes = true,
  }) async {
    replaced
      ..clear()
      ..addAll(routes);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  group('CourseReadyGuard', () {
    test('allows navigation when course is loaded', () {
      final guard = CourseReadyGuard(_StubCourseProvider(loaded: true));
      final resolver = _FakeResolver();
      final router = _FakeStackRouter();

      guard.onNavigation(resolver, router);

      expect(resolver.nextCalled, isTrue);
      expect(resolver.nextValue, isTrue);
      expect(router.replaced, isEmpty);
    });

    test('aborts and replaces with Splash when course is not loaded', () {
      final guard = CourseReadyGuard(_StubCourseProvider(loaded: false));
      final resolver = _FakeResolver();
      final router = _FakeStackRouter();

      guard.onNavigation(resolver, router);

      expect(resolver.nextCalled, isTrue);
      expect(resolver.nextValue, isFalse);
      expect(router.replaced, hasLength(1));
      expect(router.replaced.single.routeName, 'SplashRoute');
    });
  });
}
