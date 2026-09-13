/// Snapshot of the local player's progression counters and sets.
///
/// Produced by [GameProvider]; UI binds to typed fields instead of
/// `Map<String, dynamic>` key lookups.
class UserGameState {
  final int score;
  final int streak;
  final String lastStreakDate;
  final int gems;
  final List<String> achievements;
  final int lessonsCompleted;
  final int perfectLessons;
  final List<String> completedLessonIds;
  final List<String> perfectLessonIds;
  final bool streakWasBroken;
  final int wordsLearned;

  const UserGameState({
    required this.score,
    required this.streak,
    required this.lastStreakDate,
    required this.gems,
    required this.achievements,
    required this.lessonsCompleted,
    required this.perfectLessons,
    required this.completedLessonIds,
    required this.perfectLessonIds,
    required this.streakWasBroken,
    required this.wordsLearned,
  });

  static const empty = UserGameState(
    score: 0,
    streak: 0,
    lastStreakDate: '',
    gems: 0,
    achievements: <String>[],
    lessonsCompleted: 0,
    perfectLessons: 0,
    completedLessonIds: <String>[],
    perfectLessonIds: <String>[],
    streakWasBroken: false,
    wordsLearned: 0,
  );
}
