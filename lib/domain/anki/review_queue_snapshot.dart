import 'package:turna/domain/anki/study_models.dart';

enum ReviewQueueFreshness {
  ready,
  loading,
  unavailable,
  error,
  stale,
}

class ReviewQueueSnapshot {
  const ReviewQueueSnapshot({
    required this.items,
    required this.introducedDue,
    required this.unintroducedNew,
    required this.freshness,
    this.refreshedAt,
    this.error,
  });

  final List<StudyItem> items;
  final int introducedDue;
  final int unintroducedNew;
  final ReviewQueueFreshness freshness;
  final DateTime? refreshedAt;
  final Object? error;

  bool get isUnavailable => freshness == ReviewQueueFreshness.unavailable;
  bool get isLoading => freshness == ReviewQueueFreshness.loading;

  static const loading = ReviewQueueSnapshot(
    items: [],
    introducedDue: 0,
    unintroducedNew: 0,
    freshness: ReviewQueueFreshness.loading,
  );

  static const unavailable = ReviewQueueSnapshot(
    items: [],
    introducedDue: 0,
    unintroducedNew: 0,
    freshness: ReviewQueueFreshness.unavailable,
  );
}
