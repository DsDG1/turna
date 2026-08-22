import 'package:turna/domain/achievements/achievement_state.dart';

/// One newly unlocked tier produced by the evaluator. Persisting the state,
/// granting rewards, and surfacing feedback are service-layer concerns — the
/// evaluator only reports what changed.
class AchievementUnlockResult {
  final String seriesId;
  final String tierId;
  final int target;
  final int gemReward;
  final String? cosmeticRewardId;
  final DateTime unlockedAt;
  final AchievementUnlockOrigin origin;

  const AchievementUnlockResult({
    required this.seriesId,
    required this.tierId,
    required this.target,
    required this.gemReward,
    required this.cosmeticRewardId,
    required this.unlockedAt,
    required this.origin,
  });

  bool get hasCosmeticReward =>
      cosmeticRewardId != null && cosmeticRewardId!.isNotEmpty;
}
