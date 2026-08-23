// Flutter imports:
import 'package:flutter/material.dart';

// Package imports:
import 'package:auto_route/annotations.dart';
import 'package:provider/provider.dart';

// Project imports:
import 'package:turna/application/achievements/achievement_service.dart';
import 'package:turna/application/game_provider.dart';
import 'package:turna/application/gems_provider.dart';
import 'package:turna/application/grammar_review_provider.dart';
import 'package:turna/application/study_stats_provider.dart';
import 'package:turna/core/sm2.dart';
import 'package:turna/courses/languages/grammar_points.dart';
import 'package:turna/di/injection.dart';
import 'package:turna/domain/course/grammar_point.dart';
import 'package:turna/domain/course/interaction.dart';
import 'package:turna/domain/course/srs_word.dart';
import 'package:turna/domain/study/study_log.dart';
import 'package:turna/l10n/app_strings.dart';
import 'package:turna/views/lesson/components/interactions/interaction_renderer.dart';
import 'package:turna/views/review/components/review_components.dart';
import 'package:turna/views/theme.dart';

enum _GrammarCardPhase { explain, practice, rate }

@RoutePage()
class GrammarReviewPage extends StatefulWidget {
  const GrammarReviewPage({super.key});

  @override
  State<GrammarReviewPage> createState() => _GrammarReviewPageState();
}

class _GrammarReviewPageState extends State<GrammarReviewPage> {
  final Set<InteractionRenderer> _renderers = getIt<Set<InteractionRenderer>>();
  String _gemSessionSequence = DateTime.now().microsecondsSinceEpoch.toString();

  bool _showExplanation = false;
  List<SrsWord> _queue = [];
  int _currentIndex = 0;
  int _sessionCount = 0;
  _GrammarCardPhase _phase = _GrammarCardPhase.explain;
  int _practiceIndex = 0;
  bool _practiceSubmitted = false;
  bool? _practiceCorrect;
  bool _rewardsGranted = false;
  int _xpEarned = 0;
  int _gemsEarned = 0;

  @override
  void initState() {
    super.initState();
    _loadQueue();
  }

  void _loadQueue() {
    final grammar = context.read<GrammarReviewProvider>();
    setState(() {
      _gemSessionSequence = DateTime.now().microsecondsSinceEpoch.toString();
      _queue = grammar.getDueGrammarPoints();
      _currentIndex = 0;
      _sessionCount = 0;
      _showExplanation = false;
      _phase = _GrammarCardPhase.explain;
      _practiceIndex = 0;
      _practiceSubmitted = false;
      _practiceCorrect = null;
      _rewardsGranted = false;
      _xpEarned = 0;
      _gemsEarned = 0;
    });
  }

  void _resetCardState() {
    _showExplanation = false;
    _phase = _GrammarCardPhase.explain;
    _practiceIndex = 0;
    _practiceSubmitted = false;
    _practiceCorrect = null;
  }

  List<Interaction> _practiceFor(GrammarPoint? point) =>
      point?.practiceItems ?? const <Interaction>[];

  void _onRevealExplanation() {
    setState(() {
      _showExplanation = true;
      final point = _currentPoint;
      final items = _practiceFor(point);
      _phase =
          items.isEmpty ? _GrammarCardPhase.rate : _GrammarCardPhase.practice;
      _practiceIndex = 0;
      _practiceSubmitted = false;
      _practiceCorrect = null;
    });
  }

  void _onPracticeSubmit(
    bool correct, {
    String? userAnswerText,
    int? reviewQuality,
  }) {
    setState(() {
      _practiceSubmitted = true;
      _practiceCorrect = correct;
    });
  }

  void _onPracticeContinue() {
    final items = _practiceFor(_currentPoint);
    if (_practiceIndex + 1 < items.length) {
      setState(() {
        _practiceIndex++;
        _practiceSubmitted = false;
        _practiceCorrect = null;
      });
      return;
    }
    setState(() => _phase = _GrammarCardPhase.rate);
  }

