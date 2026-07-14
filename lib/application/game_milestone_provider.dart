// Flutter imports:
import 'package:flutter/foundation.dart';

// Package imports:
import 'package:injectable/injectable.dart';

// Project imports:
import 'package:varnamala/application/gems_provider.dart';
import 'package:varnamala/core/achievement_config.dart';
import 'package:varnamala/di/injection.dart';
import 'package:varnamala/service/locator.dart';

/// XP / streak milestone unlock ids + gem awards (not the UI [AchievementsProvider]).
@lazySingleton
class GameMilestoneProvider extends ChangeNotifier {
  GameMilestoneProvider(this.appPrefs);

  final AppPrefs appPrefs;

  Set<String> readAchievements() => appPrefs.preferences
      .getStringList(LocalStateKeys.achievements, defaultValue: const [])
      .getValue()
      .toSet();

  /// Mutates [achievements] with new unlocks; returns gem bonus total.
  /// Does not persist or apply gems — caller writes prefs then [applyGemBonus].
  int collectUnlockGems(
    Set<String> achievements, {
    required int score,
    required int streak,
  }) {
    return AchievementConfig.gemsForThreshold(
          AchievementConfig.xp,
          score,
          achievements,
        ) +
        AchievementConfig.gemsForThreshold(
          AchievementConfig.streak,
          streak,
          achievements,
        );
  }

  Future<void> persistAchievements(Set<String> achievements) async {
    await appPrefs.preferences.setStringList(
      LocalStateKeys.achievements,
      achievements.toList(growable: false),
    );
    notifyListeners();
  }

  /// Route gem deltas through [GemsProvider] (single writer for gems key).
  Future<void> applyGemBonus(int amount) async {
    if (amount == 0) return;
    if (getIt.isRegistered<GemsProvider>()) {
      await getIt<GemsProvider>().addGems(amount);
      return;
    }
    // Unit tests without full GetIt graph.
    final current = appPrefs.preferences
        .getInt(LocalStateKeys.gems, defaultValue: 0)
        .getValue();
    await appPrefs.preferences.setInt(LocalStateKeys.gems, current + amount);
  }
}
