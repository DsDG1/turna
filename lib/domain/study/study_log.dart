/// Types of learning activities that can be recorded.
enum StudyActivityType {
  lessonComplete,
  srsReview,
  grammarReview,
  matchGame,
  characterPractice,
}

/// A single atomic learning event.
class StudyLog {
  final String id;
  final DateTime timestamp;
  final StudyActivityType type;
  final String? lessonId;
  final int xpEarned;
  final int durationSeconds;
  final int correctCount;
  final int incorrectCount;
  final List<String> wordIds;

  StudyLog({
    required this.id,
    required this.timestamp,
    required this.type,
    this.lessonId,
    this.xpEarned = 0,
    this.durationSeconds = 0,
    this.correctCount = 0,
    this.incorrectCount = 0,
    this.wordIds = const [],
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'timestamp': timestamp.toIso8601String(),
        'type': type.name,
        'lessonId': lessonId,
        'xpEarned': xpEarned,
        'durationSeconds': durationSeconds,
        'correctCount': correctCount,
        'incorrectCount': incorrectCount,
        'wordIds': wordIds,
      };

  factory StudyLog.fromJson(Map<String, dynamic> json) => StudyLog(
        id: json['id'] as String,
        timestamp: DateTime.parse(json['timestamp'] as String),
        type: StudyActivityType.values.byName(json['type'] as String),
        lessonId: json['lessonId'] as String?,
        xpEarned: (json['xpEarned'] as num?)?.toInt() ?? 0,
        durationSeconds: (json['durationSeconds'] as num?)?.toInt() ?? 0,
        correctCount: (json['correctCount'] as num?)?.toInt() ?? 0,
        incorrectCount: (json['incorrectCount'] as num?)?.toInt() ?? 0,
        wordIds: (json['wordIds'] as List<dynamic>?)
                ?.map((e) => e as String)
                .toList() ??
            const [],
      );
}
