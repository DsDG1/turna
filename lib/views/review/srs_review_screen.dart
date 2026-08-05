// Flutter imports:
import 'package:flutter/material.dart';

// Package imports:
import 'package:auto_route/annotations.dart';
import 'package:provider/provider.dart';

// Project imports:
import 'package:turna/application/audio_controller.dart';
import 'package:turna/application/game_provider.dart';
import 'package:turna/application/gems_provider.dart';
import 'package:turna/application/srs_provider.dart';
import 'package:turna/application/study_stats_provider.dart';
import 'package:turna/core/fsrs_engine.dart';
import 'package:turna/core/sm2.dart';
import 'package:turna/courses/languages/expressions.dart';
import 'package:turna/courses/languages/vocab.dart';
import 'package:turna/di/injection.dart';
import 'package:turna/domain/course/expression.dart';
import 'package:turna/domain/course/srs_word.dart';
import 'package:turna/domain/course/word_entry.dart';
import 'package:turna/domain/study/study_log.dart';
import 'package:turna/l10n/app_strings.dart';
import 'package:turna/views/ai/components/ai_card_explain_sheet.dart';
import 'package:turna/views/review/components/review_components.dart';
import 'package:turna/views/theme.dart';

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
      final words = srs.getDueWords();
      final expressions = srs.getDueExpressions();
      _queue = [...words, ...expressions]
        ..sort((a, b) => a.dueAt.compareTo(b.dueAt));
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
      await context.read<StudyStatsProvider>().recordActivity(
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

  void _onRate(ReviewGrade grade) async {
    if (_queue.isEmpty || _currentIndex >= _queue.length) return;

    final word = _queue[_currentIndex];
    final srs = context.read<SrsProvider>();
    if (word.type == SrsItemType.expression) {
      await srs.reviewExpression(word.wordId, grade.sm2);
    } else {
      await srs.reviewWithQuality(word.wordId, grade);
    }

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
    final dueCount = context.select((SrsProvider p) => p.dueCount);

    if (_queue.isEmpty) {
      return ReviewEmptyState(
        onRefresh: _loadQueue,
        dueCount: dueCount,
        title: AppStrings.reviewSrsTitle,
        emptyMessage: AppStrings.reviewEmptyMessage,
        dueMessage: AppStrings.reviewDueMessage,
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
        title: AppStrings.reviewSrsSessionComplete,
        completionMessage: AppStrings.reviewSrsCompletionMessage(_sessionCount),
      );
    }

    final word = _queue[_currentIndex];
    final wordEntry =
        word.type == SrsItemType.word ? vocabById[word.wordId] : null;
    final expression = word.type == SrsItemType.expression
        ? expressionsById[word.wordId]
        : null;

    return Scaffold(
      backgroundColor: TurnaTheme.scaffoldBg(context),
      appBar: AppBar(
        title: Text(AppStrings.reviewSrsAppBarTitle),
        actions: [
          IconButton(
            icon: const Icon(Icons.auto_awesome_rounded),
            tooltip: AppStrings.aiExplainCard,
            onPressed: () {
              final front =
                  wordEntry?.term ?? expression?.term ?? word.wordId;
              final back = wordEntry?.translation ?? expression?.translation;
              showAiCardExplainSheet(
                context,
                language: 'Turkish',
                front: front,
                back: back,
              );
            },
          ),
          IconButton(
            icon: Text(
              AppStrings.reviewSrsTtsSpeed(
                  _audioController.ttsSpeed.toStringAsFixed(1)),
              style: const TextStyle(
                fontWeight: FontWeight.w700,
                fontSize: 14,
              ),
            ),
            tooltip: AppStrings.reviewSrsTtsSpeedTooltip,
            onPressed: _cycleSpeed,
          ),
          Center(
            child: Padding(
              padding: const EdgeInsets.only(right: 16),
              child: Text(
                AppStrings.reviewSrsProgress(_currentIndex + 1, _queue.length),
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
                  wordEntry: wordEntry,
                  expression: expression,
                  showAnswer: _showAnswer,
                  onFlip: () => setState(() => _showAnswer = true),
                  onSpeak: () => _speak(
                      wordEntry?.term ?? expression?.term ?? word.wordId),
                ),
              ),
              const SizedBox(height: 24),
              if (_showAnswer) ...[
                if (word.isLeech) ...[
                  Text(
                    AppStrings.reviewLeechHint,
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: TurnaTheme.error,
                          fontWeight: FontWeight.w600,
                        ),
                  ),
                  const SizedBox(height: 8),
                ],
                ReviewRatingBar(
                  failPreview: () {
                    final eng = context.read<SrsProvider>().engine;
                    if (eng is FsrsEngine) {
                      final mins = eng.previewFailMinutes(word);
                      if (mins <= 0) return AppStrings.srsPreviewTomorrow;
                      return AppStrings.srsPreviewFailMinutes(mins);
                    }
                    return AppStrings.srsPreviewUnknown;
                  }(),
                  passPreview: () {
                    final days = context
                        .read<SrsProvider>()
                        .previewOutcomeDays(word, ReviewOutcome.pass);
                    return days <= 0
                        ? AppStrings.srsPreviewUnknown
                        : AppStrings.srsPreviewKnown(days);
                  }(),
                  onRate: _onRate,
                  prompt: AppStrings.reviewDoYouKnow,
                ),
              ] else ...[
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: () => setState(() => _showAnswer = true),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: TurnaTheme.brandTeal,
                      foregroundColor: TurnaTheme.textOnPrimary,
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      shape: RoundedRectangleBorder(
                        borderRadius:
                            BorderRadius.circular(TurnaTheme.radiusMedium),
                      ),
                    ),
                    child: Text(
                      AppStrings.reviewSrsShowAnswer,
                      style: const TextStyle(
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
  final WordEntry? wordEntry;
  final Expression? expression;
  final bool showAnswer;
  final VoidCallback onFlip;
  final VoidCallback onSpeak;

  const _FlashCard({
    required this.word,
    this.wordEntry,
    this.expression,
    required this.showAnswer,
    required this.onFlip,
    required this.onSpeak,
  });

  String get _term => wordEntry?.term ?? expression?.term ?? word.wordId;
  String get _translation =>
      wordEntry?.translation ?? expression?.translation ?? '';
  String? get _pronunciation =>
      wordEntry?.pronunciation ?? expression?.pronunciation;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: showAnswer ? null : onFlip,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(
          color: TurnaTheme.cardBg(context),
          borderRadius: BorderRadius.circular(TurnaTheme.radiusLarge),
          boxShadow: [
            BoxShadow(
              color: TurnaTheme.brandTeal.withValues(alpha: 0.08),
              blurRadius: 20,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            if (wordEntry != null || expression != null) ...[
              Text(
                _term,
                style: Theme.of(context).textTheme.displaySmall?.copyWith(
                      fontWeight: FontWeight.w800,
                      color: TurnaTheme.textPrimaryColor(context),
                    ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 16),
              IconButton(
                tooltip: AppStrings.reviewSrsPlayPronunciation,
                onPressed: onSpeak,
                icon: const Icon(Icons.volume_up_rounded),
                iconSize: 32,
                color: TurnaTheme.brandTeal,
              ),
              const SizedBox(height: 24),
              if (showAnswer) ...[
                const Divider(),
                const SizedBox(height: 16),
                Text(
                  _translation,
                  style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                        fontWeight: FontWeight.w700,
                        color: TurnaTheme.brandTeal,
                      ),
                  textAlign: TextAlign.center,
                ),
                if (_pronunciation?.isNotEmpty == true) ...[
                  const SizedBox(height: 8),
                  Text(
                    '/$_pronunciation/',
                    style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                          color: TurnaTheme.textSecondaryColor(context),
                        ),
                  ),
                ],
                const SizedBox(height: 16),
                Consumer<SrsProvider>(
                  builder: (context, srs, _) {
                    final lessonName = word.type == SrsItemType.expression
                        ? srs.getLessonNameForExpression(word.wordId)
                        : srs.getLessonNameForWord(word.wordId);
                    return Text(
                      lessonName != null
                          ? AppStrings.reviewSrsLearnedIn(lessonName)
                          : AppStrings.reviewSrsFirstSeen(word.wordId),
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: TurnaTheme.textHintColor(context),
                          ),
                    );
                  },
                ),
              ] else ...[
                Text(
                  AppStrings.reviewSrsTapToReveal,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: TurnaTheme.textHintColor(context),
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
                AppStrings.reviewSrsEntryNotFound,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: TurnaTheme.textHintColor(context),
                    ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
