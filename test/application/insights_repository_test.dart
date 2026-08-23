import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:turna/application/memory_curve_provider.dart';
import 'package:turna/application/review_dashboard/insights_repository.dart';
import 'package:turna/application/review_dashboard/review_data_revision.dart';
import 'package:turna/application/review_progress_provider.dart';

void main() {
  const aggregate = MemoryCurveSnapshot(
    currentRetention: 1,
    trackedCards: 0,
    totalCards: 0,
    forecast: Forecast(dueToday: 0, due7Days: 0, due30Days: 0),
    maturity: MaturityBreakdown(
      newCards: 0,
      young: 0,
      mature: 0,
      leech: 0,
    ),
    retentionByInterval: [],
    totalReviews: 0,
  );

  ReviewProgressSnapshot snapshot(EventRange range) => ReviewProgressSnapshot(
        aggregate: aggregate,
        bySource: const [],
        filter: ReviewProgressFilter(eventRange: range),
        availableSources: const [ReviewSource.all],
      );

  InsightsQuery query(EventRange range) => InsightsQuery(
        range: range,
        source: ReviewSource.all,
        type: ProgressTypeFilter.all,
      );

  test('late old range cannot overwrite the current snapshot', () async {
    final pending = <EventRange, Completer<ReviewProgressSnapshot>>{};
    final revision = ReviewDataRevision();
    final repository = InsightsRepository.forTesting((filter) {
      return (pending[filter.eventRange] ??=
              Completer<ReviewProgressSnapshot>())
          .future;
    }, revision);

    final oldLoad = repository.load(query(EventRange.d365));
    final newLoad = repository.load(query(EventRange.d7));
    pending[EventRange.d7]!.complete(snapshot(EventRange.d7));
    await newLoad;
    pending[EventRange.d365]!.complete(snapshot(EventRange.d365));
    await oldLoad;

    expect(repository.current?.filter.eventRange, EventRange.d7);
  });

  test('cache key includes review data revision', () async {
    var calls = 0;
    final revision = ReviewDataRevision();
    final repository = InsightsRepository.forTesting((filter) async {
      calls++;
      return snapshot(filter.eventRange);
    }, revision);

    await repository.load(query(EventRange.d30));
    await repository.load(query(EventRange.d30));
    expect(calls, 1);
    revision.bump();
    await repository.load(query(EventRange.d30));
    expect(calls, 2);
  });
}
