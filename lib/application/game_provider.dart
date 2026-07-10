// Flutter imports:
import 'dart:async';

import 'package:flutter/material.dart';

// Package imports:
import 'package:injectable/injectable.dart';

// Project imports:
import 'package:varnamala/application/gems_provider.dart';
import 'package:varnamala/core/achievement_config.dart';
import 'package:varnamala/di/injection.dart';
import 'package:varnamala/domain/game/user_game_state.dart';
import 'package:varnamala/service/locator.dart';

enum XPEvent {
  lessonComplete(base: 10),
  perfectLesson(base: 15),
  /// Base XP per reviewed word/card; multiply by session count.
  srsReviewSession(base: 5),
  /// Base XP per reviewed grammar point; multiply by session count.
  grammarReviewSession(base: 5);

  final int base;
  const XPEvent({required this.base});
}

enum StreakCheckResult {
  none,
  maintained,
  broken,
}

@lazySingleton
class GameProvider extends ChangeNotifier {
  final AppPrefs appPrefs;

  final StreamController<UserGameState> _stateController =
      StreamController<UserGameState>.broadcast();
  final StreamController<int> _streakController =
      StreamController<int>.broadcast();
  final StreamController<int> _scoreController =
      StreamController<int>.broadcast();
  final StreamController<Set<String>> _completedLessonsController =
      StreamController<Set<String>>.broadcast();

  /// Set of lesson ids the user has completed at least once. Loaded
  /// eagerly from prefs in the constructor; treated as the source of
  /// truth for "have I done this lesson?" checks.
  late Set<String> _completedLessonIds;
  late Set<String> _perfectLessonIds;

  /// Read-only snapshot of the completed lessons set. UI bindings should
  /// use [completedLessonsStream] for live updates.
  Set<String> get completedLessonIds => Set.unmodifiable(_completedLessonIds);
  Set<String> get perfectLessonIds => Set.unmodifiable(_perfectLessonIds);

  /// True if the user has finished the given lesson at least once.
  bool isLessonCompleted(String lessonId) =>
      _completedLessonIds.contains(lessonId);

  /// True if the user has finished the given lesson without any mistakes.
  bool isLessonPerfect(String lessonId) =>
      _perfectLessonIds.contains(lessonId);

  /// Broadcasts the current [completedLessonIds] set, then any future
  /// updates. Use this from `StreamBuilder` to react to lesson finishes.
  Stream<Set<String>> get completedLessonsStream async* {
    yield Set.unmodifiable(_completedLessonIds);
    yield* _completedLessonsController.stream;
  }

  StreakCheckResult _lastStreakCheckResult = StreakCheckResult.none;
  StreakCheckResult get lastStreakCheckResult => _lastStreakCheckResult;

  GameProvider(this.appPrefs) {
    _completedLessonIds = _readStringList(
      LocalStateKeys.completedLessonIds,
      const <String>[],
    ).toSet();
    _perfectLessonIds = _readStringList(
      LocalStateKeys.perfectLessonIds,
      const <String>[],
    ).toSet();
  }

  Stream<int> getUserStreakStream() async* {
    yield _readInt(LocalStateKeys.streak, 0);
    yield* _streakController.stream;
  }

  Stream<int> getUserScoreStream() async* {
    yield _readInt(LocalStateKeys.score, 0);
    yield* _scoreController.stream;
  }

  Stream<UserGameState> getUserGameStateStream() async* {
    yield _readState();
    yield* _stateController.stream;
  }

  Future<UserGameState> getUserGameStateOnce() async => _readState();

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
      appPrefs.preferences.setInt(LocalStateKeys.lessonsCompleted, 0),
      appPrefs.preferences.setInt(LocalStateKeys.perfectLessons, 0),
      // Per-lesson progress — start empty. [recordLessonCompletion] will
      // populate these on first lesson finish. Reading them with the
      // streaming prefs API yields `null` for first-run, so the seeder
      // passes an empty list as the default.
      appPrefs.preferences.setStringList(
        LocalStateKeys.completedLessonIds,
        const <String>[],
      ),
      appPrefs.preferences.setStringList(
        LocalStateKeys.perfectLessonIds,
        const <String>[],
      ),
      appPrefs.preferences.setBool(LocalStateKeys.streakWasBroken, false),
      appPrefs.preferences.setInt(LocalStateKeys.wordsLearned, 0),
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

  Future<int> incrementScore(int xp, {bool notify = true}) async {
    if (xp <= 0) return 0;

    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);

    final score = _readInt(LocalStateKeys.score, 0);
    final streak = _readInt(LocalStateKeys.streak, 0);
    final lastDate = _parseDate(_readString(LocalStateKeys.lastStreakDate, ''));

    final streakResolution = _resolveStreakOnPractice(
      oldStreak: streak,
      oldDate: lastDate,
      today: today,
    );

    final newScore = score + xp;
    final deltaXp = newScore - score;

    final achievements = _readStringList(LocalStateKeys.achievements, const [])
        .toSet();

    // Gem unlocks are applied via [GemsProvider] after score writes so there
    // is a single writer for [LocalStateKeys.gems].
    final gemBonus = _unlockXpAchievements(achievements, newScore) +
        _unlockStreakAchievements(
          achievements,
          streakResolution.newStreak,
        );

    await Future.wait([
      appPrefs.preferences.setInt(LocalStateKeys.score, newScore),
      appPrefs.preferences.setInt(
        LocalStateKeys.streak,
        streakResolution.newStreak,
      ),
      appPrefs.preferences.setString(
        LocalStateKeys.lastStreakDate,
        today.toIso8601String(),
      ),
      appPrefs.preferences.setBool(
        LocalStateKeys.streakWasBroken,
        streakResolution.broken,
      ),
      appPrefs.preferences.setStringList(
        LocalStateKeys.achievements,
        achievements.toList(growable: false),
      ),
    ]);

