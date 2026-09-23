/// Outcome of an atomic gem purchase (Plan 2 §8.4).
enum GemConsumablePurchaseResult {
  success,
  insufficientFunds,
  monthlyLimitReached,
}

/// Outcome of an atomic cosmetic-item purchase (Plan 2 §8.4).
enum GemPurchaseResult {
  /// Spend + entitlement committed.
  success,

  /// Entitlement already exists — nothing charged, nothing written.
  alreadyOwned,

  /// Balance below price.
  insufficientFunds,
}

/// Ledger row kinds (Plan 2 §8.4): append-only facts about the gem economy.
enum GemLedgerKind { earn, spend, refund, migration, adjustment }
