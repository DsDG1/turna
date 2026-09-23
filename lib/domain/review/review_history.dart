// Project imports:
import 'package:turna/domain/course/language_codes.dart';
import 'package:turna/domain/course/srs_word.dart';

/// Filter for review-history reads — every field optional, combined AND.
class ReviewHistoryFilter {
  const ReviewHistoryFilter({
    this.sourceKind,
    this.sourceKinds,
    this.sourceId,
    this.queue,
    this.type,
    this.languageCode,
  });
  final SrsSourceKind? sourceKind;

  /// Multi-kind alternative to [sourceKind] (the "course" source rolls up
  /// `course` + `builtin` rows). Wins over [sourceKind] when both are set.
  final Set<SrsSourceKind>? sourceKinds;
  final String? sourceId;
  final String? queue;
  final String? type;
  final String? languageCode;
}

/// One interval bucket's recall tally (retention curve rows).
class RetentionBucketRow {
  const RetentionBucketRow({
    required this.intervalBucketDays,
    required this.recalled,
    required this.total,
  });
  final int intervalBucketDays;
  final int recalled;
  final int total;
}

/// One aggregated day of review activity (dashboard 7-day chart).
class DailyActivityRow {
  final DateTime localDay;
  final int reviewedCount;

  const DailyActivityRow({required this.localDay, required this.reviewedCount});
}

/// Plain data class for one review event (decoupled from the Drift row).
class ReviewEventRecord {
  final int? id;
  final String cardId;
  final String queue;
  final DateTime reviewedAt;
  final int quality;
  final int prevIntervalDays;
  final int nextIntervalDays;
  final double prevEase;
  final double nextEase;
  final int reps;
  final int lapses;
  final SrsItemType type;
  final String? sourceKey;
  final SrsSourceKind sourceKind;
  final String sourceId;
  final String? ownerId;
  final String languageCode;

  const ReviewEventRecord({
    this.id,
    required this.cardId,
    required this.queue,
    required this.reviewedAt,
    required this.quality,
    required this.prevIntervalDays,
    required this.nextIntervalDays,
    required this.prevEase,
    required this.nextEase,
    required this.reps,
    required this.lapses,
    this.type = SrsItemType.word,
    this.sourceKey,
    this.sourceKind = SrsSourceKind.course,
    this.sourceId = 'course',
    this.ownerId,
    this.languageCode = LanguageCodes.turkish,
  });

  /// A recall is successful at SM-2 quality >= 3.
  bool get recalled => quality >= 3;
}
