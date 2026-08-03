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
import 'package:varnamala/data/anki_note_dao.dart';
import 'package:varnamala/application/course_provider.dart';
import 'package:varnamala/application/game_provider.dart';
import 'package:varnamala/application/gems_provider.dart';
import 'package:varnamala/application/lesson_viewmodel.dart';
import 'package:varnamala/application/srs_provider.dart';
import 'package:varnamala/di/injection.dart';
import 'package:varnamala/domain/course/interaction.dart';
import 'package:varnamala/domain/course/srs_word.dart';
import 'package:varnamala/l10n/app_strings.dart';
import 'package:varnamala/views/lesson/components/interactions/interaction_renderer.dart';
import 'package:varnamala/views/lesson/components/lesson_dialogs.dart';
import 'package:varnamala/views/lesson/components/lesson_stage_widgets.dart';
import 'package:varnamala/views/theme.dart';

/// Anki review session. Collects due Anki cards (optionally filtered by
/// [sectionId]) into a synthetic in-memory [Lesson] and plays it through the
/// shared [LessonViewModel]. Mirrors [MistakeReviewPage] in structure.
///
/// `recordMistakes` is `false` at the lesson level — but the submit callback
/// re-enables mistake recording per item for objectively-graded interactions
/// (MCQ / FillBlank / listening), so genuine errors reach the mistake book
/// while self-graded flip cards (`AnkiCard` / `AnkiHtmlCard`) stay out of it. SRS grading is
/// handled by the shared [LessonViewModel] submit path.
@RoutePage()
class AnkiReviewSessionPage extends StatefulWidget {
  /// Restrict the review to cards belonging to this Anki section, or `null`
  /// to review cards across all imported decks.
  final String? sectionId;

  const AnkiReviewSessionPage({super.key, this.sectionId});

  @override
  State<AnkiReviewSessionPage> createState() => _AnkiReviewSessionPageState();
}

class _ReviewUndoEntry {
  final String wordId;
  final SrsWord previous;
  final bool isNewCard;
  final String? importId;

  const _ReviewUndoEntry({
    required this.wordId,
    required this.previous,
    required this.isNewCard,
    required this.importId,
  });
}

class _AnkiReviewSessionPageState extends State<AnkiReviewSessionPage> {
  late final LessonViewModel _vm;
  late final AnkiDeckManager _deckManager;
  final Set<InteractionRenderer> _renderers = getIt<Set<InteractionRenderer>>();
  final Random _random = Random();

  /// Ids of interactions in the current batch that were new cards
  /// (reps == 0) when the batch was assembled — used for daily counters.
  final Set<String> _newCardInteractionIds = {};

  bool _loading = true;
  bool _empty = false;
  String? _error;
  bool _dialogShown = false;
  bool _autoAdvanceScheduled = false;
  _ReviewUndoEntry? _undoEntry;

  @override
  void initState() {
    super.initState();
    _vm = context.read<LessonViewModel>();
    _vm.addListener(_onVmChanged);
    _deckManager = getIt<AnkiDeckManager>();
    WidgetsBinding.instance.addPostFrameCallback((_) => _start());
  }

  @override
  void dispose() {
    _vm.removeListener(_onVmChanged);
    super.dispose();
  }

  Future<void> _start() async {
    setState(() {
      _loading = true;
      _empty = false;
      _error = null;
      _newCardInteractionIds.clear();
      _undoEntry = null;
    });

    try {
      final courseProvider = context.read<CourseProvider>();
      final srsProvider = context.read<SrsProvider>();
      final noteDao = getIt<AnkiNoteDao>();
      final expiredBuried = await noteDao.clearBuriedBefore(
        DateTime.now().millisecondsSinceEpoch,
      );
      for (final card in expiredBuried) {
        await srsProvider.setWordFlags(card.wordId, buried: false);
      }
      final assembler =
          AnkiReviewAssembler(srsProvider, courseProvider, noteDao: noteDao);

      final importId = widget.sectionId == null
          ? ''
          : AnkiReviewAssembler.importIdFromSectionId(widget.sectionId!);
      final maxNew = importId.isEmpty
          ? _deckManager.newRemainingToday
          : await _deckManager.remainingForImport(importId, isNew: true);
      final maxReview = importId.isEmpty
          ? _deckManager.reviewRemainingToday
          : await _deckManager.remainingForImport(importId, isNew: false);

      // Assemble one batch (≤20 cards) and load only those cards' lesson
      // bodies — never the whole deck. A 5k-card preload used to hang here
      // on CircularProgressIndicator for minutes.
      final lesson = await assembler.assembleBatchAsync(
        sectionId: widget.sectionId,
        maxNew: maxNew,
        maxReview: maxReview,
      );

      if (!mounted) return;
      if (lesson == null) {
        setState(() {
          _loading = false;
          _empty = true;
        });
        return;
      }
      final isEmpty = lesson.flattenedStages.every((s) => s.items.isEmpty);
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
      setState(() {
        _loading = false;
        _empty = isEmpty;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = e.toString();
      });
    }
  }

