// Flutter imports:
import 'package:flutter/foundation.dart';

// Package imports:
import 'package:injectable/injectable.dart';

/// Monotonic counter that tells review-data consumers when underlying data
/// actually changed (Plan 3 §16.5).
///
/// Bumped only by data-committing paths — review events inserted, cards
/// added/removed, sources imported/uninstalled — never by widget rebuilds or
/// provider notifications. Dashboard/insights caches key on it so statistics
/// can't go permanently stale, and page-opens with an unchanged revision can
/// serve the cached snapshot (stale-while-revalidate).
@lazySingleton
class ReviewDataRevision extends ChangeNotifier {
  int _value = 0;

  /// Current revision; starts at 0 and increases by 1 per bump.
  int get value => _value;

  void bump() {
    _value++;
    notifyListeners();
  }
}
