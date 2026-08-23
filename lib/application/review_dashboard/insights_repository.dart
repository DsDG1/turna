import 'package:turna/application/review_dashboard/review_data_revision.dart';
import 'package:turna/application/diagnostics/performance_trace.dart';
import 'package:turna/application/review_progress_provider.dart';

class InsightsQuery {
  const InsightsQuery({
    required this.range,
    required this.source,
    required this.type,
    this.maturity = const {},
    this.due = DueFilter.any,
  });

  final EventRange range;
  final ReviewSource source;
  final ProgressTypeFilter type;
  final Set<MaturityBucket> maturity;
  final DueFilter due;

  String cacheKey(int revision) =>
      'insights:${range.name}:${source.id}:${type.name}:'
      '${maturity.map((e) => e.name).join(',')}:${due.name}:$revision';
}

/// Revision-keyed insights cache with a generation guard. A slow old range
/// may still complete for its caller, but can never overwrite [current].
class InsightsRepository {
  InsightsRepository(ReviewProgressProvider progress, this._revision)
      : _loader = progress.snapshot;

  InsightsRepository.forTesting(this._loader, this._revision);

  final Future<ReviewProgressSnapshot> Function(ReviewProgressFilter) _loader;
  final ReviewDataRevision _revision;
  final Map<String, ReviewProgressSnapshot> _cache = {};
  int _generation = 0;
  ReviewProgressSnapshot? _current;

  ReviewProgressSnapshot? get current => _current;
  int get generation => _generation;

  Future<ReviewProgressSnapshot> load(InsightsQuery query) async {
    final trace = Stopwatch()..start();
    final generation = ++_generation;
    final key = query.cacheKey(_revision.value);
    final cached = _cache[key];
    if (cached != null) {
      if (generation == _generation) _current = cached;
      trace.stop();
      PerformanceTrace.instance.record(
        feature: 'insights',
        operation: 'load',
        duration: trace.elapsed,
        resultSize: cached.activity.length +
            cached.aggregate.retentionByInterval.length,
        cacheStatus: TraceCacheStatus.hit,
      );
      return cached;
    }
    final snapshot = await _loader(
      ReviewProgressFilter(
        source: query.source,
        type: query.type,
        maturity: query.maturity,
        due: query.due,
        eventRange: query.range,
      ),
    );
    _cache[key] = snapshot;
    if (generation == _generation) _current = snapshot;
    trace.stop();
    PerformanceTrace.instance.record(
      feature: 'insights',
      operation: 'load',
      duration: trace.elapsed,
      resultSize: snapshot.activity.length +
          snapshot.aggregate.retentionByInterval.length,
      cacheStatus: TraceCacheStatus.miss,
    );
    return snapshot;
  }

  void invalidate() {
    _cache.clear();
    _generation++;
  }
}
