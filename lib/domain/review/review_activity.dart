/// Granularity of review-activity aggregation buckets.
enum ActivityGranularity { day, week, month }

/// One aggregated activity bucket: [reviewedCount] reviews in [bucket]
/// (a day/week/month key produced by the review history DAO).
class ActivityBucketRow {
  const ActivityBucketRow({required this.bucket, required this.reviewedCount});
  final String bucket;
  final int reviewedCount;
}
