// Flutter imports:
import 'package:flutter/material.dart';

enum AchievementType {
  streak(title: 'Streak', description: 'Streak days'),
  xp(title: 'XP', description: 'Total XP'),
  lessons(title: 'Lessons', description: 'Lessons completed'),
  perfectLessons(title: 'Perfect', description: 'Perfect lessons'),
  vocabulary(title: 'Words', description: 'Words learned'),
  champion(title: 'Champion', description: 'Course progress'),
  scholar(title: 'Scholar', description: 'New words'),
  sage(title: 'Sage', description: 'Focus'),
  sharpshooter(title: 'Sharpshooter', description: 'Accuracy'),
  wildfire(title: 'Wildfire', description: 'Consistency');

  final String title;
  final String description;
  const AchievementType({required this.title, required this.description});
}

class Achievement {
  final String id;
  final AchievementType type;
  final String title;
  final String description;
  final IconData icon;
  final Color color;
  final List<int> targets; 
  
  int get maxLevel => targets.length;

  const Achievement({
    required this.id,
    required this.type,
    required this.title,
    required this.description,
    required this.icon,
    required this.color,
    required this.targets,
  });

  // Helper to get current level (1-based) based on current progress value.
  // Capped at [maxLevel] (= targets.length): once progress meets or exceeds
  // the final target, the achievement is at its maximum level.
  int getCurrentLevel(int progress) {
    for (int i = 0; i < targets.length; i++) {
        if (progress < targets[i]) {
            return i + 1;
        }
    }
    return targets.length;
  }

  int getTargetForLevel(int level) {
      if (level <= 0) return targets.isNotEmpty ? targets.first : 0;
      if (level > targets.length) return targets.isNotEmpty ? targets.last : 0;
      return targets[level - 1];
  }
}
