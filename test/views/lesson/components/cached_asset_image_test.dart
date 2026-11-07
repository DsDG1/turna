import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:turna/views/lesson/components/cached_asset_image.dart';

void main() {
  testWidgets('renders the bundled course SVG through the shared image widget',
      (
    tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: CachedAssetImage(asset: 'assets/images/course/nt/cay.svg'),
        ),
      ),
    );
    await tester.pump();
    expect(find.byType(SvgPicture), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
