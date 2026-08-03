/// Achievement unlock configuration, centralized so XP/streak thresholds and
/// gem rewards are adjustable and testable in one place instead of scattered
/// across [GameProvider].
///
/// Each entry pairs an unlock threshold with the achievement id stored in
/// [LocalStateKeys.achievements] and the gem bonus awarded on first unlock.
class AchievementConfig {
  const AchievementConfig._();

  /// XP milestones: unlock when cumulative score crosses each threshold.
  static const List<AchievementMilestone> xp = [
    AchievementMilestone(id: 'xp_1000', threshold: 1000, gemReward: 25),
    AchievementMilestone(id: 'xp_10000', threshold: 10000, gemReward: 100),
    AchievementMilestone(id: 'xp_50000', threshold: 50000, gemReward: 250),
  ];

  /// Streak milestones: unlock when the current streak crosses each threshold.
  static const List<AchievementMilestone> streak = [
    AchievementMilestone(id: 'streak_3', threshold: 3, gemReward: 15),
    AchievementMilestone(id: 'streak_7', threshold: 7, gemReward: 50),
    AchievementMilestone(id: 'streak_30', threshold: 30, gemReward: 200),
    AchievementMilestone(id: 'streak_100', threshold: 100, gemReward: 500),
    AchievementMilestone(id: 'streak_365', threshold: 365, gemReward: 1000),
  ];

  /// Total gem bonus for unlocking every milestone in [list] whose threshold
  /// [value] meets or exceeds, recording newly-unlocked ids in [achievements].
  /// Returns 0 when nothing new unlocks.
  static int gemsForThreshold(
    List<AchievementMilestone> list,
    int value,
    Set<String> achievements,
  ) {
    var gemsReward = 0;
    for (final milestone in list) {
      if (value >= milestone.threshold && achievements.add(milestone.id)) {
        gemsReward += milestone.gemReward;
      }
    }
    return gemsReward;
  }
}

/// A single achievement unlock point.
class AchievementMilestone {
  final String id;
  final int threshold;
  final int gemReward;

  const AchievementMilestone({
    required this.id,
    required this.threshold,
    required this.gemReward,
  });
}
