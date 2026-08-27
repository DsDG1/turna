import 'package:turna/domain/anki/canonical_card_key.dart';
import 'package:turna/domain/anki/study_models.dart';
import 'package:turna/domain/review/recall_outcome.dart';

enum StudyAnalyticsFreshness { ready, loading, unavailable, error, stale }

class StudyAnalyticsSnapshot {
  const StudyAnalyticsSnapshot({
    required this.uniqueEventCount,
    required this.rememberedCount,
    required this.forgottenCount,
    required this.freshness,
  });

  final int uniqueEventCount;
  final int rememberedCount;
  final int forgottenCount;
  final StudyAnalyticsFreshness freshness;

  static const loading = StudyAnalyticsSnapshot(
    uniqueEventCount: 0,
    rememberedCount: 0,
    forgottenCount: 0,
    freshness: StudyAnalyticsFreshness.loading,
  );

  static const unavailable = StudyAnalyticsSnapshot(
    uniqueEventCount: 0,
    rememberedCount: 0,
    forgottenCount: 0,
    freshness: StudyAnalyticsFreshness.unavailable,
  );
}

/// Product events keyed by [StudyEventReceipt.eventId] so Official revlog
/// and Turna history are not double-counted.
class StudyProductAnalytics {
  StudyProductAnalytics();

  static final StudyProductAnalytics instance = StudyProductAnalytics();

  final Map<String, StudyEventReceipt> _byEventId = {};
  StudyAnalyticsFreshness freshness = StudyAnalyticsFreshness.ready;

  static const unknownCardKey = CanonicalCardKey(
    backend: AnkiBackendKind.localCanonical,
    profileId: 'profile-default-01',
    sourceId: 'unknown',
    cardId: 0,
  );

  void record(StudyEventReceipt receipt) {
    _byEventId[receipt.eventId] = receipt;
  }

  void recordEvent({
    required String eventId,
    required RecallOutcome outcome,
    CanonicalCardKey? cardKey,
    StudyLedgerOwner owner = StudyLedgerOwner.none,
  }) {
    record(
      StudyEventReceipt(
        eventId: eventId,
        idempotencyKey: eventId,
        cardKey: cardKey ?? unknownCardKey,
        ledgerOwner: owner,
        outcome: outcome,
        reviewedAt: DateTime.now(),
      ),
    );
  }

  void forget(String eventId) {
    _byEventId.remove(eventId);
  }

  void reset() {
    _byEventId.clear();
    freshness = StudyAnalyticsFreshness.ready;
  }

  int get uniqueEventCount => _byEventId.length;

  StudyAnalyticsSnapshot snapshot() {
    if (freshness == StudyAnalyticsFreshness.unavailable ||
        freshness == StudyAnalyticsFreshness.loading ||
        freshness == StudyAnalyticsFreshness.error ||
        freshness == StudyAnalyticsFreshness.stale) {
      return StudyAnalyticsSnapshot(
        uniqueEventCount: 0,
        rememberedCount: 0,
        forgottenCount: 0,
        freshness: freshness,
      );
    }
    var remembered = 0;
    var forgotten = 0;
    for (final receipt in _byEventId.values) {
      if (receipt.outcome == RecallOutcome.remembered) {
        remembered++;
      } else {
        forgotten++;
      }
    }
    return StudyAnalyticsSnapshot(
      uniqueEventCount: _byEventId.length,
      rememberedCount: remembered,
      forgottenCount: forgotten,
      freshness: StudyAnalyticsFreshness.ready,
    );
  }
}
