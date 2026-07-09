// Flutter imports:
import 'package:flutter/material.dart';

// Package imports:
import 'package:auto_route/annotations.dart';
import 'package:provider/provider.dart';

// Project imports:
import 'package:words625/application/audio_controller.dart';
import 'package:words625/application/game_provider.dart';
import 'package:words625/application/gems_provider.dart';
import 'package:words625/application/srs_provider.dart';
import 'package:words625/application/study_stats_provider.dart';
import 'package:words625/core/sm2.dart';
import 'package:words625/courses/languages/kannada_vocab.dart';
import 'package:words625/di/injection.dart';
import 'package:words625/domain/course/srs_word.dart';
import 'package:words625/domain/course/word_entry.dart';
import 'package:words625/domain/study/study_log.dart';
import 'package:words625/views/review/components/review_components.dart';
import 'package:words625/views/theme.dart';

@RoutePage()
class SrsReviewPage extends StatefulWidget {
  const SrsReviewPage({super.key});

  @override
  State<SrsReviewPage> createState() => _SrsReviewPageState();
}

class _SrsReviewPageState extends State<SrsReviewPage> {
  final AudioController _audioController = getIt<AudioController>();
  bool _showAnswer = false;
  List<SrsWord> _queue = [];
  int _currentIndex = 0;
  int _sessionCount = 0;
  bool _rewardsGranted = false;
  int _xpEarned = 0;
  int _gemsEarned = 0;

  @override
  void initState() {
    super.initState();
    _loadQueue();
  }

  void _loadQueue() {
    final srs = context.read<SrsProvider>();
    setState(() {
      _queue = srs.getDueWords();
      _currentIndex = 0;
      _showAnswer = false;
      _sessionCount = 0;
      _rewardsGranted = false;
      _xpEarned = 0;
      _gemsEarned = 0;
    });
  }

  Future<void> _speak(String text) async {
    await _audioController.speak(text);
  }

  Future<void> _grantSessionRewards(int reviewedCount) async {
    if (_rewardsGranted || reviewedCount <= 0 || !mounted) return;
    _rewardsGranted = true;

    final game = context.read<GameProvider>();
    final gemsProvider = context.read<GemsProvider>();

    var xp = 0;
    try {
      xp = await game.awardXP(
        XPEvent.srsReviewSession,
        multiplier: reviewedCount.toDouble(),
      );
    } catch (e) {
      debugPrint('Error awarding SRS review XP: $e');
    }

    final gems = GemEvent.srsReviewSession.amount;
    try {
      await gemsProvider.earnGems(GemEvent.srsReviewSession);
    } catch (e) {
      debugPrint('Error earning SRS review gems: $e');
    }

    if (!mounted) return;
    setState(() {
      _xpEarned = xp;
      _gemsEarned = gems;
    });

    // Record study activity for statistics dashboard
    try {
      context.read<StudyStatsProvider>().recordActivity(
        type: StudyActivityType.srsReview,
        xpEarned: xp,
        durationSeconds: 0, // SRS sessions are quick; could add timer later
        correctCount: reviewedCount,
        incorrectCount: 0,
      );
    } catch (e) {
      debugPrint('Error recording SRS study stats: $e');
    }
  }

  void _onRate(ReviewQuality quality) async {
    if (_queue.isEmpty || _currentIndex >= _queue.length) return;

    final word = _queue[_currentIndex];
    await context.read<SrsProvider>().reviewWithQuality(word.wordId, quality);

    final nextIndex = _currentIndex + 1;
    final nextCount = _sessionCount + 1;
    setState(() {
      _sessionCount = nextCount;
      _showAnswer = false;
      _currentIndex = nextIndex;
    });

    if (nextIndex >= _queue.length) {
      await _grantSessionRewards(nextCount);
    }
  }

