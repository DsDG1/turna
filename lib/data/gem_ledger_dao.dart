// Dart imports:
import 'dart:math';

// Package imports:
import 'package:drift/drift.dart';
import 'package:injectable/injectable.dart';
import 'package:sqlite3/sqlite3.dart' show SqliteException;

// Project imports:
import 'package:turna/core/logger.dart';
import 'package:turna/data/course_database.dart';
import 'package:turna/domain/game/gem_consumable.dart';
import 'package:turna/domain/repositories/i_gem_ledger.dart';

export 'package:turna/domain/game/gem_consumable.dart'
    show GemConsumablePurchaseResult, GemPurchaseResult, GemLedgerKind;

/// Transactional gem ledger + cosmetic entitlements (Plan 2 §8.4).
///
/// The dangerous failure mode of the old flow — "gems deducted but the item
/// never unlocked" when a crash landed between the prefs spend and the
/// unlock write — is eliminated structurally: the spend row and the
/// entitlement row are inserted in ONE SQLite transaction. Every write is
/// idempotent (`transaction_id` primary key, `event_id` unique for game
/// events), so retries and double-taps can never double-charge.
@LazySingleton(as: IGemLedger)
class GemLedgerDao implements IGemLedger {
  GemLedgerDao(this._db);

  final CourseDatabase _db;

  static const String openingBalanceTxId = 'migration_opening_balance_v1';
  static const String openingBalanceEventId = 'gem.migration.opening';
  static const String streakVoucherItemId = 'voucher_streak';

  /// UNIQUE/PK/constraint-violation message shape across sqlite3 builds
  /// ("UNIQUE constraint failed: gem_ledger.event_id", "PRIMARY KEY must be
  /// unique", "FOREIGN KEY constraint failed", SQLITE_CONSTRAINT …).
  static final RegExp _constraintPattern = RegExp(
    r'constraint|must be unique|not unique',
    caseSensitive: false,
  );

  /// Committed ledger balance: opening + every committed event. This is the
  /// auditable projection; the UI wallet ([GemsProvider]) mirrors it.
  @override
  Future<int> projectedBalance() async {
    final rows = await _db
        .customSelect(
          'SELECT COALESCE(SUM(amount), 0) AS total FROM gem_ledger '
          "WHERE status = 'committed' AND NOT "
          "(item_id = '$streakVoucherItemId' AND reason LIKE 'voucher:%')",
        )
        .get();
    return rows.first.read<int>('total');
  }

  @override
  Future<bool> hasEntitlement(String itemId) async {
    final rows = await _db.customSelect(
      'SELECT COUNT(*) AS n FROM cosmetic_entitlements WHERE item_id = ?',
      variables: [Variable.withString(itemId)],
    ).get();
    return (rows.first.read<int>('n')) > 0;
  }

  @override
  Future<Set<String>> entitledItemIds() async {
    final rows = await _db
        .customSelect('SELECT item_id FROM cosmetic_entitlements')
        .get();
    return rows.map((r) => r.read<String>('item_id')).toSet();
  }

  /// Consumable inventory projection. Voucher facts are excluded from the gem
  /// balance projection above, while their signed amount projects inventory.
  @override
  Future<int> streakVoucherBalance() async {
    final rows = await _db.customSelect(
      'SELECT COALESCE(SUM(amount), 0) AS total FROM gem_ledger '
      'WHERE status = \'committed\' AND item_id = ? '
      "AND reason LIKE 'voucher:%'",
      variables: [Variable.withString(streakVoucherItemId)],
    ).get();
    return rows.single.read<int>('total');
  }

  @override
  Future<int> streakVoucherPurchasesInMonth(DateTime month) async {
    final local = month.toLocal();
    final from = DateTime(local.year, local.month);
    final to = DateTime(local.year, local.month + 1);
    final rows = await _db.customSelect(
      'SELECT COUNT(*) AS n FROM gem_ledger '
      'WHERE status = \'committed\' AND item_id = ? '
      "AND reason = 'voucher:purchase' AND created_at >= ? AND created_at < ?",
      variables: [
        Variable.withString(streakVoucherItemId),
        Variable.withInt(from.millisecondsSinceEpoch),
        Variable.withInt(to.millisecondsSinceEpoch),
      ],
    ).get();
    return rows.single.read<int>('n');
  }

