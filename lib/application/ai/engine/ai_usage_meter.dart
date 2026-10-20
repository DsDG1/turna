// Package imports:
// (none: this is a plain process singleton, mirroring `PerformanceTrace`.)

// Flutter imports:
import 'package:flutter/foundation.dart';

/// Immutable view of the session's AI traffic.
///
/// Token counts come straight from the endpoint's `usage` block, which the
/// engine has always extracted but never read. Costs are deliberately not
/// computed here: pricing tables go stale and the provider presets explicitly
/// exclude them (see `ai_provider_preset.dart`), so this snapshot reports raw
/// token counts only and leaves any rate to the caller.
class AiUsageSnapshot {
  const AiUsageSnapshot({
    this.requests = 0,
    this.cacheHits = 0,
    this.failures = 0,
    this.cancellations = 0,
    this.promptTokens = 0,
    this.completionTokens = 0,
    this.usageReports = 0,
  });

  /// Successful engine calls that reached a result (cache hits included).
  final int requests;

  /// How many of [requests] were served locally.
  final int cacheHits;

  /// Calls that ended in an exception (including [AiCancelled]).
  final int failures;

  /// Calls the user aborted.
  final int cancellations;

  final int promptTokens;
  final int completionTokens;

  /// How many calls actually reported a `usage` block. Endpoints that omit it
  /// (some OpenAI-compatible gateways) leave the token counters at zero, so a
  /// zero must be read as "not reported", not "no tokens spent".
  final int usageReports;

  int get totalTokens => promptTokens + completionTokens;

  /// Calls that went to the network (cache hits excluded).
  int get networkRequests => requests - cacheHits;

  @override
  String toString() =>
      'AiUsageSnapshot(requests: $requests, cacheHits: $cacheHits, '
      'failures: $failures, cancellations: $cancellations, '
      'promptTokens: $promptTokens, completionTokens: $completionTokens)';
}

/// Process-local accumulator for AI token usage.
///
/// Intentionally memory-only, matching [AiCache]: a restart clears the session
/// counters rather than pretending to keep a durable billing history.
///
/// Deliberately a plain singleton (like `PerformanceTrace`) rather than a
/// GetIt registration: [AiEngine]'s constructor keeps its two required
/// parameters, so existing call sites and generated injectable code are
/// untouched, and there is exactly one accumulator regardless of how many
/// engines tests build.
class AiUsageMeter extends ChangeNotifier {
  AiUsageMeter();

  /// The process-wide accumulator every [AiEngine] writes to by default.
  static final AiUsageMeter instance = AiUsageMeter();

  int _requests = 0;
  int _cacheHits = 0;
  int _failures = 0;
  int _cancellations = 0;
  int _promptTokens = 0;
  int _completionTokens = 0;
  int _usageReports = 0;

  /// Record a completed call. [usage] is whatever the endpoint reported; a
  /// missing block still counts as a request, just not a usage report.
  void recordSuccess({Map<String, int>? usage, bool cacheHit = false}) {
    _requests++;
    if (cacheHit) _cacheHits++;
    if (usage == null) {
      notifyListeners();
      return;
    }
    final prompt = usage['prompt_tokens'] ?? usage['input_tokens'] ?? 0;
    final completion =
        usage['completion_tokens'] ?? usage['output_tokens'] ?? 0;
    if (prompt == 0 && completion == 0) {
      notifyListeners();
      return;
    }
    _promptTokens += prompt;
    _completionTokens += completion;
    _usageReports++;
    notifyListeners();
  }

  void recordFailure({required bool cancelled}) {
    _failures++;
    if (cancelled) _cancellations++;
    notifyListeners();
  }

  AiUsageSnapshot snapshot() => AiUsageSnapshot(
        requests: _requests,
        cacheHits: _cacheHits,
        failures: _failures,
        cancellations: _cancellations,
        promptTokens: _promptTokens,
        completionTokens: _completionTokens,
        usageReports: _usageReports,
      );

  void reset() {
    _requests = 0;
    _cacheHits = 0;
    _failures = 0;
    _cancellations = 0;
    _promptTokens = 0;
    _completionTokens = 0;
    _usageReports = 0;
    notifyListeners();
  }
}
