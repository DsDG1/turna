// Flutter imports:
import 'dart:async';

import 'package:flutter/material.dart';

// Package imports:
import 'package:injectable/injectable.dart';

// Project imports:
import 'package:varnamala/application/gems_provider.dart';
import 'package:varnamala/di/injection.dart';
import 'package:varnamala/domain/achievement.dart';
import 'package:varnamala/service/locator.dart';

@lazySingleton
class AchievementsProvider extends ChangeNotifier {
  final AppPrefs appPrefs;

  final StreamController<List<String>> _achievementsController =
      StreamController<List<String>>.broadcast();

  static const List<Achievement> allAchievements = [
    Achievement(
      id: 'scholar',
      type: AchievementType.scholar,
      title: 'Scholar',
      description: 'Learn new words',
      icon: Icons.auto_stories_rounded,
      color: Color(0xFF42A5F5),
      targets: [50, 100, 250, 500, 1000],
    ),
    Achievement(
      id: 'sage',
      type: AchievementType.sage,
      title: 'Sage',
      description: 'Earn XP in a single day',
      icon: Icons.psychology_rounded,
      color: Color(0xFF66BB6A),
      targets: [100, 250, 500, 1000, 2000],
    ),
    Achievement(
      id: 'wildfire',
      type: AchievementType.wildfire,
      title: 'Wildfire',
      description: 'Reach a streak of days',
      icon: Icons.local_fire_department_rounded,
      color: Color(0xFFFF7043),
      targets: [3, 7, 14, 30, 75, 125, 200, 365],
    ),
    Achievement(
      id: 'champion',
      type: AchievementType.champion,
      title: 'Champion',
      description: 'Complete lessons',
      icon: Icons.workspace_premium_rounded,
      color: Color(0xFFAB47BC),
      targets: [10, 50, 100, 250, 500],
    ),
    Achievement(
      id: 'sharpshooter',
      type: AchievementType.sharpshooter,
      title: 'Sharpshooter',
      description: 'Complete lessons with no mistakes',
      icon: Icons.track_changes_rounded,
      color: Color(0xFFEF5350),
      targets: [1, 5, 20, 50, 100],
    ),
    Achievement(
      id: 'winner',
      type: AchievementType.xp,
      title: 'Winner',
      description: 'Reach XP milestones',
      icon: Icons.emoji_events_rounded,
      color: Color(0xFFFFA726),
      targets: [1, 5, 10, 25],
    ),
  ];

  static final Map<String, Achievement> _achievementById = {
    for (final achievement in allAchievements) achievement.id: achievement,
  };

  AchievementsProvider(this.appPrefs);

  Stream<List<String>> getUnlockedAchievements() async* {
    yield _readList();
    yield* _achievementsController.stream;
  }

  Future<bool> checkAndUnlock(String achievementId) async {
    final achievement = _achievementById[achievementId];
    if (achievement == null) return false;

    final unlocked = _readList().toSet();
    if (!unlocked.add(achievementId)) return false;

    await appPrefs.preferences.setStringList(
      LocalStateKeys.achievements,
      unlocked.toList(growable: false),
    );

    // Route gem bonus through [GemsProvider] so there is a single writer for
    // [LocalStateKeys.gems] (avoids clobber races with earnGems / addGems).
    if (getIt.isRegistered<GemsProvider>()) {
      await getIt<GemsProvider>().addGems(50);
    } else {
      // Fallback (e.g. unit tests that don't register GemsProvider) — direct
      // write so the test path still records the unlock value.
      final currentGems = _readInt(LocalStateKeys.gems, 0);
      await appPrefs.preferences.setInt(LocalStateKeys.gems, currentGems + 50);
    }

    _achievementsController.add(unlocked.toList(growable: false));
    notifyListeners();
    return true;
  }

  Future<void> checkLessonMilestones({
    required int lessonsCompleted,
    required int perfectLessons,
  }) async {
    if (lessonsCompleted >= 10) {
      await checkAndUnlock('champion');
    }
    if (perfectLessons >= 1) {
      await checkAndUnlock('sharpshooter');
    }
  }

  List<String> _readList() =>
      appPrefs.preferences.getStringList(
        LocalStateKeys.achievements,
        defaultValue: const [],
      ).getValue();

  int _readInt(String key, int fallback) =>
      appPrefs.preferences.getInt(key, defaultValue: fallback).getValue();

  @override
  void dispose() {
    _achievementsController.close();
    super.dispose();
  }
}