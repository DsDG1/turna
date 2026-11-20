import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:turna/core/theme.dart';
import 'package:turna/views/widgets/turna_geometry.dart';

void main() {
  Widget buildBackdrop({bool muted = false, bool reduceMotion = false}) {
    return MaterialApp(
      theme: TurnaTheme.lightTheme,
      home: MediaQuery(
        data: MediaQueryData(disableAnimations: reduceMotion),
        child: Scaffold(
          body: TurnaGeometryBackdrop(
            kind: TurnaGeometryKind.arch,
            alignment: Alignment.bottomCenter,
            muted: muted,
            child: ListView.builder(
              physics: const ClampingScrollPhysics(),
              itemCount: 100,
              itemBuilder: (context, index) => SizedBox(
                height: 40,
                child: Text('Row $index'),
              ),
            ),
          ),
        ),
      ),
    );
  }

  double parallaxY(WidgetTester tester) {
    final transform = tester.widget<Transform>(
      find.byKey(const Key('turna-geometry-parallax')),
    );
    return transform.transform.storage[13];
  }

  testWidgets('vertical scrolling animates a bounded geometry parallax',
      (tester) async {
    await tester.pumpWidget(buildBackdrop());
    await tester.pumpAndSettle();
    expect(parallaxY(tester), 0);

    await tester.drag(find.byType(ListView), const Offset(0, -1200));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 70));
    expect(parallaxY(tester), inExclusiveRange(-72, 0));

    await tester.pumpAndSettle();
    expect(parallaxY(tester), -72);

    await tester.drag(find.byType(ListView), const Offset(0, 1200));
    await tester.pumpAndSettle();
    expect(parallaxY(tester), 0);
  });

  testWidgets('muted state blurs and fades only the decorative layer',
      (tester) async {
    await tester.pumpWidget(buildBackdrop());
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('turna-geometry-muted-blur')), findsNothing);
    expect(
      tester
          .widget<Opacity>(
            find.byKey(const Key('turna-geometry-opacity')),
          )
          .opacity,
      1,
    );

    await tester.pumpWidget(buildBackdrop(muted: true));
    await tester.pump(const Duration(milliseconds: 70));
    expect(find.byKey(const Key('turna-geometry-muted-blur')), findsOneWidget);
    expect(
      tester
          .widget<Opacity>(
            find.byKey(const Key('turna-geometry-opacity')),
          )
          .opacity,
      inExclusiveRange(0.3, 1),
    );

    await tester.pumpAndSettle();
    expect(
      tester
          .widget<Opacity>(
            find.byKey(const Key('turna-geometry-opacity')),
          )
          .opacity,
      closeTo(0.3, 0.0001),
    );

    await tester.pumpWidget(buildBackdrop());
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('turna-geometry-muted-blur')), findsNothing);
    expect(
      tester
          .widget<Opacity>(
            find.byKey(const Key('turna-geometry-opacity')),
          )
          .opacity,
      1,
    );
  });

  testWidgets('reduced motion keeps the decoration static while scrolling',
      (tester) async {
    await tester.pumpWidget(buildBackdrop(reduceMotion: true));
    await tester.pumpAndSettle();

    await tester.drag(find.byType(ListView), const Offset(0, -400));
    await tester.pumpAndSettle();

    expect(parallaxY(tester), 0);
  });
}