  Future<void> _grantSessionRewards(int reviewedCount) async {
    if (_rewardsGranted || reviewedCount <= 0 || !mounted) return;
    _rewardsGranted = true;

    final game = context.read<GameProvider>();
    final gemsProvider = context.read<GemsProvider>();

    var xp = 0;
    try {
      xp = await game.awardXP(
        XPEvent.grammarReviewSession,
        multiplier: reviewedCount.toDouble(),
      );
    } catch (e) {
      debugPrint('Error awarding grammar review XP: $e');
    }

    final gems = GemEvent.grammarReviewSession.amount;
    try {
      await gemsProvider.earnGems(
        GemEvent.grammarReviewSession,
        eventId: GemRewardEventIds.reviewSession(
          kind: 'grammar',
          completedAt: DateTime.now(),
          sessionSequence: _gemSessionSequence,
        ),
      );
    } catch (e) {
      debugPrint('Error earning grammar review gems: $e');
    }

    if (!mounted) return;
    setState(() {
      _xpEarned = xp;
      _gemsEarned = gems;
    });

    // Record study activity for statistics dashboard
    try {
      await context.read<StudyStatsProvider>().recordActivity(
            type: StudyActivityType.grammarReview,
            xpEarned: xp,
            durationSeconds: 0,
            correctCount: reviewedCount,
            incorrectCount: 0,
          );
    } catch (e) {
      debugPrint('Error recording grammar study stats: $e');
    }

    // Achievement evaluation after the authoritative writes above.
    try {
      await getIt<AchievementService>()
          .recordReviewSession(cardsAnswered: reviewedCount);
    } catch (e) {
      debugPrint('Error evaluating achievements: $e');
    }
  }

  void _onRate(ReviewGrade grade) async {
    if (_queue.isEmpty || _currentIndex >= _queue.length) return;

    final item = _queue[_currentIndex];
    await context
        .read<GrammarReviewProvider>()
        .reviewWithQuality(item.wordId, grade);

    final nextIndex = _currentIndex + 1;
    final nextCount = _sessionCount + 1;
    setState(() {
      _sessionCount = nextCount;
      _currentIndex = nextIndex;
      _resetCardState();
    });

    if (nextIndex >= _queue.length) {
      await _grantSessionRewards(nextCount);
    }
  }

  GrammarPoint? get _currentPoint {
    if (_queue.isEmpty || _currentIndex >= _queue.length) return null;
    return grammarPointById[_queue[_currentIndex].wordId];
  }

