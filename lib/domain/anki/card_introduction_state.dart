import 'package:turna/domain/anki/canonical_card_key.dart';

enum CardIntroductionStatus {
  unintroduced,
  introduced,
  retired,
}

enum CardIntroducedBy {
  course,
  importedHistory,
  migration,
  manual,
}

class CardIntroductionState {
  const CardIntroductionState({
    required this.courseId,
    required this.cardKey,
    required this.status,
    this.introducedBy,
    this.introducedAt,
    this.firstLessonId,
    this.lastStudiedAt,
    this.version = 1,
  });

  final String courseId;
  final CanonicalCardKey cardKey;
  final CardIntroductionStatus status;
  final CardIntroducedBy? introducedBy;
  final DateTime? introducedAt;
  final String? firstLessonId;
  final DateTime? lastStudiedAt;
  final int version;

  bool get isIntroduced => status == CardIntroductionStatus.introduced;
  bool get isRetired => status == CardIntroductionStatus.retired;

  CardIntroductionState copyWith({
    CardIntroductionStatus? status,
    CardIntroducedBy? introducedBy,
    DateTime? introducedAt,
    String? firstLessonId,
    DateTime? lastStudiedAt,
    int? version,
  }) {
    return CardIntroductionState(
      courseId: courseId,
      cardKey: cardKey,
      status: status ?? this.status,
      introducedBy: introducedBy ?? this.introducedBy,
      introducedAt: introducedAt ?? this.introducedAt,
      firstLessonId: firstLessonId ?? this.firstLessonId,
      lastStudiedAt: lastStudiedAt ?? this.lastStudiedAt,
      version: version ?? this.version,
    );
  }
}
