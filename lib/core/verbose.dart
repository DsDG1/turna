/// Second-level verbosity gate for noisy debug logs (e.g. `AppPrefs` value
/// dumps). Defaults off. Flip to `true` in debug only when you need the full
/// payload of a noisy log.
///
/// Release builds never reach the gated call sites because callers guard on
/// [kDebugMode] first, so this flag has no effect in production.
library;

import 'package:flutter/foundation.dart' show kDebugMode;

class Very {
  /// When `true`, gated debug logs emit their full payload (e.g. prefs
  /// values). When `false` (default), they emit a trimmed form (e.g. key
  /// only) to cut noise and avoid potential data leakage in logs.
  static bool verbose = false;
}

/// Convenience: gated debug logs should only run in debug builds in the
/// first place.
bool get veryVerbose => kDebugMode && Very.verbose;