import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:streaming_shared_preferences/streaming_shared_preferences.dart';
import 'package:turna/application/accessibility_provider.dart';
import 'package:turna/application/cosmetic_provider.dart';
import 'package:turna/application/gems_provider.dart';
import 'package:turna/domain/cosmetics/cosmetic_item.dart';
import 'package:turna/service/locator.dart';
import 'package:turna/views/widgets/cosmetic_completion_badge.dart';

void main() {
  testWidgets('reduce motion renders equipped completion effect statically',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    final prefs = AppPrefs(await StreamingSharedPreferences.instance);
    final gems = GemsProvider(prefs);
    final cosmetics = CosmeticProvider(prefs, gems);
    await gems.addGems(500);
    await cosmetics.unlockAndEquipItem(CosmeticItems.completionReedBloom);
    final accessibility = AccessibilityProvider(prefs);
    await accessibility.setReducedMotion(true);
    addTearDown(() {
      gems.dispose();
      cosmetics.dispose();
      accessibility.dispose();
    });

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<CosmeticProvider>.value(value: cosmetics),
          ChangeNotifierProvider<AccessibilityProvider>.value(
            value: accessibility,
          ),
        ],
        child: const MaterialApp(
          home: Scaffold(
            body: CosmeticCompletionBadge(
              fallbackIcon: Icons.check,
              fallbackColor: Colors.green,
            ),
          ),
        ),
      ),
    );

    expect(find.byType(TweenAnimationBuilder<double>), findsNothing);
    expect(find.bySemanticsLabel(RegExp('静态效果')), findsOneWidget);
  });
}
