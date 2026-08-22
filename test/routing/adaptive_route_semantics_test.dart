// Widget tests for the platform-adaptive AutoRoute semantics (plan §7.2).
//
// The test router reuses the *real* [AppRouter.defaultRouteType] instance so
// these tests exercise the app's actual routing policy through auto_route's
// runtime: Android gets Material page routes, iOS/macOS get real Cupertino
// page routes (edge-swipe pop semantics), and push/pop round-trips work.

// Flutter imports:
import 'package:flutter/material.dart';

// Package imports:
import 'package:auto_route/auto_route.dart';
import 'package:flutter_test/flutter_test.dart';

// Project imports:
import 'package:turna/application/course_provider.dart';
import 'package:turna/routing/course_ready_guard.dart';
import 'package:turna/routing/routing.dart';

/// Stand-in so [AppRouter] can be constructed without a course load path.
class _StubCourseProvider extends CourseProvider {
  @override
  bool get isLoaded => true;
}

/// Hand-written lightweight route entries (no codegen in tests).
class _HostRoute extends PageRouteInfo<void> {
  const _HostRoute() : super(_HostRoute.name);

  static const String name = '_HostRoute';

  static PageInfo page = PageInfo(
    name,
    builder: (_) => const _HostScreen(),
  );
}

class _TargetRoute extends PageRouteInfo<void> {
  const _TargetRoute() : super(_TargetRoute.name);

  static const String name = '_TargetRoute';

  static PageInfo page = PageInfo(
    name,
    builder: (_) => const _TargetScreen(),
  );
}

class _SemanticsRouter extends RootStackRouter {
  _SemanticsRouter(this.policy);

  final RouteType policy;

  @override
  RouteType get defaultRouteType => policy;

  @override
  List<AutoRoute> get routes => [
        AutoRoute(page: _HostRoute.page, initial: true),
        AutoRoute(page: _TargetRoute.page),
      ];
}

/// Captured runtime type of the top-most ModalRoute while building.
String? lastSeenRouteType;

class _HostScreen extends StatelessWidget {
  const _HostScreen();

  @override
  Widget build(BuildContext context) {
    lastSeenRouteType = ModalRoute.of(context)?.runtimeType.toString();
    return Scaffold(
      body: Center(
        child: TextButton(
          key: const Key('push-target'),
          onPressed: () => context.router.push(const _TargetRoute()),
          child: const Text('push'),
        ),
      ),
    );
  }
}

class _TargetScreen extends StatelessWidget {
  const _TargetScreen();

  @override
  Widget build(BuildContext context) {
    lastSeenRouteType = ModalRoute.of(context)?.runtimeType.toString();
    return const Scaffold(
      key: Key('target-screen'),
      body: SizedBox.shrink(),
    );
  }
}

Future<void> _pumpWithPolicy(WidgetTester tester, RouteType policy) async {
  final router = _SemanticsRouter(policy);
  await tester.pumpWidget(
    MaterialApp.router(routerConfig: router.config()),
  );
  await tester.pumpAndSettle();
}

void main() {
  // The app's real policy object, not a lookalike.
  final appPolicy =
      AppRouter(CourseReadyGuard(_StubCourseProvider())).defaultRouteType;

  tearDown(() {
    lastSeenRouteType = null;
  });

  testWidgets('Android builds Material page routes', (tester) async {
    await _pumpWithPolicy(tester, appPolicy);

    await tester.tap(find.byKey(const Key('push-target')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('target-screen')), findsOneWidget);
    expect(lastSeenRouteType, contains('Material'),
        reason: 'Android auto-routes must use Material semantics, not the '
            'former forced Cupertino slide-in');
  }, variant: TargetPlatformVariant.only(TargetPlatform.android));

  testWidgets('iOS builds real Cupertino page routes', (tester) async {
    await _pumpWithPolicy(tester, appPolicy);

    await tester.tap(find.byKey(const Key('push-target')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('target-screen')), findsOneWidget);
    expect(lastSeenRouteType, contains('Cupertino'),
        reason: 'iOS must get an actual CupertinoPageRoute so edge-swipe '
            'back works');
  }, variant: TargetPlatformVariant.only(TargetPlatform.iOS));

  testWidgets('macOS builds real Cupertino page routes', (tester) async {
    await _pumpWithPolicy(tester, appPolicy);

    await tester.tap(find.byKey(const Key('push-target')));
    await tester.pumpAndSettle();

    expect(lastSeenRouteType, contains('Cupertino'));
  }, variant: TargetPlatformVariant.only(TargetPlatform.macOS));

  testWidgets('push/pop round-trip returns to the previous page',
      (tester) async {
    await _pumpWithPolicy(tester, appPolicy);

    await tester.tap(find.byKey(const Key('push-target')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('target-screen')), findsOneWidget);

    tester.state<NavigatorState>(find.byType(Navigator).first).pop();
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('target-screen')), findsNothing);
    expect(find.text('push'), findsOneWidget);
  }, variant: TargetPlatformVariant.only(TargetPlatform.android));

  test('app policy carries the predictive back flag', () {
    expect(appPolicy, isA<AdaptiveRouteType>());
    expect(
        (appPolicy as AdaptiveRouteType).enablePredictiveBackGesture, isTrue);
  });
}
