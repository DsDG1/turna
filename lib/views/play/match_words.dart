// match_words_page.dart

// Dart imports:
import 'dart:async';

// Flutter imports:
import 'package:flutter/material.dart';

// Package imports:
import 'package:auto_route/annotations.dart';
import 'package:provider/provider.dart';

// Project imports:
import 'package:turna/application/achievements/achievement_service.dart';
import 'package:turna/application/game_provider.dart';
import 'package:turna/application/match_provider.dart';
import 'package:turna/core/utils.dart';
import 'package:turna/di/injection.dart';
import 'package:turna/l10n/app_strings.dart';
import 'package:turna/views/theme.dart';

@RoutePage()
class MatchWordsPage extends StatefulWidget {
  const MatchWordsPage({Key? key}) : super(key: key);

  @override
  State<MatchWordsPage> createState() => _MatchWordsPageState();
}

class _MatchWordsPageState extends State<MatchWordsPage> {
  bool _gameOverHandled = false;
  late final MatchProvider _matchProvider;

  @override
  void initState() {
    super.initState();
    _matchProvider = context.read<MatchProvider>();

    WidgetsBinding.instance.addPostFrameCallback((_) {
      _matchProvider.initializeGame();
    });
  }

  @override
  void dispose() {
    // MatchProvider is a @lazySingleton, so its own dispose() is never called
    // by Provider. Stop the per-second timer here so it doesn't keep firing
    // (and burning CPU) after the user leaves the game.
    _matchProvider.pauseTimer();
    super.dispose();
  }

  Future<void> _handleGameOver(
    MatchProvider matchProvider,
    GameProvider gameProvider,
  ) async {
    if (_gameOverHandled) return;
    _gameOverHandled = true;
    await gameProvider.incrementScore(matchProvider.sessionScore);
    // XP changed -> let the achievement engine see the new total (match
    // games award XP outside the lesson/review completion flows).
    unawaited(
      getIt<AchievementService>().evaluateAndReward().catchError((Object e) {
        debugPrint('Achievement evaluate after match failed: $e');
      }),
    );

    if (!mounted) return;

    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => _MatchGameOverDialog(
        score: matchProvider.sessionScore,
        roundsCompleted: matchProvider.roundsCompleted,
        celebrationType: matchProvider.celebrationType,
        onPlayAgain: () {
          Navigator.of(context).pop();
          _gameOverHandled = false;
          context.read<MatchProvider>().initializeGame();
        },
        onClose: () {
          Navigator.of(context).pop();
          Navigator.of(context).pop();
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Consumer2<MatchProvider, GameProvider>(
      builder: (context, matchProvider, gameProvider, _) {
        if (matchProvider.isGameOver && !_gameOverHandled) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            _handleGameOver(matchProvider, gameProvider);
          });
        }

        return Scaffold(
          appBar: AppBar(
            title: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  AppStrings.playMatchMadness,
                  style: Theme.of(context).textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.w700,
                        color: TurnaTheme.leagueAmethyst,
                      ),
                ),
                ValueListenableBuilder<int>(
                  valueListenable: matchProvider.countdownNotifier,
                  builder: (context, seconds, _) {
                    return Text(
                      getFormattedTime(seconds),
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.w700,
                        color: seconds < 25
                            ? TurnaTheme.error
                            : TurnaTheme.brandTeal,
                      ),
                    );
                  },
                ),
              ],
            ),
            toolbarHeight: 60,
            backgroundColor: TurnaTheme.cardBg(context),
            elevation: 1.2,
          ),
          body: Stack(
            children: [
              Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  children: [
                    const SizedBox(height: 12),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        _TopChip(
                          icon: Icons.bolt_rounded,
                          label: AppStrings.playXpLabel(
                              matchProvider.sessionScore),
                          color: TurnaTheme.brandTeal,
                        ),
                        _TopChip(
                          icon: Icons.auto_awesome_rounded,
                          label: AppStrings.playRoundLabel(
                              matchProvider.roundsCompleted + 1),
                          color: TurnaTheme.leagueAmethyst,
                        ),
                      ],
                    ),
                    const SizedBox(height: 14),
                    Expanded(
                      child: Row(
                        children: [
                          WordListWidget(
                            words: matchProvider.englishWords,
                            selectedWord: matchProvider.selectedEnglishWord,
                            onWordSelected: matchProvider.selectEnglishWord,
                            selectedColor: TurnaTheme.brandSky,
                            borderColor: TurnaTheme.statCardBorder(context),
                            matchedWords: matchProvider.matchedWords,
                          ),
                          const SizedBox(width: 16),
                          WordListWidget(
                            words: matchProvider.targetWords,
                            selectedWord: matchProvider.selectedTargetWord,
                            onWordSelected: matchProvider.selectTargetWord,
                            selectedColor: TurnaTheme.successDark,
                            borderColor: TurnaTheme.statCardBorder(context),
                            matchedWords: matchProvider.matchedWords,
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 14),
                    Text(
                      AppStrings.playInfiniteRoundsNote,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: TurnaTheme.textHintColor(context),
                          ),
                    ),
                    const SizedBox(height: 8),
                    MatchCounter(
                      matchedCount: matchProvider.currentRoundMatches,
                      totalCount: matchProvider.matchesPerRound,
                    ),
                  ],
                ),
              ),
              if (matchProvider.isRoundTransitioning)
                Container(
                  color: TurnaTheme.scaffoldBg(context).withValues(alpha: 0.85),
                  alignment: Alignment.center,
                  child: const _RoundCompleteOverlay(),
                ),
            ],
          ),
        );
      },
    );
  }
}

