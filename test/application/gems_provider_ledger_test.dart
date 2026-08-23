import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:streaming_shared_preferences/streaming_shared_preferences.dart';
import 'package:turna/application/cosmetic_provider.dart';
import 'package:turna/application/gems_provider.dart';
import 'package:turna/data/course_database.dart';
import 'package:turna/data/gem_ledger_dao.dart';
import 'package:turna/di/injection.dart';
import 'package:turna/domain/cosmetics/avatar_ring.dart';
import 'package:turna/service/locator.dart';

import '../helpers/in_memory_course_db.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late CourseDatabase db;
  late GemLedgerDao ledger;
  late AppPrefs prefs;
  late GemsProvider gems;

  setUp(() async {
    ensureSqliteLibForTestHost();
    SharedPreferences.setMockInitialValues({});
    prefs = AppPrefs(await StreamingSharedPreferences.instance);
    db = CourseDatabase(NativeDatabase.memory());
    ledger = GemLedgerDao(db);
    if (getIt.isRegistered<GemLedgerDao>()) {
      await getIt.unregister<GemLedgerDao>();
    }
    getIt.registerSingleton<GemLedgerDao>(ledger);
    gems = GemsProvider(prefs);
  });

  tearDown(() async {
    gems.dispose();
    if (getIt.isRegistered<GemLedgerDao>()) {
      await getIt.unregister<GemLedgerDao>();
    }
    await db.close();
  });

  Future<int> countRows({required String kind, String? reasonPrefix}) async {
    final where =
        reasonPrefix == null ? 'kind = ?' : "kind = ? AND reason LIKE ? || '%'";
    final variables = <Object?>[
      kind,
      if (reasonPrefix != null) reasonPrefix,
    ];
    final rows = await db
        .customSelect(
          'SELECT COUNT(*) AS n FROM gem_ledger WHERE $where',
          variables: variables
              .map((value) => Variable<String>(value! as String))
              .toList(),
        )
        .get();
    return rows.single.read<int>('n');
  }

  test('startup migrates prefs and duplicate event id never double-credits',
      () async {
    await prefs.preferences.setInt(LocalStateKeys.gems, 20);
    await gems.ensureGemsInitialized();

    const eventId = 'earn:lesson:intro:2026-08-23';
    await gems.earnGems(GemEvent.lessonComplete, eventId: eventId);
    await gems.earnGems(GemEvent.lessonComplete, eventId: eventId);

    expect(gems.balance, 25);
    expect(await ledger.projectedBalance(), 25);
    expect(await countRows(kind: GemLedgerKind.earn.name), 1);
  });

  test('prefs above ledger creates explicit adjustment and converges',
      () async {
    await prefs.preferences.setInt(LocalStateKeys.gems, 20);
    await gems.ensureGemsInitialized();
    await prefs.preferences.setInt(LocalStateKeys.gems, 80);

    await gems.ensureGemsInitialized();

    expect(gems.lastReconciliationDifference, 60);
    expect(gems.balance, 80);
    expect(await ledger.projectedBalance(), 80);
    expect(
      await countRows(
        kind: GemLedgerKind.adjustment.name,
        reasonPrefix: 'reconcile:prefs_above_ledger',
      ),
      1,
    );
  });

  test('ledger above prefs wins and leaves a zero-value adjustment audit row',
      () async {
    await prefs.preferences.setInt(LocalStateKeys.gems, 20);
    await gems.ensureGemsInitialized();
    await gems.addGems(15);
    await prefs.preferences.setInt(LocalStateKeys.gems, 3);

    await gems.ensureGemsInitialized();

    expect(gems.lastReconciliationDifference, -32);
    expect(gems.balance, 35);
    expect(await ledger.projectedBalance(), 35);
    expect(
      await countRows(
        kind: GemLedgerKind.adjustment.name,
        reasonPrefix: 'reconcile:ledger_above_prefs',
      ),
      1,
    );
  });

  test('atomic cosmetic purchase is mirrored once, not charged twice',
      () async {
    await prefs.preferences.setInt(LocalStateKeys.gems, 100);
    await gems.ensureGemsInitialized();
    final cosmetics = CosmeticProvider(prefs, gems);

    expect(
      await cosmetics.unlockAndEquip(kAvatarRingReed),
      CosmeticActionResult.unlockedAndEquipped,
    );

    expect(gems.balance, 60);
    expect(await ledger.projectedBalance(), 60);
    expect(await countRows(kind: GemLedgerKind.spend.name), 1);
    expect(await ledger.hasEntitlement(kAvatarRingReed), isTrue);
    cosmetics.dispose();
  });
}
