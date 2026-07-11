// match_provider.dart

// Dart imports:
import 'dart:async';
import 'dart:math';

// Flutter imports:
import 'package:flutter/foundation.dart';

// Package imports:
import 'package:injectable/injectable.dart';

// Project imports:
import 'package:varnamala/application/audio_controller.dart';
import 'package:varnamala/core/extensions.dart';
import 'package:varnamala/core/logger.dart';
import 'package:varnamala/di/injection.dart';
import 'package:varnamala/views/play/match_levels.dart';
import 'package:varnamala/service/locator.dart';

@lazySingleton
class MatchProvider extends ChangeNotifier {
  final AudioController _audioController;
  final Random _random = Random();

  MatchProvider(this._audioController);

  List<String> englishWords = [];
  List<String> targetWords = [];
  Map<String, String> matchedPairs = {};
  String? selectedEnglishWord;
  String? selectedTargetWord;
  Timer? _timer;
  int secondsRemaining = 90;
  /// Per-second countdown exposed as a [ValueListenable] so the timer text in
  /// the app bar can rebuild in isolation (via [ValueListenableBuilder])
  /// instead of triggering a whole-screen [notifyListeners] every second.
  final ValueNotifier<int> countdownNotifier = ValueNotifier<int>(90);
  Set<String> matchedWords = {};
  Map<String, String>? wordPairs;
  bool isGameOver = false;
  int sessionScore = 0;
  int roundsCompleted = 0;
  int currentRoundMatches = 0;
  bool isRoundTransitioning = false;
  MatchCelebrationType celebrationType = MatchCelebrationType.sparkles;
  int matchesPerRound = 8;
  List<MapEntry<String, String>> _dictionaryEntries = [];

  /// Re-entry guard for [checkMatch]. The method awaits an animation/sound
  /// delay between matching the pair and clearing the selection; without this,
  /// rapid taps that fire a second `checkMatch` mid-await would match against
  /// the stale selection and double-count the score.
  bool _checking = false;

  void initializeGame() {
    final targetLanguage =
        getIt<AppPrefs>().currentLanguage.getValue().getEnumValue();
    // Single-language build: always use Swahili dictionary regardless of
    // the stored preference value (which only ever resolves to swahili now).
    _dictionaryEntries = allLevel1Words.entries.toList(growable: false);
    logger.i("Match game starting for $targetLanguage");

    _setupRound();
    matchedPairs = {};
    selectedEnglishWord = null;
    selectedTargetWord = null;
    secondsRemaining = 90;
    countdownNotifier.value = 90;
    matchedWords = {};
    isGameOver = false;
    sessionScore = 0;
    roundsCompleted = 0;
    currentRoundMatches = 0;
    isRoundTransitioning = false;
    celebrationType = MatchCelebrationType.values[Random().nextInt(
      MatchCelebrationType.values.length,
    )];
    notifyListeners();

    startTimer();
  }

  Map<String, String> getRandomWords(int count) {
    final List<MapEntry<String, String>> entries = List.of(_dictionaryEntries);
    entries.shuffle(Random());
    return Map.fromEntries(entries.take(count));
  }

  void startTimer() {
    _timer?.cancel();
    _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (secondsRemaining > 0) {
        secondsRemaining--;
        countdownNotifier.value = secondsRemaining;
      } else {
        _timer?.cancel();
        isGameOver = true;
        celebrationType = MatchCelebrationType.values[Random().nextInt(
          MatchCelebrationType.values.length,
        )];
        notifyListeners();
      }
    });
  }

  void selectEnglishWord(String word) {
    if (isRoundTransitioning || isGameOver) return;
    selectedEnglishWord = word;
    checkMatch();
    notifyListeners();
  }

  void selectTargetWord(String word) {
    if (isRoundTransitioning || isGameOver) return;
    selectedTargetWord = word;
    checkMatch();
    notifyListeners();
  }

  Future<void> checkMatch() async {
    if (_checking) return; // a previous match is still animating
    if (selectedEnglishWord == null || selectedTargetWord == null) return;
    final pairs = wordPairs;
    if (pairs == null) return; // game not initialized / disposed

    _checking = true;
    try {
      if (pairs[selectedEnglishWord!] == selectedTargetWord) {
        sessionScore += 2;
        currentRoundMatches += 1;
        await _audioController.playRandomLevelUpSound();
        matchedPairs[selectedEnglishWord!] = selectedTargetWord!;
        notifyListeners();

        // Wait for animation
        await Future.delayed(const Duration(milliseconds: 500));

        final matchedEnglish = selectedEnglishWord!;
        final matchedTarget = selectedTargetWord!;
        _replaceMatchedPair(matchedEnglish, matchedTarget);
        selectedEnglishWord = null;
        selectedTargetWord = null;

        if (currentRoundMatches >= matchesPerRound) {
          roundsCompleted += 1;
          await _loadNextRound();
        }

        notifyListeners();
      } else {
        await _audioController.playRandomErrorSound();
        selectedEnglishWord = null;
        selectedTargetWord = null;
        notifyListeners();
      }
    } finally {
      _checking = false;
    }
  }

  /// Stop the countdown. Called from the match page's `dispose()` because this
  /// provider is a `@lazySingleton` (lives for the app lifetime) and would
  /// otherwise keep firing `notifyListeners` every second after the user leaves
  /// the game — wasting CPU and rebuilding any still-mounted listeners.
  void pauseTimer() {
    _timer?.cancel();
    _timer = null;
  }

  @override
  void dispose() {
    _timer?.cancel();
    countdownNotifier.dispose();
    super.dispose();
  }

  void _setupRound() {
    wordPairs = getRandomWords(8);
    englishWords = wordPairs!.keys.toList()..shuffle();
    targetWords = wordPairs!.values.toList()..shuffle();

    logger.i("Word Pairs: $wordPairs");
    logger.i("English Words: $englishWords");
    logger.i("Target Words: $targetWords");
  }

  Future<void> _loadNextRound() async {
    isRoundTransitioning = true;
    notifyListeners();

    await Future.delayed(const Duration(milliseconds: 650));
    matchedPairs.clear();
    currentRoundMatches = 0;
    isRoundTransitioning = false;
    notifyListeners();
  }

  void _replaceMatchedPair(String english, String target) {
    englishWords.remove(english);
    targetWords.remove(target);
    wordPairs?.remove(english);

    final replacement = _drawReplacementPair();
    wordPairs?[replacement.key] = replacement.value;
    englishWords.add(replacement.key);
    targetWords.add(replacement.value);
    englishWords.shuffle(_random);
    targetWords.shuffle(_random);
  }

  MapEntry<String, String> _drawReplacementPair() {
    final englishInPlay = englishWords.toSet();
    final targetInPlay = targetWords.toSet();

    final candidates = _dictionaryEntries.where((entry) {
      return !englishInPlay.contains(entry.key) &&
          !targetInPlay.contains(entry.value);
    }).toList(growable: false);

    if (candidates.isNotEmpty) {
      return candidates[_random.nextInt(candidates.length)];
    }

    // Fallback: if the dictionary is too small, still keep gameplay flowing.
    return _dictionaryEntries[_random.nextInt(_dictionaryEntries.length)];
  }
}

enum MatchCelebrationType {
  sparkles,
  trophy,
  lightning,
}
