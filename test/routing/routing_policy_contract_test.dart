// Routing policy contract tests (plan §7.1 /
// docs/platform-adaptive-page-transition-unification-plan.md).
//
// These tests lock in the platform-adaptive navigation policy:
//   1. AutoRoute default route type is adaptive with predictive back enabled.
//   2. No per-route type overrides fork away from the global policy.
//   3. No custom page transitions exist anywhere in production code.
//   4. Official route classes are only constructed in the single allowed
//      platform route selector.
//   5. Bottom tabs stay a mounted state-preserving switcher
//      (TabStack, native-default instant switching), not page routes.
//   6. Android predictive-back manifest opt-in is present.

// Dart imports:
import 'dart:io';

// Package imports:
import 'package:auto_route/auto_route.dart';
import 'package:flutter_test/flutter_test.dart';

// Project imports:
import 'package:turna/application/course_provider.dart';
import 'package:turna/routing/course_ready_guard.dart';
import 'package:turna/routing/routing.dart';

/// Minimal stand-in so [AppRouter] can be constructed without a full
/// [CourseProvider] load path (same approach as course_ready_guard_test).
class _StubCourseProvider extends CourseProvider {
  _StubCourseProvider() : _loaded = true;

  final bool _loaded;

  @override
  bool get isLoaded => _loaded;
}

/// The only file allowed to construct `MaterialPageRoute` /
/// `CupertinoPageRoute` / `PageRouteBuilder` directly (plan D5).
const _routeClassAllowlist = {
  'lib/routing/platform_page_route.dart',
};

const _libRoot = 'lib';

List<File> _dartFilesUnder(String root) {
  return Directory(root)
      .listSync(recursive: true)
      .whereType<File>()
      .where((f) => f.path.endsWith('.dart'))
      .toList();
}

String _read(File file) => file.readAsStringSync();

void main() {
  late AppRouter router;

  setUp(() {
    router = AppRouter(CourseReadyGuard(_StubCourseProvider()));
  });

  group('global route policy', () {
    test('defaultRouteType is platform-adaptive with predictive back', () {
      final type = router.defaultRouteType;
      expect(type, isA<AdaptiveRouteType>());
      final adaptive = type as AdaptiveRouteType;
      expect(adaptive.enablePredictiveBackGesture, isTrue,
          reason: 'Android predictive back must stay enabled');
    });

    test('predictive back uses the platform default transitions builder', () {
      final adaptive = router.defaultRouteType as AdaptiveRouteType;
      expect(adaptive.predictiveBackPageTransitionsBuilder, isNull,
          reason: 'A custom predictive-back builder would be a custom '
              'transition, which the plan forbids');
    });

    test('no route overrides the global platform-adaptive type', () {
      final offenders =
          router.routes.where((route) => route.type != null).toList();
      expect(offenders, isEmpty,
          reason: 'Per-route type overrides fork the navigation policy: '
              '${offenders.map((r) => r.name).join(', ')}');
    });

    test('routing.dart never forces a single-platform route type', () {
      final source = _read(File('$_libRoot/routing/routing.dart'));
      expect(source, isNot(contains('RouteType.cupertino()')));
      expect(source, isNot(contains('RouteType.material(')));
      expect(source, isNot(contains('RouteType.custom(')));
    });
  });

  group('production code has no custom page transitions', () {
    test('no PageRouteBuilder / transitionsBuilder outside allowlist', () {
      final files = _dartFilesUnder(_libRoot);
      expect(files, isNotEmpty);
      for (final file in files) {
        final path = file.path;
        final source = _read(file);
        expect(source, isNot(contains('PageRouteBuilder(')),
            reason: '$path must not construct PageRouteBuilder');
        expect(source, isNot(contains('transitionsBuilder')),
            reason: '$path must not define or pass a transitionsBuilder');
      }
    });

    test('official route classes are only built in the platform selector', () {
      final files = _dartFilesUnder(_libRoot);
      const patterns = ['MaterialPageRoute(', 'CupertinoPageRoute('];
      for (final file in files) {
        final path = file.path;
        final source = _read(file);
        for (final pattern in patterns) {
          if (!source.contains(pattern)) continue;
          final allowed = _routeClassAllowlist
              .any((allowedPath) => path.endsWith(allowedPath));
          expect(allowed, isTrue,
              reason: '$path constructs $pattern directly — route pages '
                  'through AutoRoute or lib/routing/platform_page_route.dart');
        }
      }
    });
  });

  group('navigation semantics stay layered', () {
    test('bottom tabs stay a mounted state-preserving switcher', () {
      final source = _read(File('$_libRoot/views/home/home_page.dart'));
      expect(source, contains('TabStack'),
          reason: 'Bottom tabs must not become pushed page routes; the '
              'stack keeps all tab subtrees mounted (state preserved)');
      expect(source, isNot(contains('router.push')),
          reason: 'Tab switching must stay on TabRouter, never route pushes');
    });

    test('theme does not override pageTransitionsTheme', () {
      final source = _read(File('$_libRoot/views/theme.dart'));
      expect(source, isNot(contains('PageTransitionsTheme')),
          reason: 'Android must use the SDK default page transitions');
    });
  });

  group('Android predictive back opt-in', () {
    test('manifest declares enableOnBackInvokedCallback', () {
      final manifest = _read(File('android/app/src/main/AndroidManifest.xml'));
      expect(manifest, contains('android:enableOnBackInvokedCallback="true"'));
    });
  });
}
