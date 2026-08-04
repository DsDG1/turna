// Dart imports:
import 'dart:async';

// Flutter imports:
import 'package:flutter/material.dart';

// Package imports:
import 'package:injectable/injectable.dart';

// Project imports:
import 'package:turna/service/locator.dart';

enum GemEvent {
  lessonComplete(5),
  perfectLesson(10),
  streakMilestone7(50),
  streakMilestone30(200),
  streakMilestone100(500),
  achievementUnlock(25),

  /// Flat gems for finishing one SRS word-review session.
  srsReviewSession(2),

  /// Flat gems for finishing one grammar-review session.
  grammarReviewSession(2);

  final int amount;
  const GemEvent(this.amount);
}

@lazySingleton
class GemsProvider extends ChangeNotifier {
  final AppPrefs appPrefs;

  final StreamController<int> _gemsController =
      StreamController<int>.broadcast();

  /// Serializes mutating gem writes so concurrent callers don't race on the
  /// read-modify-write cycle for [LocalStateKeys.gems]. Achievement unlocks,
  /// lesson-complete rewards, and review-session rewards all funnel through
  /// here.
  Future<void> _writeChain = Future.value();

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
  /// Concurrent [addGems] calls chain via [_writeChain] so two simultaneous
  /// `+10` writes cannot lose a delta to a clobbering last-write-wins race.
  Future<void> addGems(int amount) async {
    if (amount == 0) return;
    await _enqueueWrite(() async {
      final current = _readInt(LocalStateKeys.gems, 0);
      final next = current + amount;
      await appPrefs.preferences.setInt(LocalStateKeys.gems, next);
      _emit(next);
      notifyListeners();
    });
  }

  /// Absolute set (used by account reset). Still goes through [_writeChain]
  /// so it cannot interleave with a concurrent [addGems].
  Future<void> setGems(int value) async {
    final next = value < 0 ? 0 : value;
    await _enqueueWrite(() async {
      await appPrefs.preferences.setInt(LocalStateKeys.gems, next);
      _emit(next);
      notifyListeners();
    });
  }

  /// Current balance (prefs snapshot; may lag an in-flight write by one frame).
  int get balance => _readInt(LocalStateKeys.gems, 0);

  /// Deduct [amount] if the balance is sufficient. Serialized via [_writeChain]
  /// so concurrent spends cannot drive the balance negative.
  ///
  /// Returns `false` when [amount] is non-positive or the balance is too low.
  Future<bool> spendGems(int amount) async {
    if (amount <= 0) return false;
    final result = Completer<bool>();
    _writeChain = _writeChain.then((_) async {
      final current = _readInt(LocalStateKeys.gems, 0);
      if (current < amount) {
        if (!result.isCompleted) result.complete(false);
        return;
      }
      final next = current - amount;
      await appPrefs.preferences.setInt(LocalStateKeys.gems, next);
      _emit(next);
      notifyListeners();
      if (!result.isCompleted) result.complete(true);
    }).catchError((Object e) {
      assert(() {
        // ignore: avoid_print
        print('GemsProvider spendGems failed: $e');
        return true;
      }());
      if (!result.isCompleted) result.complete(false);
    });
    return result.future;
  }

  /// Publish the preference-backed balance after an external restore.
  void refreshFromPrefs() {
    final value = _readInt(LocalStateKeys.gems, 0);
    _emit(value);
    notifyListeners();
  }

  Future<void> _enqueueWrite(Future<void> Function() op) {
    _writeChain = _writeChain.then((_) => op()).catchError((Object e) {
      assert(() {
        // ignore: avoid_print
        print('GemsProvider write failed: $e');
        return true;
      }());
    });
    return _writeChain;
  }

  int _readInt(String key, int fallback) =>
      appPrefs.preferences.getInt(key, defaultValue: fallback).getValue();

  void _emit(int newValue) {
    _gemsController.add(newValue);
  }

  @override
  void dispose() {
    _gemsController.close();
    super.dispose();
  }
}
