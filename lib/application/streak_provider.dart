// Flutter imports:
import 'package:flutter/foundation.dart';

// Package imports:
import 'package:injectable/injectable.dart';

// Project imports:
import 'package:turna/core/streak_resolver.dart';
import 'package:turna/service/locator.dart';

/// Result of [StreakProvider.checkStreakOnAppOpen].
enum StreakCheckResult {
  none,
  maintained,
  broken,
}

/// Owns streak prefs and app-open / practice-day resolution.
@lazySingleton
class StreakProvider extends ChangeNotifier {
  StreakProvider(this.appPrefs);

  final AppPrefs appPrefs;

  StreakCheckResult _lastStreakCheckResult = StreakCheckResult.none;
  StreakCheckResult get lastStreakCheckResult => _lastStreakCheckResult;

  int get streak =>
      appPrefs.preferences.getInt(LocalStateKeys.streak, defaultValue: 0).getValue();

  String get lastStreakDateRaw => appPrefs.preferences
      .getString(LocalStateKeys.lastStreakDate, defaultValue: '')
      .getValue();

  bool get streakWasBroken => appPrefs.preferences
      .getBool(LocalStateKeys.streakWasBroken, defaultValue: false)
      .getValue();

  DateTime? parseDate(String value) {
    if (value.isEmpty) return null;
    return DateTime.tryParse(value);
  }

  /// Apply practice on [today]; persists streak fields and returns resolution.
  Future<StreakResolution> applyPracticeDay(DateTime today) async {
    final oldStreak = streak;
    final oldDate = parseDate(lastStreakDateRaw);
    final resolution = resolveStreakOnPractice(
      oldStreak: oldStreak,
      oldDate: oldDate,
      today: today,
    );

    await Future.wait([
      appPrefs.preferences.setInt(LocalStateKeys.streak, resolution.newStreak),
      appPrefs.preferences.setString(
        LocalStateKeys.lastStreakDate,
        today.toIso8601String(),
      ),
      appPrefs.preferences.setBool(
        LocalStateKeys.streakWasBroken,
        resolution.broken,
      ),
    ]);
    notifyListeners();
    return resolution;
  }

  Future<StreakCheckResult> checkStreakOnAppOpen() async {
    final lastDate = parseDate(lastStreakDateRaw);

    if (lastDate == null) {
      _lastStreakCheckResult = StreakCheckResult.none;
      notifyListeners();
      return _lastStreakCheckResult;
    }

    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final last = DateTime(lastDate.year, lastDate.month, lastDate.day);
    final gap = today.difference(last).inDays;

    if (gap <= 1) {
      await appPrefs.preferences.setBool(LocalStateKeys.streakWasBroken, false);
      _lastStreakCheckResult = StreakCheckResult.maintained;
      notifyListeners();
      return _lastStreakCheckResult;
    }

    // No streak to break: a fresh install (or one where the user never
    // practiced) seeds lastStreakDate=today with streak=0. Don't surface a
    // "streak broken" notice for users who never built a streak.
    if (streak == 0) {
      _lastStreakCheckResult = StreakCheckResult.none;
      notifyListeners();
      return _lastStreakCheckResult;
    }

    await Future.wait([
      appPrefs.preferences.setInt(LocalStateKeys.streak, 0),
      appPrefs.preferences.setBool(LocalStateKeys.streakWasBroken, true),
    ]);

    _lastStreakCheckResult = StreakCheckResult.broken;
    notifyListeners();
    return _lastStreakCheckResult;
  }
}
