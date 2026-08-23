import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:streaming_shared_preferences/streaming_shared_preferences.dart';
import 'package:turna/application/accessibility_provider.dart';
import 'package:turna/application/cosmetic_provider.dart';
import 'package:turna/application/gems_provider.dart';
import 'package:turna/data/course_database.dart';
import 'package:turna/data/gem_ledger_dao.dart';
import 'package:turna/di/injection.dart';
import 'package:turna/service/locator.dart';
import 'package:turna/views/settings/avatar_rings_page.dart';

import '../../helpers/in_memory_course_db.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('shop keeps prices and actions visible at 200% text',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    final prefs = AppPrefs(await StreamingSharedPreferences.instance);
    final gems = GemsProvider(prefs);
    final cosmetics = CosmeticProvider(prefs, gems);
    final accessibility = AccessibilityProvider(prefs);
    await accessibility.setHighContrast(true);
    await tester.binding.setSurfaceSize(const Size(520, 900));
    addTearDown(() async {
      await tester.binding.setSurfaceSize(null);
      gems.dispose();
      cosmetics.dispose();
      accessibility.dispose();
    });

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<GemsProvider>.value(value: gems),
          ChangeNotifierProvider<CosmeticProvider>.value(value: cosmetics),
          ChangeNotifierProvider<AccessibilityProvider>.value(
            value: accessibility,
          ),
        ],
        child: MaterialApp(
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(context).copyWith(
              textScaler: const TextScaler.linear(2),
              highContrast: true,
            ),
            child: child!,
          ),
          home: const AvatarRingsPage(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.text('连续学习保护券'), findsOneWidget);
    expect(find.text('40'), findsWidgets);
    expect(find.byType(FilledButton), findsWidgets);
  });

  testWidgets('shop explains and disables the monthly voucher cap',
      (tester) async {
    await getIt.reset();
    ensureSqliteLibForTestHost();
    SharedPreferences.setMockInitialValues({LocalStateKeys.gems: 200});
    final prefs = AppPrefs(await StreamingSharedPreferences.instance);
    await prefs.preferences.setInt(LocalStateKeys.gems, 200);
    final db = CourseDatabase(NativeDatabase.memory());
    final ledger = GemLedgerDao(db);
    getIt.registerSingleton<GemLedgerDao>(ledger);
    final gems = GemsProvider(prefs);
    final cosmetics = CosmeticProvider(prefs, gems);
    addTearDown(() async {
      gems.dispose();
      cosmetics.dispose();
      await getIt.reset();
      await db.close();
    });

    await gems.ensureGemsInitialized();
    expect(
      await gems.purchaseStreakVoucher(idempotencyKey: 'shop-cap-1'),
      GemConsumablePurchaseResult.success,
    );
    expect(
      await gems.purchaseStreakVoucher(idempotencyKey: 'shop-cap-2'),
      GemConsumablePurchaseResult.success,
    );

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<GemsProvider>.value(value: gems),
          ChangeNotifierProvider<CosmeticProvider>.value(value: cosmetics),
        ],
        child: const MaterialApp(home: AvatarRingsPage()),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.textContaining('本月购买已达上限 2/2'), findsOneWidget);
    final button = tester.widget<FilledButton>(
      find.byKey(const Key('streak-voucher-purchase')),
    );
    expect(button.onPressed, isNull);
  });
}
