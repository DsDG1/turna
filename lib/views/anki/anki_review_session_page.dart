// Flutter imports:
import 'dart:async';
import 'dart:math';

// Package imports:
import 'package:auto_route/auto_route.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

// Project imports:
import 'package:varnamala/application/anki/anki_deck_manager.dart';
import 'package:varnamala/application/anki/anki_review_assembler.dart';
import 'package:varnamala/application/course_provider.dart';
import 'package:varnamala/application/game_provider.dart';
import 'package:varnamala/application/gems_provider.dart';
import 'package:varnamala/application/lesson_viewmodel.dart';
import 'package:varnamala/application/srs_provider.dart';
import 'package:varnamala/data/anki_import_dao.dart';
import 'package:varnamala/data/course_database.dart';
import 'package:varnamala/data/course_repository.dart';
import 'package:varnamala/di/injection.dart';
import 'package:varnamala/domain/course/interaction.dart';
import 'package:varnamala/l10n/app_localizations.dart';
import 'package:varnamala/service/locator.dart';
import 'package:varnamala/views/lesson/components/interactions/interaction_renderer.dart';
import 'package:varnamala/views/lesson/components/lesson_dialogs.dart';
import 'package:varnamala/views/lesson/components/lesson_stage_widgets.dart';
import 'package:varnamala/views/theme.dart';

/// Anki review session. Collects due Anki cards (optionally filtered by
/// [sectionId]) into a synthetic in-memory [Lesson] and plays it through the
/// shared [LessonViewModel]. Mirrors [MistakeReviewPage] in structure.
///
/// `recordMistakes` is `false` — wrong answers here must not create fresh
/// mistake entries (would pollute the mistake log). SRS grading still runs
/// via [LessonViewModel]'s submit path.
@RoutePage()
class AnkiReviewSessionPage extends StatefulWidget {
  /// Restrict the review to cards belonging to this Anki section, or `null`
  /// to review cards across all imported decks.
  final String? sectionId;

  const AnkiReviewSessionPage({super.key, this.sectionId});

  @override
  State<AnkiReviewSessionPage> createState() => _AnkiReviewSessionPageState();
}

class _AnkiReviewSessionPageState extends State<AnkiReviewSessionPage> {
  late final LessonViewModel _vm;
  late final AnkiDeckManager _deckManager;
  final Set<InteractionRenderer> _renderers =
      getIt<Set<InteractionRenderer>>();
  final Random _random = Random();

  /// Ids of interactions in the current batch that were new cards
  /// (reps == 0) when the batch was assembled — used for daily counters.
  final Set<String> _newCardInteractionIds = {};

  bool _empty = false;
  bool _dialogShown = false;
  bool _autoAdvanceScheduled = false;

  @override
  void initState() {
    super.initState();
    _vm = context.read<LessonViewModel>();
    _vm.addListener(_onVmChanged);
    _deckManager = AnkiDeckManager(
      repo: CourseRepository(getIt<CourseDatabase>()),
      srsProvider: context.read<SrsProvider>(),
      importDao: AnkiImportDao(getIt<CourseDatabase>()),
      appPrefs: getIt<AppPrefs>(),
    );
    WidgetsBinding.instance.addPostFrameCallback((_) => _start());
  }

  @override
  void dispose() {
    _vm.removeListener(_onVmChanged);
    super.dispose();
  }

  Future<void> _start() async {
    final courseProvider = context.read<CourseProvider>();
    final srsProvider = context.read<SrsProvider>();
    final assembler = AnkiReviewAssembler(srsProvider, courseProvider);
    final lesson = assembler.assembleBatch(
      sectionId: widget.sectionId,
      maxNew: _deckManager.newRemainingToday,
      maxReview: _deckManager.reviewRemainingToday,
    );

    if (!mounted) return;
    if (lesson == null) {
      setState(() => _empty = true);
      return;
    }
    final isEmpty = lesson.flattenedStages.every((s) => s.items.isEmpty);
    setState(() => _empty = isEmpty);
    if (!isEmpty) {
      // Snapshot which cards are new (reps == 0) before any grading mutates
      // SRS state — interaction id is 'anki-review-<wordId>'.
      for (final stage in lesson.flattenedStages) {
        for (final item in stage.items) {
          final wordId = item.id.replaceFirst('anki-review-', '');
          if ((srsProvider.state[wordId]?.reps ?? 0) == 0) {
            _newCardInteractionIds.add(item.id);
          }
        }
      }
      _vm.loadLessonInstance(lesson, recordMistakes: false);
    }
  }

  /// Count one graded card against today's new/review quotas.
  void _recordReview(Interaction interaction) {
    unawaited(_deckManager.recordCardReviewed(
      isNewCard: _newCardInteractionIds.contains(interaction.id),
    ));
  }

  void _onVmChanged() {
    if (!mounted) return;
    if (_vm.isComplete) {
      _showCompletionDialog();
      return;
    }
    _handleAutoAdvance(_vm);
  }

