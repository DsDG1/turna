// Widget tests for the central platform route selector (plan D5).
//
// The selector may only pick official Flutter route classes per platform:
// iOS/macOS -> CupertinoPageRoute, everything else -> MaterialPageRoute.
// It must not expose or apply any animation parameters.
//
// The Android/iOS/macOS selection and the push/pop round-trip are covered
// end-to-end through the real AppRouter policy by
// adaptive_route_semantics_test.dart; this file only pins the desktop
// fallback that the adaptive tests' variant matrix does not exercise.

// Flutter imports:
import 'package:flutter/material.dart';

// Package imports:
import 'package:flutter_test/flutter_test.dart';

// Project imports:
import 'package:turna/routing/platform_page_route.dart';

Widget _host({
  required TargetPlatform platform,
  required void Function(String typeName) onRouteBuilt,
}) {
  return MaterialApp(
    theme: ThemeData(platform: platform),
    home: Builder(
      builder: (context) {
        final route = platformPageRoute<void>(
          context: context,
          builder: (_) => const Scaffold(body: SizedBox.shrink()),
        );
        onRouteBuilt(route.runtimeType.toString());
        return const SizedBox.shrink();
      },
    ),
  );
}

void main() {
  testWidgets('desktop platforms fall back to MaterialPageRoute',
      (tester) async {
    for (final platform in const [
      TargetPlatform.linux,
      TargetPlatform.windows,
    ]) {
      String? builtType;
      await tester.pumpWidget(
        _host(platform: platform, onRouteBuilt: (t) => builtType = t),
      );
      expect(builtType, contains('MaterialPageRoute'),
          reason: '$platform must never receive Cupertino route semantics');
      await tester.pumpWidget(const SizedBox.shrink());
    }
  });
}
