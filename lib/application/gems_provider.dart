// Flutter imports:
import 'dart:async';

import 'package:flutter/material.dart';

// Package imports:
import 'package:injectable/injectable.dart';

// Project imports:
import 'package:words625/service/locator.dart';

enum GemEvent {
  lessonComplete(5),
  perfectLesson(10),
  streakMilestone7(50),
  streakMilestone30(200),
  streakMilestone100(500),
  achievementUnlock(25),
  leaguePromotion(100),
  /// Flat gems for finishing one SRS word-review session.
  srsReviewSession(2),
  /// Flat gems for finishing one grammar-review session.
  grammarReviewSession(2);

  final int amount;
  const GemEvent(this.amount);
}

enum CommunityAction {
  follow(40),
  validatedShare(75);

  final int reward;
  const CommunityAction(this.reward);
}

@lazySingleton
class GemsProvider extends ChangeNotifier {
  final AppPrefs appPrefs;

  final StreamController<int> _gemsController =
      StreamController<int>.broadcast();

  GemsProvider(this.appPrefs);

  Stream<int> getGemsStream() async* {
    yield _readInt(LocalStateKeys.gems, 0);
    yield* _gemsController.stream;
  }

  Future<void> ensureGemsInitialized() async {
    // ensureUserGameFields already initializes `gems = 0`. Nothing to do.
  }

  Future<void> earnGems(GemEvent event) async {
    await addGems(event.amount);
  }

  /// Single writer entry for gem balance (achievement unlocks, spends, etc.).
  Future<void> addGems(int amount) async {
    if (amount == 0) return;
    final current = _readInt(LocalStateKeys.gems, 0);
    final next = current + amount;
    await appPrefs.preferences.setInt(LocalStateKeys.gems, next);
    _emit(next);
    notifyListeners();
  }

  Future<bool> claimCommunityReward(CommunityAction action) async {
    final gems = _readInt(LocalStateKeys.gems, 0);
    final updates = <String, Object?>{};

    switch (action) {
      case CommunityAction.follow:
        final alreadyClaimed =
            _readBool(LocalStateKeys.followRewardClaimed, false);
        if (alreadyClaimed) return false;
        updates[LocalStateKeys.followRewardClaimed] = true;
        break;
      case CommunityAction.validatedShare:
        final validated = _readInt(LocalStateKeys.validatedShareCount, 0);
        final claimed = _readInt(LocalStateKeys.claimedShareCount, 0);
        if (validated <= claimed) return false;
        updates[LocalStateKeys.claimedShareCount] = claimed + 1;
        break;
    }

    updates[LocalStateKeys.gems] = gems + action.reward;

    for (final entry in updates.entries) {
      final key = entry.key;
      final value = entry.value;
      if (value is int) {
        await appPrefs.preferences.setInt(key, value);
      } else if (value is bool) {
        await appPrefs.preferences.setBool(key, value);
      }
    }

    _emit(gems + action.reward);
    notifyListeners();
    return true;
  }

  int _readInt(String key, int fallback) =>
      appPrefs.preferences.getInt(key, defaultValue: fallback).getValue();

  bool _readBool(String key, bool fallback) =>
      appPrefs.preferences.getBool(key, defaultValue: fallback).getValue();

  void _emit(int newValue) {
    _gemsController.add(newValue);
  }

  @override
  void dispose() {
    _gemsController.close();
    super.dispose();
  }
}