class _RoundCompleteOverlay extends StatefulWidget {
  const _RoundCompleteOverlay();

  @override
  State<_RoundCompleteOverlay> createState() => _RoundCompleteOverlayState();
}

class _RoundCompleteOverlayState extends State<_RoundCompleteOverlay>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 550),
    )..forward();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return RepaintBoundary(
      child: ScaleTransition(
        scale: CurvedAnimation(parent: _controller, curve: Curves.elasticOut),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 14),
          decoration: BoxDecoration(
            color: TurnaTheme.cardBg(context),
            borderRadius: BorderRadius.circular(TurnaTheme.radiusLarge),
            border: Border.all(color: TurnaTheme.statCardBorder(context)),
            boxShadow: TurnaTheme.cardShadow,
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.celebration_rounded, color: TurnaTheme.brandTeal),
              SizedBox(width: 8),
              Text(
                AppStrings.playRoundComplete,
                style: TextStyle(fontWeight: FontWeight.w700),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class WordListWidget extends StatelessWidget {
  final List<String> words;
  final String? selectedWord;
  final Function(String) onWordSelected;
  final Color selectedColor;
  final Color borderColor;
  final Set<String> matchedWords;

  const WordListWidget({
    Key? key,
    required this.words,
    required this.selectedWord,
    required this.onWordSelected,
    required this.selectedColor,
    required this.borderColor,
    required this.matchedWords,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: RepaintBoundary(
        child: ListView.builder(
          itemCount: words.length,
          itemBuilder: (context, index) {
            final word = words[index];
            final isMatched = matchedWords.contains(word);
            final isSelected = selectedWord == word;
            return RepaintBoundary(
              child: GestureDetector(
                onTap: isMatched ? null : () => onWordSelected(word),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 250),
                  curve: Curves.easeInOut,
                  margin: isMatched
                      ? const EdgeInsets.symmetric(
                          vertical: 1.0, horizontal: 36.0)
                      : const EdgeInsets.symmetric(vertical: 6.0),
                  padding: isMatched
                      ? const EdgeInsets.all(4.0)
                      : const EdgeInsets.all(14.0),
                  height: isMatched ? 0 : 58,
                  decoration: BoxDecoration(
                    color:
                        isSelected ? selectedColor : TurnaTheme.cardBg(context),
                    borderRadius: BorderRadius.circular(12.0),
                    border: Border.all(
                      color: isSelected ? selectedColor : borderColor,
                    ),
                  ),
                  child: Center(
                    child: Text(
                      word,
                      style: isSelected
                          ? const TextStyle(
                              fontWeight: FontWeight.w700,
                              color: TurnaTheme.textOnPrimary,
                              fontSize: 17,
                            )
                          : TextStyle(
                              color: isMatched
                                  ? TurnaTheme.textHint
                                  : TurnaTheme.textPrimaryColor(context),
                              fontSize: 15,
                              fontWeight: FontWeight.w600,
                            ),
                    ),
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}

class MatchCounter extends StatelessWidget {
  final int matchedCount;
  final int totalCount;

  const MatchCounter({
    Key? key,
    required this.matchedCount,
    required this.totalCount,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return RepaintBoundary(
      child: AnimatedSwitcher(
        duration: const Duration(milliseconds: 260),
        transitionBuilder: (child, animation) {
          return ScaleTransition(scale: animation, child: child);
        },
        child: Text(
          AppStrings.playMatchCount(matchedCount, totalCount),
          key: ValueKey<int>(matchedCount),
          style: TextStyle(
            fontSize: 20,
            fontWeight: FontWeight.w700,
            color: TurnaTheme.textPrimaryColor(context),
          ),
        ),
      ),
    );
  }
}

class _TopChip extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;

  const _TopChip({
    required this.icon,
    required this.label,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(TurnaTheme.radiusRound),
      ),
      child: Row(
        children: [
          Icon(icon, size: 16, color: color),
          const SizedBox(width: 4),
          Text(
            label,
            style: TextStyle(
              color: color,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

class _MatchGameOverDialog extends StatefulWidget {
  final int score;
  final int roundsCompleted;
  final MatchCelebrationType celebrationType;
  final VoidCallback onPlayAgain;
  final VoidCallback onClose;

  const _MatchGameOverDialog({
    required this.score,
    required this.roundsCompleted,
    required this.celebrationType,
    required this.onPlayAgain,
    required this.onClose,
  });

  @override
  State<_MatchGameOverDialog> createState() => _MatchGameOverDialogState();
}

class _MatchGameOverDialogState extends State<_MatchGameOverDialog>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 650),
    )..forward();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final style = _celebrationStyle(widget.celebrationType);

    return Dialog(
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(TurnaTheme.radiusXLarge),
      ),
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            RepaintBoundary(
              child: ScaleTransition(
                scale: CurvedAnimation(
                  parent: _controller,
                  curve: Curves.elasticOut,
                ),
                child: Icon(style.$1, color: style.$2, size: 54),
              ),
            ),
            const SizedBox(height: 14),
            Text(
              style.$3,
              style: Theme.of(context).textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
            ),
            const SizedBox(height: 8),
            Text(
              AppStrings.playTimeUp(widget.roundsCompleted, widget.score),
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodyMedium,
            ),
            const SizedBox(height: 18),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: widget.onPlayAgain,
                child: Text(AppStrings.playPlayAgain),
              ),
            ),
            const SizedBox(height: 8),
            TextButton(
              onPressed: widget.onClose,
              child: Text(AppStrings.commonBack),
            ),
          ],
        ),
      ),
    );
  }

  (IconData, Color, String) _celebrationStyle(MatchCelebrationType type) {
    switch (type) {
      case MatchCelebrationType.sparkles:
        return (
          Icons.auto_awesome_rounded,
          TurnaTheme.leagueAmethyst,
          AppStrings.playBrilliantRun
        );
      case MatchCelebrationType.trophy:
        return (
          Icons.emoji_events_rounded,
          TurnaTheme.successDark,
          AppStrings.playChampionEnergy
        );
      case MatchCelebrationType.lightning:
        return (
          Icons.bolt_rounded,
          TurnaTheme.brandTeal,
          AppStrings.playLightningFast
        );
    }
  }
}