  @override
  Widget build(BuildContext context) {
    final dueCount = context.select((GrammarReviewProvider p) => p.dueCount);

    if (_queue.isEmpty) {
      return ReviewEmptyState(
        onRefresh: _loadQueue,
        dueCount: dueCount,
        title: AppStrings.reviewGrammarReviewTitle,
        emptyMessage: AppStrings.reviewGrammarEmptyMessage,
        dueMessage: AppStrings.reviewGrammarDueMessage,
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
        title: AppStrings.reviewGrammarSessionComplete,
        completionMessage:
            AppStrings.reviewGrammarCompletionMessage(_sessionCount),
      );
    }

    final item = _queue[_currentIndex];
    final point = grammarPointById[item.wordId];
    final practiceItems = _practiceFor(point);

    return Scaffold(
      backgroundColor: TurnaTheme.scaffoldBg(context),
      appBar: AppBar(
        title: Text(AppStrings.reviewGrammarAppBarTitle),
        actions: [
          Center(
            child: Padding(
              padding: const EdgeInsets.only(right: 16),
              child: Text(
                AppStrings.reviewGrammarProgress(
                    _currentIndex + 1, _queue.length),
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
                child: _phase == _GrammarCardPhase.practice &&
                        practiceItems.isNotEmpty
                    ? _PracticePanel(
                        interaction: practiceItems[_practiceIndex],
                        renderers: _renderers,
                        submitted: _practiceSubmitted,
                        correct: _practiceCorrect,
                        onSubmit: _onPracticeSubmit,
                        progressLabel: AppStrings.reviewGrammarPracticeLabel(
                            _practiceIndex + 1, practiceItems.length),
                      )
                    : _GrammarCard(
                        word: item,
                        point: point,
                        showExplanation: _showExplanation,
                        onFlip: _onRevealExplanation,
                      ),
              ),
              const SizedBox(height: 24),
              if (_phase == _GrammarCardPhase.rate) ...[
                ReviewRatingBar(
                  failPreview: AppStrings.srsPreviewUnknown,
                  passPreview: () {
                    final days = context
                        .read<GrammarReviewProvider>()
                        .previewOutcomeDays(item, ReviewOutcome.pass);
                    return days <= 0
                        ? AppStrings.srsPreviewUnknown
                        : AppStrings.srsPreviewKnown(days);
                  }(),
                  onRate: _onRate,
                  prompt: AppStrings.reviewGrammarDoYouUnderstand,
                ),
              ] else if (_phase == _GrammarCardPhase.practice &&
                  _practiceSubmitted) ...[
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: _onPracticeContinue,
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
                      _practiceIndex + 1 < practiceItems.length
                          ? AppStrings.reviewGrammarNextPractice
                          : AppStrings.reviewGrammarRateGrammar,
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ),
              ] else if (_phase == _GrammarCardPhase.explain) ...[
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: _onRevealExplanation,
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
                      AppStrings.reviewGrammarShowExplanation,
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

class _PracticePanel extends StatelessWidget {
  final Interaction interaction;
  final Set<InteractionRenderer> renderers;
  final bool submitted;
  final bool? correct;
  final OnInteractionSubmit onSubmit;
  final String progressLabel;

  const _PracticePanel({
    required this.interaction,
    required this.renderers,
    required this.submitted,
    required this.correct,
    required this.onSubmit,
    required this.progressLabel,
  });

  @override
  Widget build(BuildContext context) {
    final renderer = lookupRenderer(renderers, interaction);
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
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
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            progressLabel,
            style: Theme.of(context).textTheme.labelLarge?.copyWith(
                  color: TurnaTheme.brandTeal,
                  fontWeight: FontWeight.w700,
                ),
          ),
          const SizedBox(height: 12),
          Expanded(
            child: renderer.build(
              interaction,
              InteractionState(
                submitted: submitted,
                correct: correct,
              ),
              submitted ? (_, {userAnswerText, reviewQuality}) {} : onSubmit,
            ),
          ),
        ],
      ),
    );
  }
}

class _GrammarCard extends StatelessWidget {
  final SrsWord word;
  final GrammarPoint? point;
  final bool showExplanation;
  final VoidCallback onFlip;

  const _GrammarCard({
    required this.word,
    required this.point,
    required this.showExplanation,
    required this.onFlip,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: showExplanation ? null : onFlip,
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
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (point != null) ...[
                Text(
                  point!.title,
                  style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                        fontWeight: FontWeight.w800,
                        color: TurnaTheme.textPrimaryColor(context),
                      ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 24),
                if (showExplanation) ...[
                  const Divider(),
                  const SizedBox(height: 16),
                  Text(
                    point!.explanation,
                    style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                          height: 1.5,
                          color: TurnaTheme.textPrimaryColor(context),
                        ),
                  ),
                  const SizedBox(height: 16),
                  Consumer<GrammarReviewProvider>(
                    builder: (context, grammar, _) {
                      final lessonName =
                          grammar.getLessonNameForGrammarPoint(word.wordId);
                      return Text(
                        lessonName != null
                            ? AppStrings.reviewGrammarLearnedIn(lessonName)
                            : AppStrings.reviewGrammarFirstSeen(word.wordId),
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                              color: TurnaTheme.textHintColor(context),
                            ),
                      );
                    },
                  ),
                ] else ...[
                  Text(
                    AppStrings.reviewGrammarTapToReveal,
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                          color: TurnaTheme.textHintColor(context),
                        ),
                    textAlign: TextAlign.center,
                  ),
                ],
              ] else ...[
                Text(
                  word.wordId,
                  style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 16),
                Text(
                  AppStrings.reviewGrammarPointNotFound,
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: TurnaTheme.textHintColor(context),
                      ),
                  textAlign: TextAlign.center,
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
