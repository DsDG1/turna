// Unit tests for the Achievement domain model: level derivation, target
// lookup, and the off-by-one cap at maxLevel.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:varnamala/domain/achievement.dart';

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
  group('getCurrentLevel', () {
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

  group('getTargetForLevel', () {
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
}