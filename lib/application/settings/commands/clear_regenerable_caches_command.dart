// Project imports:
import 'package:turna/application/diagnostics/cache_diagnostics_registry.dart';

/// Outcome of one owner's cache clear (e.g. `ai.responseCache`).
class CacheClearOutcome {
  const CacheClearOutcome({
    required this.owner,
    required this.success,
    this.clearedEntries = 0,
    this.error,
  });

  final String owner;
  final bool success;
  final int clearedEntries;
  final Object? error;
}

/// Result of the full regenerable-cache sweep. Standalone structured result
/// (not a [SettingsOperationResult] subclass — that hierarchy is sealed to
/// its library): per-owner outcomes carry richer information than a single
/// success/failure.
class ClearCachesResult {
  const ClearCachesResult({required this.outcomes});

  /// Per-owner outcomes in execution order — one failing owner never
  /// aborts the others and never lets the whole sweep report success.
  final List<CacheClearOutcome> outcomes;

  List<CacheClearOutcome> get failures =>
      outcomes.where((outcome) => !outcome.success).toList();

  bool get allSucceeded => failures.isEmpty;
}

/// Single coordinator for clearing every regenerable cache. Before this
/// existed the diagnostics page called each cache clear separately, dropped
/// the registry's per-owner results, and an exception in any adapter aborted
/// the remaining ones while the UI just showed a generic success. This
/// command runs each owner isolated, keeps every result, prevents concurrent
/// sweeps, and reports a structured summary.
class ClearRegenerableCachesCommand {
  ClearRegenerableCachesCommand();

  bool _running = false;

  bool get isRunning => _running;

  Future<ClearCachesResult> execute() async {
    if (_running) {
      return const ClearCachesResult(outcomes: [
        CacheClearOutcome(
          owner: 'coordinator',
          success: false,
          error: 'already running',
        ),
      ]);
    }
    _running = true;
    try {
      final outcomes = <CacheClearOutcome>[];

      // Owners: registry adapters (AI cache, dashboard cache, Flutter
      // image cache) — each isolated.
      final registry = CacheDiagnosticsRegistry.production();
      for (final adapter in registry.adapters) {
        try {
          final result = await adapter.clearRegenerable();
          outcomes.add(CacheClearOutcome(
            owner: adapter.owner,
            success: true,
            clearedEntries: result.clearedEntries,
          ));
        } on Object catch (error) {
          outcomes.add(CacheClearOutcome(
            owner: adapter.owner,
            success: false,
            error: error,
          ));
        }
      }

      return ClearCachesResult(outcomes: outcomes);
    } finally {
      _running = false;
    }
  }
}
