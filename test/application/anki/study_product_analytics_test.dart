import 'package:flutter_test/flutter_test.dart';
import 'package:turna/application/study_session/study_product_analytics.dart';
import 'package:turna/domain/anki/canonical_card_key.dart';
import 'package:turna/domain/anki/study_models.dart';
import 'package:turna/domain/review/recall_outcome.dart';

void main() {
  const key = CanonicalCardKey(
    backend: AnkiBackendKind.official,
    profileId: 'p',
    sourceId: 'src',
    cardId: 1,
  );

  StudyEventReceipt receipt({
    required String eventId,
    RecallOutcome outcome = RecallOutcome.remembered,
  }) {
    return StudyEventReceipt(
      eventId: eventId,
      idempotencyKey: 'idemp-$eventId',
      cardKey: key,
      ledgerOwner: StudyLedgerOwner.officialAnki,
      outcome: outcome,
      reviewedAt: DateTime.now(),
    );
  }

  group('StudyProductAnalytics', () {
    setUp(StudyProductAnalytics.instance.reset);
    tearDown(StudyProductAnalytics.instance.reset);

    test('recordEvent keys mistakes and stats on one id', () {
      final analytics = StudyProductAnalytics.instance;
      analytics.recordEvent(eventId: 'rev-1', outcome: RecallOutcome.forgotten);
      analytics.recordEvent(eventId: 'rev-1', outcome: RecallOutcome.forgotten);
      expect(analytics.snapshot().uniqueEventCount, 1);
      expect(analytics.snapshot().forgottenCount, 1);
    });

    test('one event id is not counted twice', () {
      final analytics = StudyProductAnalytics.instance;
      final first = receipt(eventId: 'evt-1');
      analytics.record(first);
      analytics.record(
        receipt(eventId: 'evt-1', outcome: RecallOutcome.forgotten),
      );
      analytics.record(
        receipt(eventId: 'evt-2', outcome: RecallOutcome.forgotten),
      );
      final snap = analytics.snapshot();
      expect(snap.uniqueEventCount, 2);
      expect(snap.rememberedCount + snap.forgottenCount, 2);
      expect(snap.freshness, StudyAnalyticsFreshness.ready);
    });

    test('undo forgets the product event', () {
      final analytics = StudyProductAnalytics();
      analytics.record(receipt(eventId: 'evt-1'));
      analytics.forget('evt-1');
      expect(analytics.snapshot().uniqueEventCount, 0);
    });

    test('loading / unavailable / error / stale stay distinct from 0 ready', () {
      final analytics = StudyProductAnalytics();
      analytics.record(receipt(eventId: 'evt-1'));

      analytics.freshness = StudyAnalyticsFreshness.loading;
      expect(analytics.snapshot().freshness, StudyAnalyticsFreshness.loading);
      expect(analytics.snapshot().uniqueEventCount, 0);

      analytics.freshness = StudyAnalyticsFreshness.unavailable;
      expect(analytics.snapshot().freshness, StudyAnalyticsFreshness.unavailable);
      expect(analytics.snapshot().uniqueEventCount, 0);

      analytics.freshness = StudyAnalyticsFreshness.error;
      expect(analytics.snapshot().freshness, StudyAnalyticsFreshness.error);

      analytics.freshness = StudyAnalyticsFreshness.stale;
      expect(analytics.snapshot().freshness, StudyAnalyticsFreshness.stale);

      analytics.freshness = StudyAnalyticsFreshness.ready;
      expect(analytics.snapshot().uniqueEventCount, 1);
      expect(analytics.snapshot().freshness, StudyAnalyticsFreshness.ready);
    });
  });
}
