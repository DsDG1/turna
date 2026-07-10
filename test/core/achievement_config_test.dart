// Unit tests for AchievementConfig: threshold-driven gem unlocks, idempotency,
// and that the milestone tables match the historical GameProvider ladder.

import 'package:flutter_test/flutter_test.dart';
import 'package:varnamala/core/achievement_config.dart';

void main() {
  group('xp milestones', () {
    test('match the historical XP unlock ladder', () {
      expect(AchievementConfig.xp.map((m) => m.id).toList(),
          ['xp_1000', 'xp_10000', 'xp_50000']);
      expect(AchievementConfig.xp.map((m) => m.threshold).toList(),
          [1000, 10000, 50000]);
      expect(AchievementConfig.xp.map((m) => m.gemReward).toList(),
          [25, 100, 250]);
    });

    test('crossing the first threshold unlocks only it', () {
      final unlocked = <String>{};
      final gems = AchievementConfig.gemsForThreshold(
          AchievementConfig.xp, 1000, unlocked);
      expect(gems, 25);
      expect(unlocked, {'xp_1000'});
    });

    test('jumping past the top threshold unlocks all three in one pass',
        () {
      final unlocked = <String>{};
      final gems = AchievementConfig.gemsForThreshold(
          AchievementConfig.xp, 50000, unlocked);
      expect(gems, 25 + 100 + 250);
      expect(unlocked, {'xp_1000', 'xp_10000', 'xp_50000'});
    });

    test('is idempotent: re-evaluating an already-unlocked id grants no gems',
        () {
      final unlocked = {'xp_1000'};
      final gems = AchievementConfig.gemsForThreshold(
          AchievementConfig.xp, 1000, unlocked);
      expect(gems, 0);
      expect(unlocked, {'xp_1000'});
    });

    test('below every threshold unlocks nothing', () {
      final unlocked = <String>{};
      expect(
        AchievementConfig.gemsForThreshold(
            AchievementConfig.xp, 999, unlocked),
        0,
      );
      expect(unlocked, isEmpty);
    });
  });

  group('streak milestones', () {
    test('match the historical streak unlock ladder', () {
      expect(AchievementConfig.streak.map((m) => m.id).toList(),
          ['streak_3', 'streak_7', 'streak_30', 'streak_100', 'streak_365']);
      expect(AchievementConfig.streak.map((m) => m.threshold).toList(),
          [3, 7, 30, 100, 365]);
      expect(AchievementConfig.streak.map((m) => m.gemReward).toList(),
          [15, 50, 200, 500, 1000]);
    });

    test('a streak of 30 unlocks the first three tiers', () {
      final unlocked = <String>{};
      final gems = AchievementConfig.gemsForThreshold(
          AchievementConfig.streak, 30, unlocked);
      expect(gems, 15 + 50 + 200);
      expect(unlocked, {'streak_3', 'streak_7', 'streak_30'});
    });

    test('a streak regression does not re-lock or re-grant', () {
      final unlocked = {'streak_3', 'streak_7'};
      // Even if the value drops, already-unlocked ids stay and grant nothing.
      final gems = AchievementConfig.gemsForThreshold(
          AchievementConfig.streak, 1, unlocked);
      expect(gems, 0);
    });
  });
}