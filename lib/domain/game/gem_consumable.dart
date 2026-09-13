/// Outcome of an atomic gem purchase (Plan 2 §8.4).
enum GemConsumablePurchaseResult {
  success,
  insufficientFunds,
  monthlyLimitReached,
}
