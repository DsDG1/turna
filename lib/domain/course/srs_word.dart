// Package imports:
import 'package:freezed_annotation/freezed_annotation.dart';

part 'srs_word.freezed.dart';
part 'srs_word.g.dart';

/// Type of item tracked in the SRS queue.
enum SrsItemType { word, expression }

/// Spaced-repetition state for a [WordEntry] or [Expression]. Persisted per-id.
///
/// Scheduling is FSRS by default (ADR 0028): [stability] / [difficulty] are
/// the continuous memory parameters. Legacy SM-2 fields ([intervalDays],
/// [ease], [reps], [lapses]) are retained for display, exports, and migration.
///
/// **Mastery is not a discrete stage**: UI should use retrievability / mastery
/// score, not “passed box 4”.
/// [reps] counts total successful recalls (it is NOT reset on a lapse).
@freezed
abstract class SrsWord with _$SrsWord {
  const factory SrsWord({
    required String wordId,
    required DateTime dueAt,
    @Default(1) int intervalDays,
    @Default(2.5) double ease,
    @Default(0) int reps,
    @Default(0) int lapses,
    @Default(false) bool isLeech,
    /// Imported scheduling states that Anki intentionally keeps out of the
    /// ordinary due queue. They are explicit instead of being mislabelled as
    /// leeches, so the original state can be restored or inspected later.
    @Default(false) bool isSuspended,
    @Default(false) bool isBuried,
    @Default(SrsItemType.word) SrsItemType type,

    /// Wall-clock time of the most recent review (null for never-reviewed
    /// cards). Used with [stability] for \(R(t)\) without a DB join.
    DateTime? lastReviewedAt,

    /// FSRS memory stability \(S\) (days until predicted R ≈ 90%). Null until
    /// first FSRS review or SM-2→FSRS migration seed.
    double? stability,

    /// FSRS difficulty \(D\) in \[1, 10\]. Null until seeded.
    double? difficulty,

    /// FSRS learning state value: 1=learning, 2=review, 3=relearning.
    @Default(1) int fsrsState,

    /// FSRS learning/relearning step index (null when in pure review state).
    int? learningStep,
  }) = _SrsWord;

  factory SrsWord.fromJson(Map<String, dynamic> json) =>
      _$SrsWordFromJson(json);

  /// Factory for a never-seen item (due immediately).
  factory SrsWord.fresh(String wordId) => SrsWord(
        wordId: wordId,
        dueAt: DateTime.now(),
      );
}
