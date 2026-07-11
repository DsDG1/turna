// Dart imports:
import 'dart:async';

// Flutter imports:
import 'package:flutter/foundation.dart';

// Package imports:
import 'package:injectable/injectable.dart';

// Project imports:
import 'package:varnamala/application/game_milestone_provider.dart';
import 'package:varnamala/application/lesson_progress_provider.dart';
import 'package:varnamala/application/score_provider.dart';
import 'package:varnamala/application/streak_provider.dart';
import 'package:varnamala/domain/game/user_game_state.dart';
import 'package:varnamala/service/locator.dart';

export 'package:varnamala/application/streak_provider.dart' show StreakCheckResult;

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

/// Facade over score / streak / lesson progress / milestone providers.
///
/// Public API is stable for UI and tests (ADR 0015). Prefer sub-providers for
/// new code when a single concern is enough.
@lazySingleton
class GameProvider extends ChangeNotifier {
  final AppPrefs appPrefs;
  final ScoreProvider scoreProvider;
  final StreakProvider streakProvider;
  final LessonProgressProvider lessonProgress;
  final GameMilestoneProvider milestones;

  final StreamController<UserGameState> _stateController =
      StreamController<UserGameState>.broadcast();
  final StreamController<int> _streakController =
      StreamController<int>.broadcast();
  final StreamController<int> _scoreController =
      StreamController<int>.broadcast();

  GameProvider(
    this.appPrefs,
    this.scoreProvider,
    this.streakProvider,
    this.lessonProgress,
    this.milestones,
  );

  /// Test helper without Injectable graph.
  factory GameProvider.forTesting(AppPrefs prefs) => GameProvider(
        prefs,
        ScoreProvider(prefs),
        StreakProvider(prefs),
        LessonProgressProvider(prefs),
        GameMilestoneProvider(prefs),
      );

  // ── Lesson progress (delegated) ───────────────────────────────────

  Set<String> get completedLessonIds => lessonProgress.completedLessonIds;
  Set<String> get perfectLessonIds => lessonProgress.perfectLessonIds;

  bool isLessonCompleted(String lessonId) =>
      lessonProgress.isLessonCompleted(lessonId);

  bool isLessonPerfect(String lessonId) =>
      lessonProgress.isLessonPerfect(lessonId);

  Stream<Set<String>> get completedLessonsStream =>
      lessonProgress.completedLessonsStream;

  StreakCheckResult get lastStreakCheckResult =>
      streakProvider.lastStreakCheckResult;

  Stream<int> getUserStreakStream() async* {
    yield streakProvider.streak;
    yield* _streakController.stream;
  }

  Stream<int> getUserScoreStream() async* {
    yield scoreProvider.score;
    yield* _scoreController.stream;
  }

  Stream<UserGameState> getUserGameStateStream() async* {
    yield _readState();
    yield* _stateController.stream;
  }

  Future<UserGameState> getUserGameStateOnce() async => _readState();

  Future<void> ensureUserGameFields() async {
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

    final score = scoreProvider.score;
    final newScore = score + xp;
    final deltaXp = newScore - score;

    // Streak for this practice day (persists streak fields).
    final streakResolution = await streakProvider.applyPracticeDay(today);

    final achievements = milestones.readAchievements();
    final gemBonus = milestones.collectUnlockGems(
      achievements,
      score: newScore,
      streak: streakResolution.newStreak,
    );

    await Future.wait([
      scoreProvider.setScore(newScore),
      milestones.persistAchievements(achievements),
    ]);

    if (gemBonus != 0) {
      await milestones.applyGemBonus(gemBonus);
    }

    if (notify) notifyListeners();
    _emitState();
    return deltaXp;
  }

  Future<void> resetLessonProgress() async {
    await lessonProgress.resetLessonProgress();
    notifyListeners();
    _emitState();
  }

  Future<void> recordLessonCompletion({
    required String lessonId,
    required bool wasPerfect,
  }) async {
    await lessonProgress.recordLessonCompletion(
      lessonId: lessonId,
      wasPerfect: wasPerfect,
    );
    notifyListeners();
    _emitState();
  }

  Future<StreakCheckResult> checkStreakOnAppOpen() async {
    final result = await streakProvider.checkStreakOnAppOpen();
    notifyListeners();
    _emitState();
    return result;
  }

  // --- helpers ---

  bool _readBool(String key, bool fallback) =>
      appPrefs.preferences.getBool(key, defaultValue: fallback).getValue();

  int _readInt(String key, int fallback) =>
      appPrefs.preferences.getInt(key, defaultValue: fallback).getValue();

  List<String> _readStringList(String key, List<String> fallback) =>
      appPrefs.preferences.getStringList(key, defaultValue: fallback).getValue();

  UserGameState _readState() => UserGameState(
        score: scoreProvider.score,
        streak: streakProvider.streak,
        lastStreakDate: streakProvider.lastStreakDateRaw,
        gems: _readInt(LocalStateKeys.gems, 0),
        achievements: _readStringList(LocalStateKeys.achievements, const []),
        lessonsCompleted: _readInt(LocalStateKeys.lessonsCompleted, 0),
        perfectLessons: _readInt(LocalStateKeys.perfectLessons, 0),
        completedLessonIds:
            lessonProgress.completedLessonIds.toList(growable: false),
        perfectLessonIds:
            lessonProgress.perfectLessonIds.toList(growable: false),
        streakWasBroken: streakProvider.streakWasBroken,
        wordsLearned: _readInt(LocalStateKeys.wordsLearned, 0),
      );

  void _emitState() {
    final state = _readState();
    _stateController.add(state);
    _streakController.add(state.streak);
    _scoreController.add(state.score);
  }

  @override
  void dispose() {
    _stateController.close();
    _streakController.close();
    _scoreController.close();
    super.dispose();
  }
}
