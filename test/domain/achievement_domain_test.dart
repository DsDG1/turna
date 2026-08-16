// Consolidated domain and config tests for Achievements and XP/Streak milestones.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:turna/core/achievement_config.dart';
import 'package:turna/domain/achievement.dart';

Achievement _achievement({required List<int> targets}) => Achievement(
      id: 'a-test',
      type: AchievementType.xp,
      title: 'XP',
      description: 'Total XP',
      icon: Icons.star,
      color: Colors.amber,
      targets: targets,
    );

void main() {
  group('Achievement getCurrentLevel', () {
    test('progress below the first target is level 1', () {
      final a = _achievement(targets: [100, 1000, 10000]);
      expect(a.getCurrentLevel(0), 1);
      expect(a.getCurrentLevel(99), 1);
    });

    test('progress at a target boundary advances to the next level', () {
      final a = _achievement(targets: [100, 1000, 10000]);
      expect(a.getCurrentLevel(100), 2);
      expect(a.getCurrentLevel(1000), 3);
    });

    test('progress meeting or exceeding the final target is capped at maxLevel',
        () {
      final a = _achievement(targets: [100, 1000, 10000]);
      expect(a.maxLevel, 3);
      expect(a.getCurrentLevel(10000), 3); // at the final target
      expect(a.getCurrentLevel(999999), 3); // far beyond
      // Regression guard: must never exceed maxLevel (was length + 1).
      expect(a.getCurrentLevel(999999), lessThanOrEqualTo(a.maxLevel));
    });

    test('an achievement with a single target caps at level 1 when reached',
        () {
      final a = _achievement(targets: [7]);
      expect(a.maxLevel, 1);
      expect(a.getCurrentLevel(0), 1);
      expect(a.getCurrentLevel(7), 1);
    });
  });

  group('Achievement getTargetForLevel', () {
    test('returns the target for each 1-based level', () {
      final a = _achievement(targets: [100, 1000, 10000]);
      expect(a.getTargetForLevel(1), 100);
      expect(a.getTargetForLevel(2), 1000);
      expect(a.getTargetForLevel(3), 10000);
    });

    test('levels above maxLevel clamp to the last target', () {
      final a = _achievement(targets: [100, 1000, 10000]);
      expect(a.getTargetForLevel(4), 10000);
      expect(a.getTargetForLevel(99), 10000);
    });

    test('non-positive levels fall back to the first target', () {
      final a = _achievement(targets: [100, 1000, 10000]);
      expect(a.getTargetForLevel(0), 100);
      expect(a.getTargetForLevel(-1), 100);
    });

    test('an empty-target achievement never throws and reports 0', () {
      final a = _achievement(targets: const []);
      expect(a.maxLevel, 0);
      expect(a.getTargetForLevel(1), 0);
      expect(a.getCurrentLevel(123), 0);
    });
  });

  group('AchievementConfig xp milestones', () {
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

    test('jumping past the top threshold unlocks all three in one pass', () {
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
        AchievementConfig.gemsForThreshold(AchievementConfig.xp, 999, unlocked),
        0,
      );
      expect(unlocked, isEmpty);
    });
  });

  group('AchievementConfig streak milestones', () {
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