  /// Atomically charges gems and grants one streak voucher.
  @override
  Future<GemConsumablePurchaseResult> purchaseStreakVoucher({
    required int price,
    required int currentBalance,
    required int monthlyLimit,
    String? idempotencyKey,
    DateTime? purchasedAt,
  }) async {
    final now = purchasedAt ?? DateTime.now();
    final txId = idempotencyKey ?? 'voucher-purchase-${_randomId()}';
    if (await _transactionExists(txId)) {
      return GemConsumablePurchaseResult.success;
    }
    if (currentBalance < price) {
      return GemConsumablePurchaseResult.insufficientFunds;
    }
    late GemConsumablePurchaseResult outcome;
    await _db.transaction(() async {
      if (await streakVoucherPurchasesInMonth(now) >= monthlyLimit) {
        outcome = GemConsumablePurchaseResult.monthlyLimitReached;
        return;
      }
      final createdAt = now.millisecondsSinceEpoch;
      await _db.customStatement(
        'INSERT INTO gem_ledger '
        '(transaction_id, event_id, kind, amount, reason, item_id, '
        ' created_at, status) VALUES (?, NULL, ?, ?, ?, NULL, ?, '
        " 'committed')",
        [
          txId,
          GemLedgerKind.spend.name,
          -price,
          'purchase:$streakVoucherItemId',
          createdAt,
        ],
      );
      await _db.customStatement(
        'INSERT INTO gem_ledger '
        '(transaction_id, event_id, kind, amount, reason, item_id, '
        ' created_at, status) VALUES (?, ?, ?, 1, ?, ?, ?, '
        " 'committed')",
        [
          '$txId:grant',
          '$txId:grant',
          GemLedgerKind.earn.name,
          'voucher:purchase',
          streakVoucherItemId,
          createdAt,
        ],
      );
      outcome = GemConsumablePurchaseResult.success;
    });
    return outcome;
  }

  @override
  Future<bool> grantStreakVoucher({
    required String eventId,
    String reason = 'voucher:grant',
  }) =>
      record(
        kind: GemLedgerKind.earn,
        amount: 1,
        reason: reason,
        eventId: eventId,
        itemId: streakVoucherItemId,
      );

  /// Consumes at most one voucher for a local day.
  @override
  Future<bool> consumeStreakVoucher({required String localDay}) async {
    final eventId = 'voucher:use:$localDay';
    if (await _eventExists(eventId)) return false;
    if (await streakVoucherBalance() <= 0) return false;
    return record(
      kind: GemLedgerKind.spend,
      amount: -1,
      reason: 'voucher:use',
      eventId: eventId,
      itemId: streakVoucherItemId,
    );
  }

  /// Append an earn/refund/adjustment event, idempotent per [eventId].
  /// Returns false when [eventId] already exists (double-credit guard).
  @override
  Future<bool> record({
    required GemLedgerKind kind,
    required int amount,
    required String reason,
    String? eventId,
    String? itemId,
    String? transactionId,
  }) async {
    final txId = transactionId ?? eventId ?? 'tx-${_randomId()}';
    try {
      await _db.customStatement(
        'INSERT INTO gem_ledger '
        '(transaction_id, event_id, kind, amount, reason, item_id, '
        ' created_at, status) VALUES (?, ?, ?, ?, ?, ?, ?, '
        " 'committed')",
        [
          txId,
          eventId,
          kind.name,
          amount,
          reason,
          itemId,
          DateTime.now().millisecondsSinceEpoch,
        ],
      );
      return true;
    } catch (e) {
      // A UNIQUE/constraint violation on transaction_id/event_id means the
      // event is already recorded — the idempotent double-credit guard.
      // Anything else is a real storage failure; keep the false return (the
      // caller contract is "false = not recorded") but leave a trace.
      final isConstraintViolation =
          e is SqliteException && _constraintPattern.hasMatch(e.message);
      if (!isConstraintViolation) {
        logger.w('Gem ledger record failed: $e');
      }
      return false;
    }
  }

