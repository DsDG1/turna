// Widget tests for the central platform route selector (plan D5).
//
// The selector may only pick official Flutter route classes per platform:
// iOS/macOS -> CupertinoPageRoute, everything else -> MaterialPageRoute.
// It must not expose or apply any animation parameters.

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
  testWidgets('Android theme selects MaterialPageRoute', (tester) async {
    String? builtType;
    await tester.pumpWidget(
      _host(
          platform: TargetPlatform.android, onRouteBuilt: (t) => builtType = t),
    );
    expect(builtType, contains('MaterialPageRoute'));
  });

  testWidgets('iOS theme selects CupertinoPageRoute', (tester) async {
    String? builtType;
    await tester.pumpWidget(
      _host(platform: TargetPlatform.iOS, onRouteBuilt: (t) => builtType = t),
    );
    expect(builtType, contains('CupertinoPageRoute'));
  });

  testWidgets('macOS theme selects CupertinoPageRoute', (tester) async {
    String? builtType;
    await tester.pumpWidget(
      _host(platform: TargetPlatform.macOS, onRouteBuilt: (t) => builtType = t),
    );
    expect(builtType, contains('CupertinoPageRoute'));
  });

  testWidgets('desktop platforms fall back to MaterialPageRoute',
      (tester) async {
    String? builtType;
    await tester.pumpWidget(
      _host(platform: TargetPlatform.linux, onRouteBuilt: (t) => builtType = t),
    );
    expect(builtType, contains('MaterialPageRoute'));
  });

  testWidgets('selector-produced route pushes and pops through a Navigator',
      (tester) async {
    var popped = false;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => TextButton(
            onPressed: () async {
              await Navigator.of(context).push(
                platformPageRoute<void>(
                  context: context,
                  builder: (_) => const Scaffold(
                    key: Key('pushed-page'),
                    body: SizedBox.shrink(),
                  ),
                ),
              );
              popped = true;
            },
            child: const Text('push'),
          ),
        ),
      ),
    );

    await tester.tap(find.text('push'));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('pushed-page')), findsOneWidget);

    tester.state<NavigatorState>(find.byType(Navigator).first).pop();
    await tester.pumpAndSettle();
    expect(popped, isTrue);
  });
}
