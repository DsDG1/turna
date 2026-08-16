enum AiRequestOutcome { success, failed, cancelled, budgetBlocked }

enum AiDataSensitivity { public, learnerSensitive }

class AiRequestContext {
  const AiRequestContext({
    required this.feature,
    this.sessionId,
    this.promptVersion = '',
    this.maxOutputTokens = 800,
    this.sensitivity = AiDataSensitivity.public,
  });

  final String feature;
  final String? sessionId;
  final String promptVersion;
  final int maxOutputTokens;
  final AiDataSensitivity sensitivity;
}

class AiRequestMetric {
  const AiRequestMetric({
    required this.requestId,
    required this.feature,
    required this.startedAt,
    required this.latencyMs,
    required this.outcome,
    this.sessionId,
    this.promptVersion = '',
    this.model = '',
    this.inputTokens = 0,
    this.outputTokens = 0,
    this.cacheHit = false,
    this.estimatedCost = 0,
  });

  final String requestId;
  final String feature;
  final String? sessionId;
  final String promptVersion;
  final String model;
  final DateTime startedAt;
  final int latencyMs;
  final int inputTokens;
  final int outputTokens;
  final bool cacheHit;
  final AiRequestOutcome outcome;
  final double estimatedCost;

  int get totalTokens => inputTokens + outputTokens;
}

class AiUsageSummary {
  const AiUsageSummary({
    this.requests = 0,
    this.inputTokens = 0,
    this.outputTokens = 0,
    this.cacheHits = 0,
    this.failures = 0,
    this.estimatedCost = 0,
  });

  final int requests;
  final int inputTokens;
  final int outputTokens;
  final int cacheHits;
  final int failures;
  final double estimatedCost;

  int get totalTokens => inputTokens + outputTokens;
  double get cacheHitRate => requests == 0 ? 0 : cacheHits / requests;
  double get failureRate => requests == 0 ? 0 : failures / requests;
}
