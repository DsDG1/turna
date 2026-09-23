// Project imports:
import 'package:turna/domain/game/gem_consumable.dart';

/// Transactional gem ledger + cosmetic entitlements (Plan 2 §8.4).
///
/// Append-only facts about the gem economy; writes are idempotent
/// (`transaction_id` primary key, `event_id` unique for game events), so
/// retries and double-taps can never double-charge.
///
/// Concrete: `GemLedgerDao` in `lib/data`.
abstract class IGemLedger {
  /// Spendable gem balance — sum of committed rows, excluding streak-voucher
  /// fact rows (voucher amounts project inventory, not gems).
  Future<int> projectedBalance();

  /// Whether [itemId] is already entitled (owned).
  Future<bool> hasEntitlement(String itemId);

  /// All entitled cosmetic item ids.
  Future<Set<String>> entitledItemIds();

  /// Current streak-voucher inventory (signed sum of voucher fact rows).
  Future<int> streakVoucherBalance();

  /// Voucher purchases inside the local calendar month of [month].
  Future<int> streakVoucherPurchasesInMonth(DateTime month);

  /// Atomic consumable purchase: debits [price] gems and credits one voucher
  /// in a single transaction. Idempotent via [idempotencyKey].
  Future<GemConsumablePurchaseResult> purchaseStreakVoucher({
    required int price,
    required int currentBalance,
    required int monthlyLimit,
    String? idempotencyKey,
    DateTime? purchasedAt,
  });

  /// Grant one streak voucher (idempotent via [eventId]).
  Future<bool> grantStreakVoucher({
    required String eventId,
    String reason = 'voucher:grant',
  });

  /// Consume one streak voucher for [localDay] (idempotent, one per day).
  Future<bool> consumeStreakVoucher({required String localDay});

  /// Append one ledger row. Returns false when the write was skipped because
  /// [transactionId]/[eventId] already exists or the insert failed.
  Future<bool> record({
    required GemLedgerKind kind,
    required int amount,
    required String reason,
    String? eventId,
    String? itemId,
    String? transactionId,
  });

  /// Atomic cosmetic purchase: checks entitlement + balance, then writes the
  /// spend row and the entitlement in one transaction.
  Future<GemPurchaseResult> purchase({
    required String itemId,
    required int price,
    required int currentBalance,
    required int catalogVersion,
    String? idempotencyKey,
  });

  /// One-time migration of the legacy prefs-based balance + unlock set into
  /// the ledger. Idempotent via the fixed opening-balance transaction id.
  Future<bool> migrateFromPrefs({
    required int prefsBalance,
    required Set<String> unlockedItemIds,
  });
}
