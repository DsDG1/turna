import 'package:turna/domain/repositories/i_ai_metrics_repository.dart';

class AiBudgetExceeded implements Exception {
  const AiBudgetExceeded(this.message);

  final String message;

  @override
  String toString() => message;
}

/// Local, provider-independent request budget. It guards runaway usage even
/// when the configured endpoint does not report monetary pricing.
class AiBudgetManager {
  const AiBudgetManager({
    required IAiMetricsRepository repository,
    this.dailySoftTokenLimit = 50000,
    this.dailyHardTokenLimit = 100000,
  }) : _repository = repository;

  final IAiMetricsRepository _repository;
  final int dailySoftTokenLimit;
  final int dailyHardTokenLimit;

  Future<void> enforce({required int requestedOutputTokens}) async {
    final now = DateTime.now();
    final summary = await _repository.usageSummary(
      since: DateTime(now.year, now.month, now.day),
    );
    if (summary.totalTokens + requestedOutputTokens > dailyHardTokenLimit) {
      throw const AiBudgetExceeded('已达到今日 AI 用量上限，请明天再试或调整预算。');
    }
  }

  Future<bool> isSoftLimitReached() async {
    final now = DateTime.now();
    final summary = await _repository.usageSummary(
      since: DateTime(now.year, now.month, now.day),
    );
    return summary.totalTokens >= dailySoftTokenLimit;
  }
}
