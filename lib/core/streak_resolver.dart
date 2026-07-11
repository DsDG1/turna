/// Result of applying a practice event to the current streak.
class StreakResolution {
  final int newStreak;
  final bool broken;

  const StreakResolution({
    required this.newStreak,
    required this.broken,
  });
}

/// Pure streak update for a practice/XP day (no I/O).
///
/// - [oldDate] null → start or keep streak at least 1
/// - same calendar day (gap ≤ 0) → unchanged
/// - consecutive day (gap == 1) → increment
/// - gap ≥ 2 → reset to 1 and mark broken
StreakResolution resolveStreakOnPractice({
  required int oldStreak,
  required DateTime? oldDate,
  required DateTime today,
}) {
  if (oldDate == null) {
    return StreakResolution(
      newStreak: oldStreak == 0 ? 1 : oldStreak,
      broken: false,
    );
  }

  final last = DateTime(oldDate.year, oldDate.month, oldDate.day);
  final day = DateTime(today.year, today.month, today.day);
  final gap = day.difference(last).inDays;

  if (gap <= 0) {
    return StreakResolution(newStreak: oldStreak, broken: false);
  }

  if (gap == 1) {
    return StreakResolution(newStreak: oldStreak + 1, broken: false);
  }

  return const StreakResolution(newStreak: 1, broken: true);
}
