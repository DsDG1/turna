/// Aggregated statistics for a single day.
class DailyStudyStats {
  final DateTime date;
  final int totalXp;
  final int totalDurationSeconds;
  final int correctCount;
  final int incorrectCount;
  final int lessonCount;
  final int reviewCount;

  DailyStudyStats({
    required this.date,
    this.totalXp = 0,
    this.totalDurationSeconds = 0,
    this.correctCount = 0,
    this.incorrectCount = 0,
    this.lessonCount = 0,
    this.reviewCount = 0,
  });

  double get accuracy =>
      (correctCount + incorrectCount) == 0
          ? 0.0
          : correctCount / (correctCount + incorrectCount);

  int get totalQuestions => correctCount + incorrectCount;

  Map<String, dynamic> toJson() => {
        'date': _dateKey(date),
        'totalXp': totalXp,
        'totalDurationSeconds': totalDurationSeconds,
        'correctCount': correctCount,
        'incorrectCount': incorrectCount,
        'lessonCount': lessonCount,
        'reviewCount': reviewCount,
      };

  factory DailyStudyStats.fromJson(Map<String, dynamic> json) {
    final dateKey = json['date'] as String;
    return DailyStudyStats(
      date: _parseDateKey(dateKey),
      totalXp: (json['totalXp'] as num?)?.toInt() ?? 0,
      totalDurationSeconds:
          (json['totalDurationSeconds'] as num?)?.toInt() ?? 0,
      correctCount: (json['correctCount'] as num?)?.toInt() ?? 0,
      incorrectCount: (json['incorrectCount'] as num?)?.toInt() ?? 0,
      lessonCount: (json['lessonCount'] as num?)?.toInt() ?? 0,
      reviewCount: (json['reviewCount'] as num?)?.toInt() ?? 0,
    );
  }

  static String _dateKey(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  static DateTime _parseDateKey(String key) {
    final parts = key.split('-');
    return DateTime(
      int.parse(parts[0]),
      int.parse(parts[1]),
      int.parse(parts[2]),
    );
  }
}

/// A weak word entry for targeted review.
class WeakWord {
  final String wordId;
  final String displayText;
  final String? translation;
  final int mistakeCount;
  final DateTime lastMistakeAt;

  WeakWord({
    required this.wordId,
    required this.displayText,
    this.translation,
    required this.mistakeCount,
    required this.lastMistakeAt,
  });
}
