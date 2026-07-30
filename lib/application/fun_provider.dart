// Flutter imports:
import 'package:flutter/material.dart';

// Package imports:
import 'package:injectable/injectable.dart';

// Project imports:
import 'package:varnamala/application/game_provider.dart';
import 'package:varnamala/core/achievement_config.dart';
import 'package:varnamala/service/locator.dart';

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

  bool _autoAnswer = false;

  FunProvider(this._appPrefs, this._gameProvider) {
    _load();
  }

  bool get autoAnswer => _autoAnswer;

  void _load() {
    _autoAnswer = _appPrefs.preferences
        .getBool(LocalStateKeys.funAutoAnswer, defaultValue: false)
        .getValue();
  }

  Future<void> setAutoAnswer(bool value) async {
    _autoAnswer = value;
    await _appPrefs.setBool(LocalStateKeys.funAutoAnswer, value: value);
    notifyListeners();
  }

  // ── One-shot cheat actions ──────────────────────────────────────────

  /// Set total XP score to 99999. ScoreProvider reads directly from prefs
  /// (score_provider.dart:17), so notify on GameProvider is sufficient.
  Future<void> cheatMaxScore() async {
    await _appPrefs.setInt(LocalStateKeys.score, 99999);
    _gameProvider.notifyListeners();
  }

  /// Set gems to 99999. GemsProvider reads from prefs on every access
  /// (gems_provider.dart:44).
  Future<void> cheatMaxGems() async {
    await _appPrefs.setInt(LocalStateKeys.gems, 99999);
    _gameProvider.notifyListeners();
  }

  /// Unlock every achievement milestone. AchievementConfig has separate
  /// `xp` and `streak` lists (achievement_config.dart:11-24); merge both.
  Future<void> cheatUnlockAllAchievements() async {
    final allIds = <String>[
      ...AchievementConfig.xp.map((m) => m.id),
      ...AchievementConfig.streak.map((m) => m.id),
    ];
    await _appPrefs.setStringList(LocalStateKeys.achievements, allIds);
    _gameProvider.notifyListeners();
  }
}