  /// Count one graded card against today's new/review quotas.
  void _recordReview(Interaction interaction) {
    final wordId = interaction.id.replaceFirst('anki-review-', '');
    final previous = context.read<SrsProvider>().state[wordId];
    if (previous != null) {
      _undoEntry = _ReviewUndoEntry(
        wordId: wordId,
        previous: previous,
        isNewCard: _newCardInteractionIds.contains(interaction.id),
        importId: _importIdFromWordId(wordId),
      );
    }
    unawaited(_deckManager.recordCardReviewed(
      isNewCard: _newCardInteractionIds.contains(interaction.id),
      importId: _importIdFromWordId(wordId),
    ));
  }

  String? _importIdFromWordId(String wordId) {
    if (!wordId.startsWith('anki-')) return null;
    final cIdx = wordId.lastIndexOf('-c');
    if (cIdx <= 5) return null;
    return wordId.substring(5, cIdx);
  }

  Future<void> _undoLastReview() async {
    final entry = _undoEntry;
    if (entry == null) return;
    final ok = await context.read<SrsProvider>().undoWordReview(
          entry.wordId,
          entry.previous,
        );
    if (!ok || !mounted) return;
    await _deckManager.recordCardUnreviewed(
      wasNewCard: entry.isNewCard,
      importId: entry.importId,
    );
    if (!mounted) return;
    final uiOk = await _vm.undoLastInteraction();
    if (!mounted) return;
    if (!uiOk) {
      // Gate held by an in-flight grade — leave the snackbar / entry in
      // place so the user can re-tap once the gate releases.
      return;
    }
    setState(() => _undoEntry = null);
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('已撤销上一张评分')),
    );
  }

  Future<void> _setCurrentCardState({
    bool? suspended,
    int? buriedUntil,
    bool? marked,
    int? flag,
  }) async {
    final interaction = _vm.currentInteraction;
    if (interaction == null) return;
    final wordId = interaction.id.replaceFirst('anki-review-', '');
    final dao = getIt<AnkiNoteDao>();
    final meta = await dao.cardMetaByWordId(wordId);
    if (meta == null || !mounted) return;
    await dao.setCardState(
      meta.importId,
      meta.cardId,
      suspended: suspended,
      buriedUntil: buriedUntil,
      marked: marked,
      flag: flag,
    );
    await context.read<SrsProvider>().setWordFlags(
          wordId,
          suspended: suspended,
          buried: buriedUntil == null ? null : true,
        );
  }

  Future<void> _showCardMenu() async {
    final action = await showModalBottomSheet<String>(
      context: context,
      builder: (sheetContext) => SafeArea(
        child: Wrap(
          children: [
            ListTile(
              leading: const Icon(Icons.pause_circle_outline),
              title: const Text('暂停卡片'),
              onTap: () => Navigator.pop(sheetContext, 'suspend'),
            ),
            ListTile(
              leading: const Icon(Icons.snooze_outlined),
              title: const Text('埋卡到明天'),
              onTap: () => Navigator.pop(sheetContext, 'bury'),
            ),
            ListTile(
              leading: const Icon(Icons.bookmark_border),
              title: const Text('标记 / 取消标记'),
              onTap: () => Navigator.pop(sheetContext, 'mark'),
            ),
            for (final entry in const [
              (1, Colors.red, '红旗'),
              (2, Colors.orange, '橙旗'),
              (3, Colors.blue, '蓝旗'),
              (4, Colors.green, '绿旗'),
            ])
              ListTile(
                leading: Icon(Icons.flag, color: entry.$2),
                title: Text(entry.$3),
                onTap: () => Navigator.pop(sheetContext, 'flag:${entry.$1}'),
              ),
          ],
        ),
      ),
    );
    if (!mounted || action == null) return;
    if (action == 'suspend') {
      await _setCurrentCardState(suspended: true);
      if (mounted) _vm.advance();
    } else if (action == 'bury') {
      final tomorrow = DateTime.now().add(const Duration(days: 1));
      await _setCurrentCardState(
        buriedUntil: DateTime(tomorrow.year, tomorrow.month, tomorrow.day)
            .millisecondsSinceEpoch,
      );
      if (mounted) _vm.advance();
    } else if (action == 'mark') {
      final interaction = _vm.currentInteraction;
      if (interaction != null) {
        final meta = await getIt<AnkiNoteDao>().cardMetaByWordId(
          interaction.id.replaceFirst('anki-review-', ''),
        );
        if (meta != null) await _setCurrentCardState(marked: !meta.marked);
      }
    } else if (action.startsWith('flag:')) {
      await _setCurrentCardState(flag: int.parse(action.substring(5)));
    }
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
      body: _loading
          ? _buildLoading()
          : _error != null
              ? _buildError()
              : _empty
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
                          return _buildLoading();
                        }
                        final renderer =
                            lookupRenderer(_renderers, interaction);
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
                                (correct, {userAnswerText, reviewQuality}) {
                                  _recordReview(interaction);
                                  // Objectively-graded cards (MCQ/FillBlank/
                                  // listening) feed the mistake log; self-
                                  // graded flip cards stay out of it.
                                  vm.submitInteraction(
                                    correct,
                                    userAnswerText: userAnswerText,
                                    reviewQuality: reviewQuality,
                                    recordMistake: interaction is! AnkiCard &&
                                        interaction is! AnkiHtmlCard,
                                    mistakeWordId: interaction.id
                                        .replaceFirst('anki-review-', ''),
                                  );
                                },
                              ),
                            ),
                            if (showCheck)
                              SafeArea(
                                child: Padding(
                                  padding:
                                      const EdgeInsets.fromLTRB(20, 0, 20, 16),
                                  child: LessonCheckButton(
                                    label: selected.$5
                                        ? AppStrings.commonContinue
                                        : AppStrings.commonGotIt,
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
        tooltip: AppStrings.commonClose,
        icon: Icon(
          Icons.close_rounded,
          color: VarnamalaTheme.textPrimaryColor(context),
        ),
        onPressed: () => Navigator.of(context).maybePop(),
      ),
      title: Text(
        AppStrings.ankiReviewTitle,
        style: TextStyle(
          fontSize: 16,
          fontWeight: FontWeight.w700,
          color: VarnamalaTheme.textPrimaryColor(context),
        ),
      ),
      centerTitle: true,
      actions: [
        IconButton(
          tooltip: '撤销上一张评分',
          icon: const Icon(Icons.undo_rounded),
          onPressed: _undoEntry == null ? null : _undoLastReview,
        ),
        IconButton(
          tooltip: '卡片操作',
          icon: const Icon(Icons.more_vert_rounded),
          onPressed:
              _loading || _empty || _error != null ? null : _showCardMenu,
        ),
      ],
      bottom: (_empty || _loading || _error != null)
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

  Widget _buildLoading() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const CircularProgressIndicator(),
            const SizedBox(height: 20),
            Text(
              AppStrings.ankiReviewPreparing,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                    color: VarnamalaTheme.textSecondaryColor(context),
                  ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildError() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.error_outline_rounded,
              size: 64,
              color: VarnamalaTheme.error.withValues(alpha: 0.7),
            ),
            const SizedBox(height: 16),
            Text(
              AppStrings.ankiReviewLoadFailed,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
            ),
            const SizedBox(height: 8),
            Text(
              AppStrings.ankiReviewLoadFailedDetail(_error ?? ''),
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: VarnamalaTheme.textSecondaryColor(context),
                  ),
            ),
            const SizedBox(height: 20),
            FilledButton(
              onPressed: _start,
              child: Text(AppStrings.ankiReviewRetry),
            ),
            TextButton(
              onPressed: () => Navigator.of(context).maybePop(),
              child: Text(AppStrings.commonBack),
            ),
          ],
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
              AppStrings.ankiNoCardsDue,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                    color: VarnamalaTheme.textSecondaryColor(context),
                  ),
            ),
            const SizedBox(height: 16),
            TextButton(
              onPressed: () => Navigator.of(context).maybePop(),
              child: Text(AppStrings.commonBack),
            ),
          ],
        ),
      ),
    );
  }
}