  void _cycleSpeed() {
    final speeds = <double>[0.8, 1.0, 1.2];
    final current = _audioController.ttsSpeed;
    final nextIndex = (speeds.indexOf(current) + 1) % speeds.length;
    _audioController.setTtsSpeed(speeds[nextIndex]);
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final dueCount = context.watch<SrsProvider>().dueCount;

    if (_queue.isEmpty) {
      return ReviewEmptyState(
        onRefresh: _loadQueue,
        dueCount: dueCount,
        title: 'Review',
        emptyMessage: 'You\'ve reviewed everything for now.',
        dueMessage: 'words are already due — pull to refresh',
      );
    }

    if (_currentIndex >= _queue.length) {
      return ReviewCompletionState(
        reviewedCount: _sessionCount,
        dueCount: dueCount,
        xpEarned: _xpEarned,
        gemsEarned: _gemsEarned,
        onDone: () => Navigator.of(context).pop(),
        onReviewMore: _loadQueue,
        title: 'Session Complete!',
        completionMessage: 'You reviewed $_sessionCount words.',
      );
    }

    final word = _queue[_currentIndex];
    final entry = swahiliVocabById[word.wordId];

    return Scaffold(
      backgroundColor: VarnamalaTheme.scaffoldBg(context),
      appBar: AppBar(
        title: const Text('Review'),
        actions: [
          IconButton(
            icon: Text(
              '${_audioController.ttsSpeed.toStringAsFixed(1)}x',
              style: const TextStyle(
                fontWeight: FontWeight.w700,
                fontSize: 14,
              ),
            ),
            tooltip: 'TTS speed',
            onPressed: _cycleSpeed,
          ),
          Center(
            child: Padding(
              padding: const EdgeInsets.only(right: 16),
              child: Text(
                '${_currentIndex + 1} / ${_queue.length}',
                style: const TextStyle(fontWeight: FontWeight.w700),
              ),
            ),
          ),
        ],
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            children: [
              Expanded(
                child: _FlashCard(
                  word: word,
                  entry: entry,
                  showAnswer: _showAnswer,
                  onFlip: () => setState(() => _showAnswer = true),
                  onSpeak: () => _speak(entry?.term ?? word.wordId),
                ),
              ),
              const SizedBox(height: 24),
              if (_showAnswer) ...[
                ReviewRatingBar(
                  onRate: _onRate,
                  prompt: 'How well did you know this?',
                ),
              ] else ...[
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: () => setState(() => _showAnswer = true),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: VarnamalaTheme.peacockTeal,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      shape: RoundedRectangleBorder(
                        borderRadius:
                            BorderRadius.circular(VarnamalaTheme.radiusMedium),
                      ),
                    ),
                    child: const Text(
                      'Show Answer',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _FlashCard extends StatelessWidget {
  final SrsWord word;
  final WordEntry? entry;
  final bool showAnswer;
  final VoidCallback onFlip;
  final VoidCallback onSpeak;

  const _FlashCard({
    required this.word,
    required this.entry,
    required this.showAnswer,
    required this.onFlip,
    required this.onSpeak,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: showAnswer ? null : onFlip,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(VarnamalaTheme.radiusLarge),
          boxShadow: [
            BoxShadow(
              color: VarnamalaTheme.peacockTeal.withValues(alpha: 0.08),
              blurRadius: 20,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            if (entry != null) ...[
              Text(
                entry!.term,
                style: Theme.of(context).textTheme.displaySmall?.copyWith(
                      fontWeight: FontWeight.w800,
                      color: VarnamalaTheme.textPrimary,
                    ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 16),
              IconButton(
                onPressed: onSpeak,
                icon: const Icon(Icons.volume_up_rounded),
                iconSize: 32,
                color: VarnamalaTheme.peacockTeal,
              ),
              const SizedBox(height: 24),
              if (showAnswer) ...[
                const Divider(),
                const SizedBox(height: 16),
                Text(
                  entry!.translation,
                  style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                        fontWeight: FontWeight.w700,
                        color: VarnamalaTheme.peacockTeal,
                      ),
                  textAlign: TextAlign.center,
                ),
                if (entry!.pronunciation?.isNotEmpty == true) ...[
                  const SizedBox(height: 8),
                  Text(
                    '/${entry!.pronunciation}/',
                    style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                          color: VarnamalaTheme.textSecondary,
                        ),
                  ),
                ],
                const SizedBox(height: 16),
                Consumer<SrsProvider>(
                  builder: (context, srs, _) {
                    final lessonName = srs.getLessonNameForWord(word.wordId);
                    return Text(
                      lessonName != null
                          ? 'Learned in: $lessonName'
                          : 'First seen: ${word.wordId}',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: VarnamalaTheme.textHint,
                          ),
                    );
                  },
                ),
              ] else ...[
                Text(
                  'Tap to reveal meaning',
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: VarnamalaTheme.textHint,
                      ),
                ),
              ],
            ] else ...[
              Text(
                word.wordId,
                style: Theme.of(context).textTheme.displaySmall?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
              ),
              const SizedBox(height: 16),
              Text(
                'Vocabulary entry not found',
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: VarnamalaTheme.textHint,
                    ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
