// Pure relearn-ladder helpers (ADR 0029). Binary scoring only.

/// Same-day fail relearn delays. [failStreak] is 1-based count of fails today
/// *including* the fail just graded.
///
/// | streak | delay |
/// | 1 | 10 min (30 min if [mature]) |
/// | 2 | 30 min |
/// | 3 | 2 hours |
/// | ≥4 | next calendar day (returns null → caller sets tomorrow) |
Duration? relearnDelayForFailStreak(
  int failStreak, {
  bool mature = false,
}) {
  if (failStreak <= 0) return const Duration(minutes: 10);
  if (failStreak == 1) {
    return Duration(minutes: mature ? 30 : 10);
  }
  if (failStreak == 2) return const Duration(minutes: 30);
  if (failStreak == 3) return const Duration(hours: 2);
  return null; // push to next day
}

/// Stability (days) at or above this counts as mature for first-fail delay.
const double matureStabilityDays = 21.0;

bool isMatureStability(double? stability, int intervalDays) {
  if (stability != null && stability >= matureStabilityDays) return true;
  return intervalDays >= matureStabilityDays.round();
}

bool isSameCalendarDay(DateTime a, DateTime b) =>
    a.year == b.year && a.month == b.month && a.day == b.day;

/// Local midnight of [day] + 1 day.
DateTime nextLocalMidnight(DateTime nowLocal) {
  return DateTime(nowLocal.year, nowLocal.month, nowLocal.day)
      .add(const Duration(days: 1));
}

/// Human preview label for fail streak *before* applying the fail (0 = first).
String relearnPreviewLabel(int failsTodaySoFar, {bool mature = false}) {
  final streak = failsTodaySoFar + 1;
  final d = relearnDelayForFailStreak(streak, mature: mature);
  if (d == null) return '明天';
  if (d.inHours >= 1) return '约 ${d.inHours} 小时';
  return '约 ${d.inMinutes} 分钟';
}
