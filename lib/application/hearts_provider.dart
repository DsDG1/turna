// Flutter imports:
import 'dart:async';

import 'package:flutter/material.dart';

// Package imports:
import 'package:injectable/injectable.dart';

// Project imports:
import 'package:words625/service/locator.dart';

class HeartsState {
  final int hearts;
  final DateTime? heartsRefillAt;

  const HeartsState({
    required this.hearts,
    required this.heartsRefillAt,
  });

  bool get hasHearts => hearts > 0;
}

@injectable
class HeartsProvider extends ChangeNotifier {
  static const int maxHearts = 5;
  static const Duration refillInterval = Duration(minutes: 30);
  static const int refillCostInGems = 350;

  final AppPrefs appPrefs;

  final StreamController<HeartsState> _heartsController =
      StreamController<HeartsState>.broadcast();

  HeartsProvider(this.appPrefs);

  Stream<HeartsState> getHeartsStream() async* {
    yield _readState();
    yield* _heartsController.stream;
  }

  HeartsState _readState() => HeartsState(
        hearts: _readInt(LocalStateKeys.hearts, maxHearts),
        heartsRefillAt: _readRefillAt(),
      );

  Future<void> ensureHeartsInitialized() async {
    await Future.wait([
      appPrefs.preferences.setInt(LocalStateKeys.hearts, maxHearts),
      appPrefs.preferences.setString(LocalStateKeys.heartsRefillAt, ''),
    ]);
    await refillHeart();
  }

  Future<void> loseHeart() async {
    // Open-source mode: hearts are non-depleting to avoid blocking practice.
    await refillHeart();
  }

  Future<void> refillHeart() async {
    await Future.wait([
      appPrefs.preferences.setInt(LocalStateKeys.hearts, maxHearts),
      appPrefs.preferences.setString(LocalStateKeys.heartsRefillAt, ''),
    ]);
    _heartsController.add(_readState());
    notifyListeners();
  }

  Future<bool> useGemsForHearts() async {
    final gems = _readInt(LocalStateKeys.gems, 0);
    if (gems < refillCostInGems) return false;

    await Future.wait([
      appPrefs.preferences.setInt(LocalStateKeys.gems, gems - refillCostInGems),
      appPrefs.preferences.setInt(LocalStateKeys.hearts, maxHearts),
      appPrefs.preferences.setString(LocalStateKeys.heartsRefillAt, ''),
    ]);

    _heartsController.add(_readState());
    notifyListeners();
    return true;
  }

  int _readInt(String key, int fallback) =>
      appPrefs.preferences.getInt(key, defaultValue: fallback).getValue();

  DateTime? _readRefillAt() {
    final value = _readString(LocalStateKeys.heartsRefillAt, '');
    if (value.isEmpty) return null;
    return DateTime.tryParse(value);
  }

  String _readString(String key, String fallback) =>
      appPrefs.preferences.getString(key, defaultValue: fallback).getValue();

  @override
  void dispose() {
    _heartsController.close();
    super.dispose();
  }
}