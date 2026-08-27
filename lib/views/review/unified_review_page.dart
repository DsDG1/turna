import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:turna/application/achievements/achievement_service.dart';
import 'package:turna/application/audio_controller.dart';
import 'package:turna/application/game_provider.dart';
import 'package:turna/application/gems_provider.dart';
import 'package:turna/application/mistake_provider.dart';
import 'package:turna/application/review/review_session_controller.dart';
import 'package:turna/application/ai/ai_card_context_resolver.dart';
import 'package:turna/application/study_session/study_product_analytics.dart';
import 'package:turna/application/study_stats_provider.dart';
import 'package:turna/di/injection.dart';
import 'package:turna/domain/course/interaction.dart';
import 'package:turna/domain/course/mistake_entry.dart';
import 'package:turna/domain/review/recall_outcome.dart';
import 'package:turna/domain/review/review_item.dart';
import 'package:turna/domain/review/review_ledger.dart';
import 'package:turna/domain/review/review_ledger_resolver.dart';
import 'package:turna/domain/study/study_log.dart';
import 'package:turna/l10n/app_strings.dart';
import 'package:turna/views/ai/components/ai_card_explain_sheet.dart';
import 'package:turna/views/anki/anki_webview_sizing.dart';
import 'package:turna/views/review/components/binary_recall_bar.dart';
import 'package:turna/domain/anki/objective_outcome.dart';
import 'package:turna/views/review/components/study_card_surface.dart';
import 'package:turna/views/review/components/review_progress_header.dart';
import 'package:turna/views/review/components/unified_review_completion.dart';
import 'package:auto_route/auto_route.dart';
import 'package:turna/views/theme.dart';

/// Unified review page providing a single, consistent review experience for all card sources.
@RoutePage()
class UnifiedReviewPage extends StatefulWidget {
  final List<ReviewItem> items;
  final ReviewLedgerResolver ledgerResolver;
  final String? title;
  final Future<void> Function(ReviewItem item, RecallOutcome outcome)?
      onOutcomeRecorded;
  final Future<void> Function(ReviewEventReceipt receipt)? onOutcomeUndone;

  const UnifiedReviewPage({
    super.key,
    required this.items,
    required this.ledgerResolver,
    this.title,
    this.onOutcomeRecorded,
    this.onOutcomeUndone,
  });

  @override
  State<UnifiedReviewPage> createState() => _UnifiedReviewPageState();
}

class _UnifiedReviewPageState extends State<UnifiedReviewPage> {
  final AudioController _audioController = getIt<AudioController>();
  final String _gemSessionSequence =
      DateTime.now().microsecondsSinceEpoch.toString();
  late final ReviewSessionController _controller;
  final Map<String, String> _mistakeIdsBySchedulingKey = {};

  @override
  void initState() {
    super.initState();
    _controller = ReviewSessionController(
      items: widget.items,
      ledgerResolver: widget.ledgerResolver,
      onOutcomeRecorded: (item, outcome) async {
        await _onOutcomeRecorded(item, outcome);
        await widget.onOutcomeRecorded?.call(item, outcome);
      },
      onOutcomeUndone: (receipt) async {
        await _onOutcomeUndone(receipt);
        await widget.onOutcomeUndone?.call(receipt);
      },
      onSessionCompleted: _onSessionCompleted,
    );
    _controller.addListener(_onStateChanged);
  }

  void _onStateChanged() {
    if (mounted) setState(() {});
  }

