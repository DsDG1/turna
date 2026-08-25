// Dart imports:
import 'dart:async';

// Flutter imports:
import 'package:flutter/foundation.dart';

// Package imports:
import 'package:injectable/injectable.dart';

// Project imports:
import 'package:turna/application/game_provider.dart';
import 'package:turna/application/gems_provider.dart';
import 'package:turna/application/fun_lab_snapshot_service.dart';
import 'package:turna/service/locator.dart';

/// "Fun Lab" settings — joke cheat features persisted across launches.
///
/// Mirrors the [AccessibilityProvider] recipe: keys live in [LocalStateKeys],
/// reads happen in [_load], setters persist then notify.
///
/// [autoAnswer] is consumed by the lesson screen to auto-submit correct
/// answers. The one-shot cheat actions write directly to prefs then poke
/// [GameProvider.notifyListeners] so every widget watching GameProvider
/// rebuilds with the new values (ScoreProvider / GemsProvider both read
/// from prefs on each access, so no separate notification is needed).
@lazySingleton
class FunProvider extends ChangeNotifier {
  final AppPrefs _appPrefs;
  final GameProvider _gameProvider;
  final GemsProvider _gemsProvider;
  final FunLabSnapshotService _snapshotService;

  bool _autoAnswer = false;
  bool _allAchievementsUnlocked = false;
  bool _busy = false;
  bool _snapshotLoaded = false;
  FunLabSnapshotMeta? _snapshot;

  FunProvider(
    this._appPrefs,
    this._gameProvider,
    this._gemsProvider,
    this._snapshotService,
  ) {
    _load();
    unawaited(_loadSnapshot());
  }

  bool get autoAnswer => _autoAnswer;
  bool get allAchievementsUnlocked => _allAchievementsUnlocked;
  bool get isBusy => _busy;
  bool get snapshotLoaded => _snapshotLoaded;
  bool get hasSnapshot => _snapshot != null;
  FunLabSnapshotMeta? get snapshot => _snapshot;

  void _load() {
    _autoAnswer = _appPrefs.preferences
        .getBool(LocalStateKeys.funAutoAnswer, defaultValue: false)
        .getValue();
    if (!kDebugMode && _autoAnswer) {
      // Migration S2-M01 (Plan 2 §4.4): the cheat toggle must never survive
      // into a release/profile build. Force it off and persist so the stored
      // preference matches reality for a later debug run.
      _autoAnswer = false;
      _appPrefs.setBool(LocalStateKeys.funAutoAnswer, value: false);
    }
    _allAchievementsUnlocked = _appPrefs.preferences
        .getBool(
          LocalStateKeys.funAllAchievementsUnlocked,
          defaultValue: false,
        )
        .getValue();
  }

  Future<void> _loadSnapshot() async {
    try {
      _snapshot = await _snapshotService.loadMeta();
    } catch (_) {
      _snapshot = null;
    } finally {
      _snapshotLoaded = true;
      notifyListeners();
    }
  }

  Future<void> setAutoAnswer(bool value) async {
    if (value && !kDebugMode) return; // release builds can never re-enable it
    _autoAnswer = value;
    await _appPrefs.setBool(LocalStateKeys.funAutoAnswer, value: value);
    notifyListeners();
  }

  // ── One-shot cheat actions ──────────────────────────────────────────

  Future<void> createSnapshot() async {
    await _runBusy(() async {
      _snapshot = await _snapshotService.createSnapshot();
    });
  }

  Future<void> restoreSnapshot() async {
    _requireSnapshot();
    await _runBusy(() async {
      await _snapshotService.restoreSnapshot();
      _load();
      _snapshot = await _snapshotService.loadMeta();
    });
  }

  Future<void> deleteSnapshot() async {
    _requireSnapshot();
    await _runBusy(() async {
      await _snapshotService.deleteSnapshot();
      _snapshot = null;
    });
  }

  Future<int> countPostponableReviews() =>
      _snapshotService.countPostponableReviews();

  Future<int> postponeAllReviewsOneDay() async {
    _requireSnapshot();
    var affected = 0;
    await _runBusy(() async {
      affected = await _snapshotService.postponeAllActiveReviews(
        const Duration(days: 1),
      );
    });
    return affected;
  }

  /// Set total XP score to 99999. ScoreProvider reads directly from prefs
  /// (score_provider.dart:17), so notify on GameProvider is sufficient.
  Future<void> cheatMaxScore() async {
    _requireSnapshot();
    await _runBusy(() async {
      await _appPrefs.setInt(LocalStateKeys.score, 99999);
      _gameProvider.refreshFromPrefs();
    });
  }

  /// Set gems to 99999. GemsProvider reads from prefs on every access
  /// (gems_provider.dart:44).
  Future<void> cheatMaxGems() async {
    _requireSnapshot();
    await _runBusy(() async {
      await _gemsProvider.setGems(99999);
      _gameProvider.refreshFromPrefs();
    });
  }

  /// Display all profile achievements as complete without changing the real
  /// counters or pre-consuming XP/streak milestone rewards.
  Future<void> cheatUnlockAllAchievements() async {
    _requireSnapshot();
    await _runBusy(() async {
      _allAchievementsUnlocked = true;
      await _appPrefs.setBool(
        LocalStateKeys.funAllAchievementsUnlocked,
        value: true,
      );
    });
  }

  void _requireSnapshot() {
    if (_snapshot == null) throw StateError('Fun Lab snapshot required');
  }

  Future<void> _runBusy(Future<void> Function() action) async {
    if (_busy) return;
    _busy = true;
    notifyListeners();
    try {
      await action();
    } finally {
      _busy = false;
      notifyListeners();
    }
  }
}
