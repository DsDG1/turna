import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:streaming_shared_preferences/streaming_shared_preferences.dart';
import 'package:turna/application/accessibility_provider.dart';
import 'package:turna/service/locator.dart';
import 'package:turna/views/ai/components/ai_quick_chips.dart';

void main() {
  testWidgets('focus mode removes AI recommendation chips', (tester) async {
    SharedPreferences.setMockInitialValues({});
    final prefs = AppPrefs(await StreamingSharedPreferences.instance);
    final accessibility = AccessibilityProvider(prefs);
    await accessibility.setFocusMode(true);

    await tester.pumpWidget(
      ChangeNotifierProvider<AccessibilityProvider>.value(
        value: accessibility,
        child: MaterialApp(
          home: Scaffold(
            body: AiQuickChipsBar(onChip: (_) {}),
          ),
        ),
      ),
    );

    expect(find.byType(ActionChip), findsNothing);
  });
}
