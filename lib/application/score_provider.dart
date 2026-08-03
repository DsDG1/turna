// Flutter imports:
import 'package:flutter/foundation.dart';

// Package imports:
import 'package:injectable/injectable.dart';

// Project imports:
import 'package:turna/service/locator.dart';

/// Owns total XP score persistence ([LocalStateKeys.score]).
@lazySingleton
class ScoreProvider extends ChangeNotifier {
  ScoreProvider(this.appPrefs);

  final AppPrefs appPrefs;

  int get score =>
      appPrefs.preferences.getInt(LocalStateKeys.score, defaultValue: 0).getValue();

  Future<void> setScore(int value) async {
    await appPrefs.preferences.setInt(LocalStateKeys.score, value);
    notifyListeners();
  }

  Future<int> addScore(int xp) async {
    if (xp <= 0) return 0;
    final next = score + xp;
    await setScore(next);
    return xp;
  }
}
