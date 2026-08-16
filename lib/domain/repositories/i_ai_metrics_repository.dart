import 'package:turna/domain/ai_companion/ai_request_metric.dart';

abstract interface class IAiMetricsRepository {
  Future<void> recordMetric(AiRequestMetric metric);

  Future<AiUsageSummary> usageSummary({
    required DateTime since,
    String? feature,
  });

  Future<void> clearMetrics();
}
