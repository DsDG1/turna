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
import 'package:varnamala/views/play/match_levels.dart';
import 'package:varnamala/service/locator.dart';

@lazySingleton
class MatchProvider extends ChangeNotifier {
  final AudioController _audioController;
  final AppPrefs _appPrefs;
  final Random _random = Random();

  MatchProvider(this._audioController, this._appPrefs);

  List<String> _englishWords = [];
  List<String> _targetWords = [];
  Map<String, String> _matchedPairs = {};
  String? _selectedEnglishWord;
  String? _selectedTargetWord;
  Timer? _timer;
  int _secondsRemaining = 90;

  /// Per-second countdown exposed as a [ValueListenable] so the timer text in
  /// the app bar can rebuild in isolation (via [ValueListenableBuilder])
  /// instead of triggering a whole-screen [notifyListeners] every second.
  final ValueNotifier<int> countdownNotifier = ValueNotifier<int>(90);
  Set<String> _matchedWords = {};
  Map<String, String>? _wordPairs;
  bool _isGameOver = false;
  int _sessionScore = 0;
  int _roundsCompleted = 0;
  int _currentRoundMatches = 0;
  bool _isRoundTransitioning = false;
  MatchCelebrationType _celebrationType = MatchCelebrationType.sparkles;
  final int _matchesPerRound = 8;
  List<MapEntry<String, String>> _dictionaryEntries = [];

  // ── Read-only surface ──────────────────────────────────────────────
  List<String> get englishWords => _englishWords;
  List<String> get targetWords => _targetWords;
  Map<String, String> get matchedPairs => _matchedPairs;
  String? get selectedEnglishWord => _selectedEnglishWord;
  String? get selectedTargetWord => _selectedTargetWord;
  Set<String> get matchedWords => _matchedWords;
  Map<String, String>? get wordPairs => _wordPairs;
  bool get isGameOver => _isGameOver;
  int get sessionScore => _sessionScore;
  int get roundsCompleted => _roundsCompleted;
  int get currentRoundMatches => _currentRoundMatches;
  bool get isRoundTransitioning => _isRoundTransitioning;
  MatchCelebrationType get celebrationType => _celebrationType;
  int get matchesPerRound => _matchesPerRound;

  /// Re-entry guard for [checkMatch]. The method awaits an animation/sound
  /// delay between matching the pair and clearing the selection; without this,
  /// rapid taps that fire a second `checkMatch` mid-await would match against
  /// the stale selection and double-count the score.
  bool _checking = false;

  void initializeGame() {
    final targetLanguage =
        _appPrefs.currentLanguage.getValue().getEnumValue();
    // Single-language build: always use the target-language dictionary regardless of
    // the stored preference value (which only ever resolves to turkish now).
    _dictionaryEntries = allLevel1Words.entries.toList(growable: false);
    logger.i("Match game starting for $targetLanguage");

    _setupRound();
    _matchedPairs = {};
    _selectedEnglishWord = null;
    _selectedTargetWord = null;
    _secondsRemaining = 90;
    countdownNotifier.value = 90;
    _matchedWords = {};
    _isGameOver = false;
    _sessionScore = 0;
    _roundsCompleted = 0;
    _currentRoundMatches = 0;
    _isRoundTransitioning = false;
    _celebrationType = MatchCelebrationType.values[Random().nextInt(
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
      if (_secondsRemaining > 0) {
        _secondsRemaining--;
        countdownNotifier.value = _secondsRemaining;
      } else {
        _timer?.cancel();
        _isGameOver = true;
        _celebrationType = MatchCelebrationType.values[Random().nextInt(
          MatchCelebrationType.values.length,
        )];
        notifyListeners();
      }
    });
  }

  void selectEnglishWord(String word) {
    if (_isRoundTransitioning || _isGameOver) return;
    _selectedEnglishWord = word;
    checkMatch();
    notifyListeners();
  }

  void selectTargetWord(String word) {
    if (_isRoundTransitioning || _isGameOver) return;
    _selectedTargetWord = word;
    checkMatch();
    notifyListeners();
  }

  Future<void> checkMatch() async {
    if (_checking) return; // a previous match is still animating
    if (_selectedEnglishWord == null || _selectedTargetWord == null) return;
    final pairs = _wordPairs;
    if (pairs == null) return; // game not initialized / disposed

    _checking = true;
    try {
      if (pairs[_selectedEnglishWord!] == _selectedTargetWord) {
        _sessionScore += 2;
        _currentRoundMatches += 1;
        await _audioController.playRandomLevelUpSound();
        _matchedPairs[_selectedEnglishWord!] = _selectedTargetWord!;
        notifyListeners();

        // Wait for animation
        await Future.delayed(const Duration(milliseconds: 500));

        final matchedEnglish = _selectedEnglishWord!;
        final matchedTarget = _selectedTargetWord!;
        _replaceMatchedPair(matchedEnglish, matchedTarget);
        _selectedEnglishWord = null;
        _selectedTargetWord = null;

        if (_currentRoundMatches >= _matchesPerRound) {
          _roundsCompleted += 1;
          await _loadNextRound();
        }

        notifyListeners();
      } else {
        await _audioController.playRandomErrorSound();
        _selectedEnglishWord = null;
        _selectedTargetWord = null;
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
    _wordPairs = getRandomWords(8);
    _englishWords = _wordPairs!.keys.toList()..shuffle();
    _targetWords = _wordPairs!.values.toList()..shuffle();

    logger.i("Word Pairs: $_wordPairs");
    logger.i("English Words: $_englishWords");
    logger.i("Target Words: $_targetWords");
  }

  Future<void> _loadNextRound() async {
    _isRoundTransitioning = true;
    notifyListeners();

    await Future.delayed(const Duration(milliseconds: 650));
    _matchedPairs.clear();
    _currentRoundMatches = 0;
    _isRoundTransitioning = false;
    notifyListeners();
  }

  void _replaceMatchedPair(String english, String target) {
    _englishWords.remove(english);
    _targetWords.remove(target);
    _wordPairs?.remove(english);

    final replacement = _drawReplacementPair();
    _wordPairs?[replacement.key] = replacement.value;
    _englishWords.add(replacement.key);
    _targetWords.add(replacement.value);
    _englishWords.shuffle(_random);
    _targetWords.shuffle(_random);
  }

  MapEntry<String, String> _drawReplacementPair() {
    final englishInPlay = _englishWords.toSet();
    final targetInPlay = _targetWords.toSet();

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