  Future<void> _onOutcomeRecorded(
      ReviewItem item, RecallOutcome outcome) async {
    final receipt = _controller.lastReceipt;
    if (receipt != null) {
      StudyProductAnalytics.instance.recordEvent(
        eventId: receipt.eventId,
        outcome: outcome,
      );
    }
    if (outcome == RecallOutcome.forgotten) {
      try {
        final mp = context.read<MistakeProvider?>();
        final content = item.content;
        final term = content is StandardCourseCardContent
            ? content.frontText
            : item.schedulingKey.rawId;
        final translation =
            content is StandardCourseCardContent ? content.backText : '';

        final mistakeId = receipt?.eventId ??
            'review_${DateTime.now().microsecondsSinceEpoch}_${item.sessionItemId}';
        await mp?.record(
          MistakeEntry(
            id: mistakeId,
            lessonId: 'srs-review',
            stageId: 'stage-review',
            interactionId: item.sessionItemId,
            wordId: item.schedulingKey.rawId,
            interactionSnapshot: Interaction.ankiCard(
              id: item.sessionItemId,
              front: term,
              back: translation,
            ),
            userAnswer: AppStrings.reviewBinaryForgotten,
            correctAnswer: translation,
            timestamp: DateTime.now(),
          ),
        );
        _mistakeIdsBySchedulingKey[item.schedulingKey.rawId] = mistakeId;
      } catch (_) {}
    }
  }

  Future<void> _onOutcomeUndone(ReviewEventReceipt receipt) async {
    StudyProductAnalytics.instance.forget(receipt.eventId);
    final mistakeId =
        _mistakeIdsBySchedulingKey.remove(receipt.schedulingKey.rawId);
    if (mistakeId == null) return;
    final mistakes = context.read<MistakeProvider?>();
    await mistakes?.removeByIds({mistakeId});
  }

  Future<void> _onSessionCompleted(int remembered, int forgotten) async {
    final total = remembered + forgotten;
    if (total == 0) return;

    try {
      final study = context.read<StudyStatsProvider?>();
      final game = context.read<GameProvider?>();
      final gems = context.read<GemsProvider?>();
      final achievements = getIt<AchievementService>();

      var xp = 15;
      if (game != null) {
        xp = await game.awardXP(
          XPEvent.srsReviewSession,
          multiplier: total.toDouble(),
        );
      }
      if (gems != null) {
        await gems.earnGems(
          GemEvent.srsReviewSession,
          eventId: GemRewardEventIds.reviewSession(
            kind: 'srs',
            completedAt: DateTime.now(),
            sessionSequence: _gemSessionSequence,
          ),
        );
      }
      if (study != null) {
        await study.recordActivity(
          type: StudyActivityType.srsReview,
          xpEarned: xp,
          durationSeconds: _controller.elapsed.inSeconds,
          correctCount: remembered,
          incorrectCount: forgotten,
        );
      }
      // Achievement evaluation after every authoritative write above; the
      // per-card delta feeds the durable totalReviewedCards projection.
      await achievements.recordReviewSession(cardsAnswered: total);
    } catch (_) {}
  }

  @override
  void dispose() {
    _controller.removeListener(_onStateChanged);
    _controller.dispose();
    super.dispose();
  }

  void _speakText(String text) {
    if (text.isEmpty) return;
    _audioController.speak(text);
  }

