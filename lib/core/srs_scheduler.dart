// Dart imports:
import 'dart:math';

// Project imports:
import 'package:varnamala/domain/course/srs_word.dart';

/// Abstraction over spaced-repetition scheduling algorithms.
///
/// Implementations must treat **mastery as continuous** (via
/// [retrievability] / [masteryScore]), not as a fixed N-stage graduation.
abstract class SrsScheduler {
  /// Apply a quality grade and return the updated card state.
  ///
  /// [quality] uses SuperMemo-style 0..5 (or FSRS-mapped binary grades from
  /// [ReviewGrade]). [random] may drive interval fuzz when supported.
  SrsWord review(SrsWord word, int quality, {DateTime? now, Random? random});

  /// Deterministic preview of the next interval in whole days (0 = same-day
  /// relearn / sub-day). Must not apply random fuzz.
  int previewIntervalDays(SrsWord word, int quality, {DateTime? now});

  /// Predicted probability of successful recall at [now] (0..1).
  double retrievability(SrsWord word, {DateTime? now});

  /// Continuous mastery signal in [0,1] for UI — **not** a discrete stage.
  double masteryScore(SrsWord word, {DateTime? now});
}
