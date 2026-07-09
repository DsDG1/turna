// match_provider.dart

// Dart imports:
import 'dart:async';
import 'dart:math';

// Flutter imports:
import 'package:flutter/foundation.dart';

// Package imports:
import 'package:injectable/injectable.dart';

// Project imports:
import 'package:words625/application/audio_controller.dart';
import 'package:words625/core/extensions.dart';
import 'package:words625/core/logger.dart';
import 'package:words625/di/injection.dart';
import 'package:words625/match_levels.dart';
import 'package:words625/service/locator.dart';

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
        notifyListeners();
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
    if (selectedEnglishWord != null && selectedTargetWord != null) {
      if (wordPairs![selectedEnglishWord!] == selectedTargetWord) {
        sessionScore += 2;
        currentRoundMatches += 1;
        _audioController.playRandomLevelUpSound();
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
        _audioController.playRandomErrorSound();
        selectedEnglishWord = null;
        selectedTargetWord = null;
        notifyListeners();
      }
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
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