  void _openAiTutor() {
    final item = _controller.currentItem;
    if (item == null) return;
    // Unified AI card context (Plan 3 §20): sanitized plaintext only, and
    // the answer enters the prompt only after the learner revealed it —
    // never a raw scheduling id for Official template cards.
    final context_ = const AiCardContextResolver().resolve(
      item,
      answerRevealed: _controller.isRevealed,
      language: 'tr',
    );
    if (!context_.supported) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(AppStrings.aiCardExplainUnsupported)),
      );
      return;
    }
    showAiCardExplainSheet(
      context,
      cardContext: context_,
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_controller.items.isEmpty) {
      return Scaffold(
        appBar: AppBar(
          title: Text(widget.title ?? AppStrings.reviewReviewAppBarTitle),
        ),
        body: Center(
          child: Text(
            AppStrings.reviewEmptyMessage,
            style: TextStyle(
              fontSize: 16,
              color: TurnaTheme.textSecondaryColor(context),
            ),
          ),
        ),
      );
    }

    if (_controller.isComplete) {
      return Scaffold(
        body: SafeArea(
          child: UnifiedReviewCompletion(
            totalCount: _controller.totalCount,
            rememberedCount: _controller.rememberedCount,
            forgottenCount: _controller.forgottenCount,
            elapsed: _controller.elapsed,
            onFinish: () => Navigator.of(context).maybePop(),
          ),
        ),
      );
    }

    final item = _controller.currentItem!;
    final content = item.content;
    final structured = content is StandardCourseCardContent &&
        content.interaction != null &&
        content.interaction is! AnkiCard &&
        content.interaction is! AnkiHtmlCard;

    return Scaffold(
      backgroundColor: TurnaTheme.scaffoldBg(context),
      appBar: ReviewProgressHeader(
        progress: _controller.progress,
        currentIndex: _controller.currentIndex + 1,
        totalCount: _controller.totalCount,
        onBack: () => Navigator.of(context).maybePop(),
        onAiExplain: _openAiTutor,
        onUndo: () async {
          final ok = await _controller.undoLast();
          if (!ok || !context.mounted) return;
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('已撤销上一张评分'),
              duration: Duration(seconds: 2),
            ),
          );
        },
        canUndo: _controller.lastReceipt != null && !_controller.isSubmitting,
      ),
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            // Responsive page chrome: padding and the card/action gap shrink
            // on short screens and center within 760dp on tablets
            // (WEBVIEW-UX-2026-08 §6.2).
            final mq = MediaQuery.of(context);
            final sizing = resolveAnkiWebViewSizing(
              AnkiWebViewSizingInput(
                viewport: Size(constraints.maxWidth, constraints.maxHeight),
                orientation: mq.orientation,
                scene: AnkiWebViewScene.review,
              ),
            );
            return Padding(
              padding: EdgeInsets.symmetric(
                horizontal: sizing.horizontalPadding,
                vertical: 16,
              ),
              child: Column(
                children: [
                  Expanded(
                    child: StudyCardSurface(
                      content: content,
                      isRevealed: _controller.isRevealed,
                      onReveal: _controller.reveal,
                      onSpeak: content is StandardCourseCardContent
                          ? () => _speakText(content.frontText)
                          : null,
                      onObjectiveResult: structured
                          ? (correct) {
                              _controller.reveal();
                              _controller.answer(
                                objectiveRecallOutcome(correct: correct),
                              );
                            }
                          : null,
                      generation: _controller.currentIndex,
                    ),
                  ),
                  SizedBox(height: sizing.bottomGap),
                  if (_controller.lastError != null) ...[
                    Text(
                      '当前卡片无法安全写入，请重试或稍后返回。',
                      key: const Key('unified-review-error'),
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        color: TurnaTheme.error,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 12),
                  ] else if (_controller.sideEffectWarning != null) ...[
                    Text(
                      '复习已保存，统计稍后同步。',
                      key: const Key('unified-review-side-effect-warning'),
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: TurnaTheme.textSecondaryColor(context),
                      ),
                    ),
                    const SizedBox(height: 12),
                  ],
                  if (structured)
                    const SizedBox.shrink()
                  else if (!_controller.isRevealed)
                    SizedBox(
                      width: double.infinity,
                      height: 52,
                      child: ElevatedButton(
                        onPressed: _controller.isSubmitting
                            ? null
                            : _controller.reveal,
                        // styleFrom treats elevation as a base level (pressed: +6); pin all states flat.
                        style: ElevatedButton.styleFrom(
                          backgroundColor: TurnaTheme.brandTeal,
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(16),
                          ),
                        ).copyWith(
                            elevation: const WidgetStatePropertyAll<double>(0)),
                        child: Text(
                          AppStrings.lessonShowAnswer,
                          style: const TextStyle(
                            fontWeight: FontWeight.w700,
                            fontSize: 16,
                          ),
                        ),
                      ),
                    )
                  else
                    BinaryRecallBar(
                      onOutcome: _controller.answer,
                      forgottenPreview: _controller.forgottenPreview,
                      rememberedPreview: _controller.rememberedPreview,
                      enabled: !_controller.isSubmitting &&
                          _controller.lastError == null,
                    ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }
}
