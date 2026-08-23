// Dart imports:
import 'dart:math' as math;

/// Alert policy for the system-health state machine (Plan §15).
///
/// Score is an aggregation INPUT (severity ordering), never a button-driven
/// output: nothing in the UI may deduct points. Resolution comes from
/// system evidence (a passing self-check), and stale events expire by
/// themselves instead of waiting for the user to click anything.
abstract final class SystemHealthPolicy {
  /// A group counts toward the effective score while its last occurrence is
  /// inside this window.
  static const Duration activeWindow = Duration(hours: 24);

  /// An event with no recurrence for this long expires on its own.
  static const Duration autoExpireAfter = Duration(days: 7);

  static const int attentionThreshold = 10;
  static const int criticalThreshold = 40;

  /// Per-group score contribution within the active window.
  static const int warningGroupScore = 1;
  static const int errorGroupScore = 3;

  /// Severity for a decayed score. Groups with a `fatal` level pin the
  /// result to critical while they are inside the window.
  static int effectiveScore({
    required Iterable<({String level, int lastAt, int count})> groups,
    required int nowMillis,
  }) {
    var score = 0;
    var hasFatal = false;
    for (final group in groups) {
      final age = nowMillis - group.lastAt;
      // A group whose lastAt lies slightly in the future (clock skew
      // between log sources) counts as active.
      if (age > activeWindow.inMilliseconds) continue;
      if (group.level == 'fatal') {
        hasFatal = true;
        continue;
      }
      score += group.level == 'error' ? errorGroupScore : warningGroupScore;
    }
    if (hasFatal) return math.max(score, criticalThreshold);
    return score;
  }

  static bool shouldExpire({required int lastAt, required int nowMillis}) =>
      nowMillis - lastAt > autoExpireAfter.inMilliseconds;

  /// Whether an event whose score is [score] may auto-resolve after a
  /// passing self-check (Plan §15.4).
  static bool resolvesAtScore(int score) => score < attentionThreshold;
}