  void _handleAutoAdvance(LessonViewModel vm) {
    if (_autoAdvanceScheduled) return;
    if (!vm.hasSubmitted) return;
    final interaction = vm.currentInteraction;
    if (interaction == null) return;
    final renderer = lookupRenderer(_renderers, interaction);
    if (!renderer.autoAdvance) return;

    _autoAdvanceScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _autoAdvanceScheduled = false;
        vm.advance();
      }
    });
  }

  Future<void> _showCompletionDialog() async {
    if (!mounted || _dialogShown) return;
    _dialogShown = true;

    final total = _vm.totalInteractionCount;
    final correct = _vm.correctAnswers;
    final wasPerfect = total > 0 && correct == total;
    final xpEarned = wasPerfect
        ? XPEvent.lessonComplete.base + XPEvent.perfectLesson.base
        : XPEvent.lessonComplete.base;
    final gemsEarned = wasPerfect
        ? GemEvent.lessonComplete.amount + GemEvent.perfectLesson.amount
        : GemEvent.lessonComplete.amount;

    await showLessonCompletionDialog(
      context: context,
      isMounted: () => mounted,
      correctCount: correct,
      incorrectCount: _vm.incorrectAnswers,
      totalCount: total,
      durationSeconds: _vm.durationSeconds,
      xpEarned: xpEarned,
      gemsEarned: gemsEarned,
      wasPerfect: wasPerfect,
      questionResults: _vm.questionResults,
      random: _random,
    );
    _dialogShown = false;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: VarnamalaTheme.scaffoldBg(context),
      appBar: _buildAppBar(context),
      body: _empty
          ? _buildEmpty()
          : Selector<LessonViewModel,
              (Interaction?, InteractionState, String?, bool, bool)>(
              selector: (context, vm) => (
                vm.currentInteraction,
                vm.currentInteractionState,
                vm.currentStageName,
                vm.hasSubmitted,
                vm.isAnswerCorrect,
              ),
              builder: (context, selected, _) {
                final vm = _vm;
                final interaction = selected.$1;
                if (interaction == null) {
                  return const Center(child: CircularProgressIndicator());
                }
                final renderer = lookupRenderer(_renderers, interaction);
                final showCheck = selected.$4 && !renderer.autoAdvance;
                return Column(
                  children: [
                    if (selected.$3 != null)
                      LessonStageBanner(
                        name: selected.$3!,
                        accent: VarnamalaTheme.leagueAmethyst,
                      ),
                    Expanded(
                      child: renderer.build(
                        interaction,
                        selected.$2,
                        (correct, {userAnswerText}) {
                          _recordReview(interaction);
                          vm.submitInteraction(correct,
                              userAnswerText: userAnswerText);
                        },
                      ),
                    ),
                    if (showCheck)
                      SafeArea(
                        child: Padding(
                          padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
                          child: LessonCheckButton(
                            label: selected.$5
                                ? AppLocalizations.of(context)!.commonContinue
                                : AppLocalizations.of(context)!.commonGotIt,
                            enabled: true,
                            onPressed: () => vm.advance(),
                          ),
                        ),
                      ),
                  ],
                );
              },
            ),
    );
  }

  PreferredSizeWidget _buildAppBar(BuildContext context) {
    return AppBar(
      backgroundColor: VarnamalaTheme.surfaceColor(context),
      elevation: 0,
      leading: IconButton(
        tooltip: AppLocalizations.of(context)!.commonClose,
        icon: Icon(
          Icons.close_rounded,
          color: VarnamalaTheme.textPrimaryColor(context),
        ),
        onPressed: () => Navigator.of(context).maybePop(),
      ),
      title: Text(
        AppLocalizations.of(context)!.ankiReviewTitle,
        style: TextStyle(
          fontSize: 16,
          fontWeight: FontWeight.w700,
          color: VarnamalaTheme.textPrimaryColor(context),
        ),
      ),
      centerTitle: true,
      bottom: _empty
          ? null
          : PreferredSize(
              preferredSize: const Size.fromHeight(4),
              child: Selector<LessonViewModel, double>(
                selector: (context, vm) => vm.progress,
                builder: (context, progress, _) => LinearProgressIndicator(
                  value: progress,
                  backgroundColor:
                      VarnamalaTheme.leagueAmethyst.withValues(alpha: 0.1),
                  valueColor: const AlwaysStoppedAnimation<Color>(
                      VarnamalaTheme.leagueAmethyst),
                ),
              ),
            ),
    );
  }

  Widget _buildEmpty() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.check_circle_outline_rounded,
              size: 64,
              color: VarnamalaTheme.success.withValues(alpha: 0.6),
            ),
            const SizedBox(height: 16),
            Text(
              AppLocalizations.of(context)!.ankiNoCardsDue,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                    color: VarnamalaTheme.textSecondaryColor(context),
                  ),
            ),
            const SizedBox(height: 16),
            TextButton(
              onPressed: () => Navigator.of(context).maybePop(),
              child: Text(AppLocalizations.of(context)!.commonBack),
            ),
          ],
        ),
      ),
    );
  }
}