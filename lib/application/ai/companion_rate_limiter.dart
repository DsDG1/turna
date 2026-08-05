/// Simple local debounce / min-interval gate for companion AI surfaces.
///
/// Not a network rate limit — only prevents accidental double-taps and
/// rapid re-fires that burn tokens. Diagnosis keeps a longer interval.
class CompanionRateLimiter {
  CompanionRateLimiter({
    this.minInterval = const Duration(seconds: 2),
  });

  final Duration minInterval;
  final Map<String, DateTime> _last = <String, DateTime>{};

  /// Returns `true` if the call is allowed and records the timestamp.
  /// Returns `false` if too soon since the last allowed call for [key].
  bool tryAcquire(String key, {Duration? interval}) {
    final now = DateTime.now();
    final min = interval ?? minInterval;
    final last = _last[key];
    if (last != null && now.difference(last) < min) {
      return false;
    }
    _last[key] = now;
    return true;
  }

  /// Seconds remaining until [key] may fire again (0 if ready).
  int secondsRemaining(String key, {Duration? interval}) {
    final last = _last[key];
    if (last == null) return 0;
    final min = interval ?? minInterval;
    final left = min - DateTime.now().difference(last);
    if (left.isNegative) return 0;
    return left.inSeconds + (left.inMilliseconds % 1000 == 0 ? 0 : 1);
  }

  void reset([String? key]) {
    if (key == null) {
      _last.clear();
    } else {
      _last.remove(key);
    }
  }

  /// Well-known surface keys.
  static const hint = 'companion.hint';
  static const tutor = 'companion.tutor';
  static const dictionary = 'companion.dictionary';
  static const diagnosis = 'companion.diagnosis';
  static const cardExplain = 'companion.card';
  static const depth = 'companion.depth';
}