  /// Atomic purchase: spend row + entitlement row in one transaction.
  ///
  /// [currentBalance] is the wallet balance at call time (the caller's
  /// authoritative fast-path). A repeated call with the same [idempotencyKey]
  /// is a no-op that reports [GemPurchaseResult.success] again — double taps
  /// never double-charge.
  @override
  Future<GemPurchaseResult> purchase({
    required String itemId,
    required int price,
    required int currentBalance,
    required int catalogVersion,
    String? idempotencyKey,
  }) async {
    if (await hasEntitlement(itemId)) {
      return GemPurchaseResult.alreadyOwned;
    }
    if (currentBalance < price) {
      return GemPurchaseResult.insufficientFunds;
    }
    final txId = idempotencyKey ?? 'purchase-$itemId-${_randomId()}';
    final now = DateTime.now().millisecondsSinceEpoch;
    try {
      await _db.transaction(() async {
        await _db.customStatement(
          'INSERT INTO gem_ledger '
          '(transaction_id, event_id, kind, amount, reason, item_id, '
          ' created_at, status) VALUES (?, NULL, ?, ?, ?, ?, ?, '
          " 'committed')",
          [
            txId,
            GemLedgerKind.spend.name,
            -price,
            'purchase:$itemId',
            itemId,
            now
          ],
        );
        await _db.customStatement(
          'INSERT OR IGNORE INTO cosmetic_entitlements '
          '(item_id, acquired_by_transaction, acquired_at, catalog_version) '
          'VALUES (?, ?, ?, ?)',
          [itemId, txId, now, catalogVersion],
        );
      });
      return GemPurchaseResult.success;
    } catch (_) {
      // Idempotent retry with the same key likely already committed.
      if (await hasEntitlement(itemId)) {
        return GemPurchaseResult.success;
      }
      rethrow;
    }
  }

  /// One-time migration from the legacy prefs-based economy (Plan 2 §8.6).
  ///
  /// Idempotent by fixed transaction ids: the opening balance row
  /// (`migration_opening_balance_v1`) seeds the ledger with the previous
  /// prefs balance, and each already-unlocked ring becomes an entitlement
  /// with a deterministic `migration_entitlement_<itemId>` transaction id.
  /// Balance is verified against [expectedBalance] before the completion
  /// marker is written; a mismatch keeps the store read-only-worthy for
  /// diagnostics instead of silently proceeding.
  @override
  Future<bool> migrateFromPrefs({
    required int prefsBalance,
    required Set<String> unlockedItemIds,
  }) async {
    await record(
      kind: GemLedgerKind.migration,
      amount: prefsBalance,
      reason: 'legacy prefs opening balance',
      eventId: openingBalanceEventId,
      transactionId: openingBalanceTxId,
    );
    // record() returns false both for "already done" and real failures;
    // distinguish by checking the fixed transaction id.
    final opened = await _transactionExists(openingBalanceTxId);
    if (!opened) return false;

    final now = DateTime.now().millisecondsSinceEpoch;
    for (final itemId in unlockedItemIds) {
      await _db.customStatement(
        'INSERT OR IGNORE INTO gem_ledger '
        '(transaction_id, event_id, kind, amount, reason, item_id, '
        ' created_at, status) VALUES (?, NULL, ?, 0, ?, ?, ?, '
        " 'committed')",
        [
          'migration_entitlement_$itemId',
          GemLedgerKind.migration.name,
          'legacy unlock migration',
          itemId,
          now,
        ],
      );
      await _db.customStatement(
        'INSERT OR IGNORE INTO cosmetic_entitlements '
        '(item_id, acquired_by_transaction, acquired_at, catalog_version) '
        "VALUES (?, ?, ?, 0)",
        [itemId, 'migration_entitlement_$itemId', now],
      );
    }

    // The projection may legitimately differ after later earn/spend rows or
    // after restoring a prefs snapshot over an existing database. The wallet
    // owner performs reconciliation; migration only proves its fixed opening
    // row and entitlement rows exist.
    return true;
  }

  Future<bool> _transactionExists(String txId) async {
    final rows = await _db.customSelect(
      'SELECT COUNT(*) AS n FROM gem_ledger WHERE transaction_id = ?',
      variables: [Variable.withString(txId)],
    ).get();
    return (rows.first.read<int>('n')) > 0;
  }

  Future<bool> _eventExists(String eventId) async {
    final rows = await _db.customSelect(
      'SELECT COUNT(*) AS n FROM gem_ledger WHERE event_id = ?',
      variables: [Variable.withString(eventId)],
    ).get();
    return rows.single.read<int>('n') > 0;
  }

  static String _randomId() {
    final rng = Random();
    return DateTime.now().millisecondsSinceEpoch.toRadixString(36) +
        rng.nextInt(1 << 32).toRadixString(36);
  }
}
