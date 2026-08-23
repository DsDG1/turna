// Unit tests for the transactional gem ledger (Plan 2 §8.4): atomic
// purchase (no "charged but not unlocked"), idempotent double taps, the
// prefs→ledger migration, and the balance projection.

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:turna/data/course_database.dart';
import 'package:turna/data/gem_ledger_dao.dart';

import '../helpers/in_memory_course_db.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late CourseDatabase db;
  late GemLedgerDao ledger;

  setUp(() {
    ensureSqliteLibForTestHost();
    db = CourseDatabase(NativeDatabase.memory());
    ledger = GemLedgerDao(db);
  });

  tearDown(() async => db.close());

  test('purchase commits spend + entitlement atomically', () async {
    final result = await ledger.purchase(
      itemId: 'ring_reed',
      price: 40,
      currentBalance: 100,
      catalogVersion: 1,
    );
    expect(result, GemPurchaseResult.success);
    expect(await ledger.hasEntitlement('ring_reed'), isTrue);
    // Opening 0 - 40 = -40 until the migration seeds an opening balance;
    // the projection must reflect every committed fact.
    expect(await ledger.projectedBalance(), -40);
  });

  test('insufficient funds charge nothing and unlock nothing', () async {
    final result = await ledger.purchase(
      itemId: 'ring_lake',
      price: 80,
      currentBalance: 10,
      catalogVersion: 1,
    );
    expect(result, GemPurchaseResult.insufficientFunds);
    expect(await ledger.hasEntitlement('ring_lake'), isFalse);
    expect(await ledger.projectedBalance(), 0);
  });

  test('double tap / retry with the same key never double-charges',
      () async {
    final key = 'purchase-ring_reed-fixed';
    for (var i = 0; i < 3; i++) {
      await ledger.purchase(
        itemId: 'ring_reed',
        price: 40,
        currentBalance: 100,
        catalogVersion: 1,
        idempotencyKey: key,
      );
    }
    expect(await ledger.projectedBalance(), -40,
        reason: 'three attempts, one charge');
  });

  test('already-owned purchase is a no-op', () async {
    await ledger.purchase(
      itemId: 'ring_reed',
      price: 40,
      currentBalance: 100,
      catalogVersion: 1,
    );
    final second = await ledger.purchase(
      itemId: 'ring_reed',
      price: 40,
      currentBalance: 100,
      catalogVersion: 1,
    );
    expect(second, GemPurchaseResult.alreadyOwned);
    expect(await ledger.projectedBalance(), -40);
  });

  test('earn events are idempotent per event id', () async {
    expect(
      await ledger.record(
        kind: GemLedgerKind.earn,
        amount: 5,
        reason: 'lessonComplete',
        eventId: 'lesson-l1',
      ),
      isTrue,
    );
    expect(
      await ledger.record(
        kind: GemLedgerKind.earn,
        amount: 5,
        reason: 'lessonComplete',
        eventId: 'lesson-l1',
      ),
      isFalse,
      reason: 'the same game event must not credit twice',
    );
    expect(await ledger.projectedBalance(), 5);
  });

  test('prefs migration is idempotent and preserves balance + unlocks',
      () async {
    const legacyBalance = 120;
    const unlocked = {'ring_reed'};

    expect(
      await ledger.migrateFromPrefs(
        prefsBalance: legacyBalance,
        unlockedItemIds: unlocked,
      ),
      isTrue,
    );
    expect(await ledger.projectedBalance(), legacyBalance);
    expect(await ledger.entitledItemIds(), unlocked);

    // Running the migration again changes nothing.
    expect(
      await ledger.migrateFromPrefs(
        prefsBalance: legacyBalance,
        unlockedItemIds: unlocked,
      ),
      isTrue,
    );
    expect(await ledger.projectedBalance(), legacyBalance,
        reason: 'idempotent migration must not re-credit the opening balance');
    expect(await ledger.entitledItemIds(), unlocked);
  });
}
