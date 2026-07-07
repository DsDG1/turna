// Flutter imports:
import 'dart:async';

import 'package:flutter/material.dart';

// Package imports:
import 'package:injectable/injectable.dart';

// Project imports:
import 'package:words625/service/locator.dart';

enum XPEvent {
  lessonComplete(base: 10),
  perfectLesson(base: 15),
  dailyGoalComplete(base: 20),
  streakBonus(base: 5),
  challengeWin(base: 25);

  final int base;
  const XPEvent({required this.base});
}

enum StreakCheckResult {
  none,
  maintained,
  freezeConsumed,
  broken,
}

@injectable
class GameProvider extends ChangeNotifier {
  static const String bronzeLeague = 'bronze';
  static const int defaultDailyXpGoal = 50;
  static const int defaultStreakRepairTarget = 100;

  final AppPrefs appPrefs;

  final StreamController<Map<String, dynamic>> _stateController =
      StreamController<Map<String, dynamic>>.broadcast();
  final StreamController<int> _streakController =
      StreamController<int>.broadcast();
  final StreamController<int> _scoreController =
      StreamController<int>.broadcast();

  StreakCheckResult _lastStreakCheckResult = StreakCheckResult.none;
  StreakCheckResult get lastStreakCheckResult => _lastStreakCheckResult;

  GameProvider(this.appPrefs);

  Stream<int> getUserStreakStream() async* {
    yield _readInt(LocalStateKeys.streak, 0);
    yield* _streakController.stream;
  }

  Stream<int> getUserScoreStream() async* {
    yield _readInt(LocalStateKeys.score, 0);
    yield* _scoreController.stream;
  }

  Stream<Map<String, dynamic>> getUserGameStateStream() async* {
    yield _readState();
    yield* _stateController.stream;
  }

  Future<Map<String, dynamic>> getUserGameStateOnce() async => _readState();

  Future<void> ensureUserGameFields() async {
    // Seed defaults only once. We use a dedicated boolean to mark completion.
    if (_readBool(LocalStateKeys.initialized, false)) {
      return;
    }

    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);

    await Future.wait([
      appPrefs.preferences.setInt(LocalStateKeys.score, 0),
      appPrefs.preferences.setInt(LocalStateKeys.streak, 0),
      appPrefs.preferences.setString(
        LocalStateKeys.lastStreakDate,
        today.toIso8601String(),
      ),
      appPrefs.preferences.setInt(LocalStateKeys.leagueXp, 0),
      appPrefs.preferences.setInt(LocalStateKeys.dailyXpGoal, defaultDailyXpGoal),
      appPrefs.preferences.setInt(LocalStateKeys.dailyXpEarned, 0),
      appPrefs.preferences.setString(
        LocalStateKeys.lastDailyReset,
        today.toIso8601String(),
      ),
      appPrefs.preferences.setInt(LocalStateKeys.lessonsCompleted, 0),
      appPrefs.preferences.setInt(LocalStateKeys.perfectLessons, 0),
      appPrefs.preferences.setInt(LocalStateKeys.streakFreezes, 0),
      appPrefs.preferences.setBool(LocalStateKeys.streakFreezeActive, false),
      appPrefs.preferences.setBool(LocalStateKeys.streakWasBroken, false),
      appPrefs.preferences.setBool(LocalStateKeys.streakRepairRequired, false),
      appPrefs.preferences.setInt(LocalStateKeys.streakRepairProgress, 0),
      appPrefs.preferences.setInt(
        LocalStateKeys.streakRepairTarget,
        defaultStreakRepairTarget,
      ),
      appPrefs.preferences.setInt(LocalStateKeys.streakBeforeBreak, 0),
      appPrefs.preferences.setInt(LocalStateKeys.wordsLearned, 0),
      appPrefs.preferences.setInt(LocalStateKeys.friendsCount, 0),
      appPrefs.preferences.setBool(LocalStateKeys.followRewardClaimed, false),
      appPrefs.preferences.setInt(LocalStateKeys.validatedShareCount, 0),
      appPrefs.preferences.setInt(LocalStateKeys.claimedShareCount, 0),
      appPrefs.preferences.setStringList(LocalStateKeys.achievements, const []),
      appPrefs.preferences.setBool(LocalStateKeys.initialized, true),
    ]);

