/// Domain-level review outcome and rating grades decoupled from any specific
/// SRS scheduling algorithm (SM-2 or FSRS).
library;

/// Binary outcome used by objectively graded exercises and legacy review UI.
///
/// Imported Anki flip cards use [AnkiReviewRating] so their scheduling keeps
/// the official Again / Hard / Good / Easy distinction.
enum ReviewOutcome {
  /// Forgot / incorrect → FSRS Again.
  fail,

  /// Remembered / correct → FSRS Good.
  pass;

  /// Legacy SM-2 quality int still stored on [ReviewEvents.quality].
  int get quality {
    switch (this) {
      case ReviewOutcome.fail:
        return 1;
      case ReviewOutcome.pass:
        return 4;
    }
  }

  static ReviewOutcome fromCorrect(bool correct) =>
      correct ? ReviewOutcome.pass : ReviewOutcome.fail;

  static ReviewOutcome fromQuality(int quality) =>
      quality < 3 ? ReviewOutcome.fail : ReviewOutcome.pass;
}

/// The four official Anki answer buttons expressed as the scheduler's legacy
/// SM-2 quality values. Values 3/4/5 also preserve distinct Hard/Good/Easy
/// behavior when the app is configured to use SM-2 instead of FSRS.
enum AnkiReviewRating {
  again(1),
  hard(3),
  good(4),
  easy(5);

  final int quality;
  const AnkiReviewRating(this.quality);
}

/// 2-button flashcard labels — aliases of [ReviewOutcome].
///   unknown = fail (不认识)
///   known   = pass (认识)
enum ReviewGrade {
  unknown(1),
  known(4);

  final int sm2;
  const ReviewGrade(this.sm2);

  ReviewOutcome get outcome =>
      this == ReviewGrade.known ? ReviewOutcome.pass : ReviewOutcome.fail;

  static ReviewGrade fromOutcome(ReviewOutcome o) =>
      o == ReviewOutcome.pass ? ReviewGrade.known : ReviewGrade.unknown;
}