    if (gemBonus != 0) {
      await _applyGemBonus(gemBonus);
    }

    if (notify) notifyListeners();
    _emitState();
    return deltaXp;
  }

  /// Route gem deltas through [GemsProvider] (single writer for gems key).
  Future<void> _applyGemBonus(int amount) async {
    if (amount == 0) return;
    if (getIt.isRegistered<GemsProvider>()) {
      await getIt<GemsProvider>().addGems(amount);
      return;
    }
    // Unit tests that construct GameProvider without GetIt.
    final current = _readInt(LocalStateKeys.gems, 0);
    await appPrefs.preferences.setInt(LocalStateKeys.gems, current + amount);
  }

  /// Clears all per-lesson completion / perfect records. Used from Settings.
  Future<void> resetLessonProgress() async {
    _completedLessonIds.clear();
    _perfectLessonIds.clear();

    await Future.wait([
      appPrefs.preferences.setStringList(
        LocalStateKeys.completedLessonIds,
        const <String>[],
      ),
      appPrefs.preferences.setStringList(
        LocalStateKeys.perfectLessonIds,
        const <String>[],
      ),
      appPrefs.preferences.setInt(LocalStateKeys.lessonsCompleted, 0),
      appPrefs.preferences.setInt(LocalStateKeys.perfectLessons, 0),
      appPrefs.preferences.setInt(LocalStateKeys.wordsLearned, 0),
    ]);

    notifyListeners();
    _emitState();
    _completedLessonsController.add(const <String>{});
  }

  Future<void> recordLessonCompletion({
    required String lessonId,
    required bool wasPerfect,
  }) async {
    _completedLessonIds.add(lessonId);
    if (wasPerfect) {
      _perfectLessonIds.add(lessonId);
    }

    // The legacy int counters are now derived from the set lengths so
    // they stay in lock-step with the per-lesson records.
    final lessonsCompleted = _completedLessonIds.length;
    final perfectLessons = _perfectLessonIds.length;

    await Future.wait([
      appPrefs.preferences.setStringList(
        LocalStateKeys.completedLessonIds,
        _completedLessonIds.toList(growable: false),
      ),
      appPrefs.preferences.setStringList(
        LocalStateKeys.perfectLessonIds,
        _perfectLessonIds.toList(growable: false),
      ),
      appPrefs.preferences.setInt(
        LocalStateKeys.lessonsCompleted,
        lessonsCompleted,
      ),
      appPrefs.preferences.setInt(LocalStateKeys.perfectLessons, perfectLessons),
    ]);

    notifyListeners();
    _emitState();
    // Always emit on the progress stream so subscribers (ProgressProvider →
    // course tree) rebuild on every completion, including replays that
    // upgrade a lesson to perfect. Gating on `addedToCompleted` would miss
    // replay events and leave the Perfect badge stale.
    _completedLessonsController.add(Set.unmodifiable(_completedLessonIds));
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

    await Future.wait([
      appPrefs.preferences.setInt(LocalStateKeys.streak, 0),
      appPrefs.preferences.setBool(LocalStateKeys.streakWasBroken, true),
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

  UserGameState _readState() => UserGameState(
        score: _readInt(LocalStateKeys.score, 0),
        streak: _readInt(LocalStateKeys.streak, 0),
        lastStreakDate: _readString(LocalStateKeys.lastStreakDate, ''),
        gems: _readInt(LocalStateKeys.gems, 0),
        achievements: _readStringList(LocalStateKeys.achievements, const []),
        lessonsCompleted: _readInt(LocalStateKeys.lessonsCompleted, 0),
        perfectLessons: _readInt(LocalStateKeys.perfectLessons, 0),
        completedLessonIds: _completedLessonIds.toList(growable: false),
        perfectLessonIds: _perfectLessonIds.toList(growable: false),
        streakWasBroken: _readBool(LocalStateKeys.streakWasBroken, false),
        wordsLearned: _readInt(LocalStateKeys.wordsLearned, 0),
      );

  void _emitState() {
    final state = _readState();
    _stateController.add(state);
    _streakController.add(state.streak);
    _scoreController.add(state.score);
  }

  int _unlockXpAchievements(Set<String> achievements, int score) =>
      AchievementConfig.gemsForThreshold(AchievementConfig.xp, score, achievements);

  int _unlockStreakAchievements(Set<String> achievements, int streak) =>
      AchievementConfig.gemsForThreshold(
          AchievementConfig.streak, streak, achievements);

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
  }) {
    if (oldDate == null) {
      return _StreakResolution(
        newStreak: oldStreak == 0 ? 1 : oldStreak,
        broken: false,
      );
    }

    final last = DateTime(oldDate.year, oldDate.month, oldDate.day);
    final gap = today.difference(last).inDays;

    if (gap <= 0) {
      return _StreakResolution(
        newStreak: oldStreak,
        broken: false,
      );
    }

    if (gap == 1) {
      return _StreakResolution(
        newStreak: oldStreak + 1,
        broken: false,
      );
    }

    return _StreakResolution(
      newStreak: 1,
      broken: true,
    );
  }

  @override
  void dispose() {
    _stateController.close();
    _streakController.close();
    _scoreController.close();
    _completedLessonsController.close();
    super.dispose();
  }
}

class _StreakResolution {
  final int newStreak;
  final bool broken;

  _StreakResolution({
    required this.newStreak,
    required this.broken,
  });
}