    notifyListeners();
    _emitState();
  }

  Future<int> awardXP(
    XPEvent event, {
    double multiplier = 1.0,
    bool notify = true,
  }) async {
    final xp = (event.base * multiplier).round();
    if (xp <= 0) return 0;

    await incrementScore(xp, notify: false);

    if (notify) notifyListeners();
    return xp;
  }

  Future<void> incrementScore(int xp, {bool notify = true}) async {
    if (xp <= 0) return;

    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);

    final score = _readInt(LocalStateKeys.score, 0);
    final streak = _readInt(LocalStateKeys.streak, 0);
    final leagueXp = _readInt(LocalStateKeys.leagueXp, 0);
    final streakFreezeActive =
        _readBool(LocalStateKeys.streakFreezeActive, false);
    final streakFreezes = _readInt(LocalStateKeys.streakFreezes, 0);
    final lastDate = _parseDate(_readString(LocalStateKeys.lastStreakDate, ''));

    final streakResolution = _resolveStreakOnPractice(
      oldStreak: streak,
      oldDate: lastDate,
      today: today,
      streakFreezeActive: streakFreezeActive,
      streakFreezes: streakFreezes,
    );

    final newScore = score + xp;
    var newGems = _readInt(LocalStateKeys.gems, 0);

    final achievements = _readStringList(LocalStateKeys.achievements, const [])
        .toSet();

    newGems += _unlockXpAchievements(achievements, newScore);
    newGems += _unlockStreakAchievements(
      achievements,
      streakResolution.newStreak,
    );

    final dailyResetDate = _parseDate(
      _readString(LocalStateKeys.lastDailyReset, ''),
    );
    var dailyXpEarned = _readInt(LocalStateKeys.dailyXpEarned, 0);
    if (dailyResetDate == null || !_isSameDay(dailyResetDate, today)) {
      dailyXpEarned = 0;
    }

    final dailyGoal = _readInt(LocalStateKeys.dailyXpGoal, defaultDailyXpGoal);
    final previousDailyXp = dailyXpEarned;
    dailyXpEarned += xp;

    final streakRepairRequired =
        _readBool(LocalStateKeys.streakRepairRequired, false);
    final streakWasBroken = _readBool(LocalStateKeys.streakWasBroken, false);
    final streakRepairTarget =
        _readInt(LocalStateKeys.streakRepairTarget, defaultStreakRepairTarget);
    final previousRepairProgress =
        _readInt(LocalStateKeys.streakRepairProgress, 0);

    var streakRepairProgress = previousRepairProgress;
    var repairedThisUpdate = false;
    var repairedStreak = streakResolution.newStreak;

    if (streakRepairRequired && streakWasBroken) {
      streakRepairProgress = previousRepairProgress + xp;
      if (streakRepairProgress >= streakRepairTarget) {
        repairedThisUpdate = true;
        final streakBeforeBreak =
            _readInt(LocalStateKeys.streakBeforeBreak, 1);
        repairedStreak = streakBeforeBreak <= 0 ? 1 : streakBeforeBreak;
      }
    }

    var finalScore = newScore;
    if (previousDailyXp < dailyGoal && dailyXpEarned >= dailyGoal) {
      finalScore += XPEvent.dailyGoalComplete.base;
    }

    await Future.wait([
      appPrefs.preferences.setInt(LocalStateKeys.score, finalScore),
      appPrefs.preferences.setInt(
        LocalStateKeys.streak,
        repairedThisUpdate ? repairedStreak : streakResolution.newStreak,
      ),
      appPrefs.preferences.setString(
        LocalStateKeys.lastStreakDate,
        today.toIso8601String(),
      ),
      appPrefs.preferences.setInt(
        LocalStateKeys.streakFreezes,
        streakResolution.remainingFreezes,
      ),
      appPrefs.preferences.setBool(
        LocalStateKeys.streakFreezeActive,
        streakResolution.freezeActive,
      ),
      appPrefs.preferences.setBool(
        LocalStateKeys.streakWasBroken,
        repairedThisUpdate ? false : streakResolution.broken,
      ),
      appPrefs.preferences.setBool(
        LocalStateKeys.streakRepairRequired,
        repairedThisUpdate
            ? false
            : (streakRepairRequired && streakWasBroken),
      ),
      appPrefs.preferences.setInt(
        LocalStateKeys.streakRepairProgress,
        repairedThisUpdate ? 0 : streakRepairProgress,
      ),
      appPrefs.preferences.setInt(
        LocalStateKeys.streakRepairTarget,
        streakRepairTarget,
      ),
      appPrefs.preferences.setInt(LocalStateKeys.leagueXp, leagueXp + xp),
      appPrefs.preferences.setInt(LocalStateKeys.dailyXpEarned, dailyXpEarned),
      appPrefs.preferences.setInt(LocalStateKeys.dailyXpGoal, dailyGoal),
      appPrefs.preferences.setString(
        LocalStateKeys.lastDailyReset,
        today.toIso8601String(),
      ),
      appPrefs.preferences.setInt(LocalStateKeys.gems, newGems),
      appPrefs.preferences.setStringList(
        LocalStateKeys.achievements,
        achievements.toList(growable: false),
      ),
    ]);

    if (notify) notifyListeners();
    _emitState();
  }

  Future<void> recordLessonCompletion({
    required bool wasPerfect,
  }) async {
    final lessonsCompleted =
        _readInt(LocalStateKeys.lessonsCompleted, 0) + 1;
    final perfectLessons =
        _readInt(LocalStateKeys.perfectLessons, 0) + (wasPerfect ? 1 : 0);

    await Future.wait([
      appPrefs.preferences.setInt(LocalStateKeys.lessonsCompleted, lessonsCompleted),
      appPrefs.preferences.setInt(LocalStateKeys.perfectLessons, perfectLessons),
    ]);

    notifyListeners();
    _emitState();
  }

  Future<StreakCheckResult> checkStreakOnAppOpen() async {
    final lastDateStr = _readString(LocalStateKeys.lastStreakDate, '');
    final lastDate = _parseDate(lastDateStr);

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
      _emitState();
      return _lastStreakCheckResult;
    }

    final streakFreezes = _readInt(LocalStateKeys.streakFreezes, 0);
    final freezeActive = _readBool(LocalStateKeys.streakFreezeActive, false);

    if (gap == 2 && (freezeActive || streakFreezes > 0)) {
      await Future.wait([
        appPrefs.preferences.setInt(
          LocalStateKeys.streakFreezes,
          freezeActive ? streakFreezes : streakFreezes - 1,
        ),
        appPrefs.preferences.setBool(LocalStateKeys.streakFreezeActive, false),
        appPrefs.preferences.setString(
          LocalStateKeys.lastStreakDate,
          today.toIso8601String(),
        ),
        appPrefs.preferences.setBool(LocalStateKeys.streakWasBroken, false),
      ]);
      _lastStreakCheckResult = StreakCheckResult.freezeConsumed;
      notifyListeners();
      _emitState();
      return _lastStreakCheckResult;
    }

    await Future.wait([
      appPrefs.preferences.setInt(LocalStateKeys.streak, 0),
      appPrefs.preferences.setBool(LocalStateKeys.streakWasBroken, true),
      appPrefs.preferences.setInt(
        LocalStateKeys.streakBeforeBreak,
        _readInt(LocalStateKeys.streak, 0),
      ),
      appPrefs.preferences.setBool(LocalStateKeys.streakRepairRequired, true),
      appPrefs.preferences.setInt(LocalStateKeys.streakRepairProgress, 0),
      appPrefs.preferences.setInt(
        LocalStateKeys.streakRepairTarget,
        defaultStreakRepairTarget,
      ),
    ]);

    _lastStreakCheckResult = StreakCheckResult.broken;
    notifyListeners();
    _emitState();
    return _lastStreakCheckResult;
  }

  // --- Internal helpers ---

  int _readInt(String key, int fallback) =>
      appPrefs.preferences.getInt(key, defaultValue: fallback).getValue();

  bool _readBool(String key, bool fallback) =>
      appPrefs.preferences.getBool(key, defaultValue: fallback).getValue();

  String _readString(String key, String fallback) =>
      appPrefs.preferences.getString(key, defaultValue: fallback).getValue();

  List<String> _readStringList(String key, List<String> fallback) =>
      appPrefs.preferences.getStringList(key, defaultValue: fallback).getValue();

  Map<String, dynamic> _readState() => {
        'score': _readInt(LocalStateKeys.score, 0),
        'streak': _readInt(LocalStateKeys.streak, 0),
        'lastStreakDate': _readString(LocalStateKeys.lastStreakDate, ''),
        'leagueXp': _readInt(LocalStateKeys.leagueXp, 0),
        'league': bronzeLeague,
        'gems': _readInt(LocalStateKeys.gems, 0),
        'hearts': _readInt(LocalStateKeys.hearts, 5),
        'heartsRefillAt': null,
        'streakFreezes': _readInt(LocalStateKeys.streakFreezes, 0),
        'streakFreezeActive':
            _readBool(LocalStateKeys.streakFreezeActive, false),
        'achievements':
            _readStringList(LocalStateKeys.achievements, const []),
        'dailyXpGoal': _readInt(LocalStateKeys.dailyXpGoal, defaultDailyXpGoal),
        'dailyXpEarned': _readInt(LocalStateKeys.dailyXpEarned, 0),
        'lastDailyReset': _readString(LocalStateKeys.lastDailyReset, ''),
        'lessonsCompleted':
            _readInt(LocalStateKeys.lessonsCompleted, 0),
        'perfectLessons': _readInt(LocalStateKeys.perfectLessons, 0),
        'streakWasBroken': _readBool(LocalStateKeys.streakWasBroken, false),
        'streakRepairRequired':
            _readBool(LocalStateKeys.streakRepairRequired, false),
        'streakRepairProgress':
            _readInt(LocalStateKeys.streakRepairProgress, 0),
        'streakRepairTarget':
            _readInt(LocalStateKeys.streakRepairTarget, defaultStreakRepairTarget),
        'streakBeforeBreak': _readInt(LocalStateKeys.streakBeforeBreak, 0),
        'followRewardClaimed':
            _readBool(LocalStateKeys.followRewardClaimed, false),
        'validatedShareCount':
            _readInt(LocalStateKeys.validatedShareCount, 0),
        'claimedShareCount': _readInt(LocalStateKeys.claimedShareCount, 0),
        'wordsLearned': _readInt(LocalStateKeys.wordsLearned, 0),
        'friendsCount': _readInt(LocalStateKeys.friendsCount, 0),
        'languages': <String>[],
      };

  void _emitState() {
    final state = _readState();
    _stateController.add(state);
    _streakController.add(state['streak'] as int);
    _scoreController.add(state['score'] as int);
  }

  int _unlockXpAchievements(Set<String> achievements, int score) {
    var gemsReward = 0;
    if (score >= 1000 && achievements.add('xp_1000')) gemsReward += 25;
    if (score >= 10000 && achievements.add('xp_10000')) gemsReward += 100;
    if (score >= 50000 && achievements.add('xp_50000')) gemsReward += 250;
    return gemsReward;
  }

  int _unlockStreakAchievements(Set<String> achievements, int streak) {
    var gemsReward = 0;
    if (streak >= 3 && achievements.add('streak_3')) gemsReward += 15;
    if (streak >= 7 && achievements.add('streak_7')) gemsReward += 50;
    if (streak >= 30 && achievements.add('streak_30')) gemsReward += 200;
    if (streak >= 100 && achievements.add('streak_100')) gemsReward += 500;
    if (streak >= 365 && achievements.add('streak_365')) gemsReward += 1000;
    return gemsReward;
  }

  bool _isSameDay(DateTime first, DateTime second) {
    return first.year == second.year &&
        first.month == second.month &&
        first.day == second.day;
  }

  DateTime? _parseDate(dynamic value) {
    if (value == null) return null;
    if (value is DateTime) return value;
    if (value is String && value.isNotEmpty) return DateTime.tryParse(value);
    return null;
  }

  _StreakResolution _resolveStreakOnPractice({
    required int oldStreak,
    required DateTime? oldDate,
    required DateTime today,
    required bool streakFreezeActive,
    required int streakFreezes,
  }) {
    if (oldDate == null) {
      return _StreakResolution(
        newStreak: oldStreak == 0 ? 1 : oldStreak,
        remainingFreezes: streakFreezes,
        freezeActive: streakFreezeActive,
        broken: false,
      );
    }

    final last = DateTime(oldDate.year, oldDate.month, oldDate.day);
    final gap = today.difference(last).inDays;

    if (gap <= 0) {
      return _StreakResolution(
        newStreak: oldStreak,
        remainingFreezes: streakFreezes,
        freezeActive: streakFreezeActive,
        broken: false,
      );
    }

    if (gap == 1) {
      return _StreakResolution(
        newStreak: oldStreak + 1,
        remainingFreezes: streakFreezes,
        freezeActive: streakFreezeActive,
        broken: false,
      );
    }

    if (gap == 2 && (streakFreezeActive || streakFreezes > 0)) {
      return _StreakResolution(
        newStreak: oldStreak + 1,
        remainingFreezes: streakFreezeActive ? streakFreezes : streakFreezes - 1,
        freezeActive: false,
        broken: false,
      );
    }

    return _StreakResolution(
      newStreak: 1,
      remainingFreezes: streakFreezes,
      freezeActive: streakFreezeActive,
      broken: true,
    );
  }

  @override
  void dispose() {
    _stateController.close();
    _streakController.close();
    _scoreController.close();
    super.dispose();
  }
}

class _StreakResolution {
  final int newStreak;
  final int remainingFreezes;
  final bool freezeActive;
  final bool broken;

  _StreakResolution({
    required this.newStreak,
    required this.remainingFreezes,
    required this.freezeActive,
    required this.broken,
  });
}