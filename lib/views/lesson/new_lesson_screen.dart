// Dart imports:
import 'dart:async';
import 'dart:math';

// Flutter imports:
import 'package:flutter/material.dart';

// Package imports:
import 'package:auto_route/auto_route.dart';
import 'package:provider/provider.dart';

// Project imports:
import 'package:varnamala/application/ai/ai_course_provider.dart';
import 'package:varnamala/application/ai/ai_hint_provider.dart';
import 'package:varnamala/application/game_provider.dart';
import 'package:varnamala/application/gems_provider.dart';
import 'package:varnamala/application/lesson_viewmodel.dart';
import 'package:varnamala/core/enums.dart';
import 'package:varnamala/di/injection.dart';
import 'package:varnamala/domain/course/interaction.dart';
import 'package:varnamala/domain/course/lesson.dart';
import 'package:varnamala/routing/routing.gr.dart';
import 'package:varnamala/service/tab_router.dart';
import 'package:varnamala/views/lesson/components/ai_hint_sheet.dart';
import 'package:varnamala/views/lesson/components/interactions/interaction_renderer.dart';
import 'package:varnamala/views/lesson/components/lesson_dialogs.dart';
import 'package:varnamala/views/lesson/components/lesson_stage_widgets.dart';
import 'package:varnamala/views/theme.dart';

@RoutePage()
class NewLessonPage extends StatefulWidget {
  final String lessonId;

  const NewLessonPage({Key? key, required this.lessonId}) : super(key: key);

  @override
  State<NewLessonPage> createState() => _NewLessonPageState();
}

class _NewLessonPageState extends State<NewLessonPage> {
  late final LessonViewModel _vm;
  final Set<InteractionRenderer> _renderers =
      getIt<Set<InteractionRenderer>>();
  final Random _random = Random();
  bool _autoAdvanceScheduled = false;
  bool _dialogShown = false;
  /// Once the completion dialog has been shown for this lesson pass, never
  /// re-show it on a subsequent VM notify (the VM stays `isComplete` until a
  /// retry/reset, so any stray notify after dismissal would otherwise pop the
  /// dialog a second time). Reset together with `_dialogShown` on retry.
  bool _completionDialogShown = false;
  bool _loadFailed = false;

  @override
  void initState() {
    super.initState();
    _vm = context.read<LessonViewModel>();
    _vm.addListener(_onVmChanged);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _openLesson();
    });
  }

  @override
  void dispose() {
    _vm.removeListener(_onVmChanged);
    super.dispose();
  }

  Future<void> _openLesson() async {
    final ok = await _vm.loadLesson(widget.lessonId);
    if (!mounted) return;
    if (!ok) {
      setState(() => _loadFailed = true);
    }
  }

  /// Side effects (auto-advance, completion dialog) run only on VM notify —
  /// never from [build], to avoid multi-rebuild races.
  void _onVmChanged() {
    if (!mounted) return;
    final vm = _vm;
    if (vm.isComplete) {
      _showCompletionDialog();
      return;
    }
    if (vm.masteryFailed) {
      _showMasteryRetryDialog();
      return;
    }
    _handleAutoAdvance(vm);
  }

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider.value(
      value: _vm,
      child: Builder(
        builder: (context) => Scaffold(
          backgroundColor: VarnamalaTheme.scaffoldBg(context),
          appBar: _LessonAppBar(
            vm: _vm,
            onClose: () => _vm.isComplete
                ? null
                : Navigator.of(context).maybePop(),
            onAiHint: () => _openAiHint(context, _vm),
          ),
          body: _LessonBody(
            vm: _vm,
            renderers: _renderers,
            loadFailed: _loadFailed,
            lessonId: widget.lessonId,
            onRetry: () {
              setState(() => _loadFailed = false);
              _openLesson();
            },
            onSubmit: (correct, {userAnswerText}) {
              _vm.submitInteraction(correct, userAnswerText: userAnswerText);
            },
            onAdvance: () => _vm.advance(),
          ),
        ),
      ),
    );
  }

  /// Build the question snapshot, trigger an explanation, and pop up the
  /// hint sheet. If no API config is set, route the user to settings instead.
  Future<void> _openAiHint(BuildContext context, LessonViewModel vm) async {
    final interaction = vm.currentInteraction;
    if (interaction == null) return;

    final config = context.read<AiCourseProvider>().config;
    if (!config.isComplete) {
      await _showAiConfigPrompt(context);
      return;
    }

    final ctx = AiQuestionContext(
      // The loaded course is hardcoded to Turkish (CourseLoader.baseDir);
      // derive the persona's language label from that, not from the user's
      // LanguageProvider preference (a TTS/UI setting that could diverge once
      // a second TargetLanguage ships).
      language: TargetLanguage.turkish.displayName,
      typeLabel: interactionTypeLabel(interaction),
      promptLabel: interactionPromptLabel(interaction),
      optionsLabel: interactionOptionsLabel(interaction),
      correctLabel: interactionCorrectAnswerLabel(interaction),
      userAnswer: vm.currentInteractionState.userAnswerText,
    );

    final hintProvider = context.read<AiHintProvider>();
    hintProvider.reset();
    unawaited(hintProvider.explainQuestion(config: config, ctx: ctx));

    if (!mounted) return;
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: VarnamalaTheme.cardBg(context),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(
          top: Radius.circular(VarnamalaTheme.radiusXLarge),
        ),
      ),
      builder: (_) => AiHintSheet(
        onEnterChat: () {
          context.router.push(AiHintChatRoute(context: ctx));
        },
      ),
    );
  }

  Future<void> _showAiConfigPrompt(BuildContext context) async {
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('AI not configured'),
        content: const Text('Please fill in Base URL / API Key / Model under '
            'Settings → Learning → AI API Configuration before using AI hints.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('Later'),
          ),
          FilledButton(
            onPressed: () {
              Navigator.of(dialogContext).pop();
              getIt<TabRouter>().switchTo(TabDestination.settings);
            },
            child: const Text('Go to settings'),
          ),
        ],
      ),
    );
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
    if (!mounted || _dialogShown || _completionDialogShown) return;
    _dialogShown = true;
    _completionDialogShown = true;

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

  Future<void> _showMasteryRetryDialog() async {
    if (!mounted || _dialogShown) return;
    _dialogShown = true;

    final navigator = Navigator.of(context);
    final result = await showMasteryRetryDialog(
      context: context,
      isMounted: () => mounted,
      vm: _vm,
    );

    _dialogShown = false;
    if (!mounted) return;

    switch (result) {
      case MasteryDialogResult.retry:
        // Fresh attempt: allow the completion dialog to show again if this
        // retry pass succeeds.
        _completionDialogShown = false;
        _vm.retryMastery();
        break;
      case MasteryDialogResult.back:
        unawaited(navigator.maybePop());
        break;
      case null:
        // The dialog is barrierDismissible:false, so the only way `result` is
        // null is the Android system back button. Without handling it the user
        // is trapped (no dialog shown, no interaction, no way forward).
        // Re-show the dialog so they must pick Retry or Back explicitly.
        if (mounted) unawaited(_showMasteryRetryDialog());
        break;
    }
  }
}

/// Lesson AppBar, rebuilt only when the fields it actually shows change
/// (lesson name, stage name, completion flag for the close button, progress,
/// AI-hint eligibility). The rest of the page (body) no longer drags the AppBar
/// into a rebuild on every answer submission.
class _LessonAppBar extends StatelessWidget implements PreferredSizeWidget {
  final LessonViewModel vm;
  final VoidCallback? onClose;
  final VoidCallback onAiHint;

  const _LessonAppBar({
    required this.vm,
    required this.onClose,
    required this.onAiHint,
  });

  @override
  Size get preferredSize => const Size.fromHeight(kToolbarHeight + 4);

  @override
  Widget build(BuildContext context) {
    return Selector<LessonViewModel,
        ({String name, String? stage, bool complete, double progress, bool aiEligible})>(
      selector: (context, vm) => (
        name: vm.lesson?.name ?? 'Lesson',
        stage: vm.currentStageName,
        complete: vm.isComplete,
        progress: vm.progress,
        aiEligible: _aiEligible(vm),
      ),
      builder: (context, s, _) => AppBar(
        backgroundColor: VarnamalaTheme.surfaceColor(context),
        elevation: 0,
        leading: IconButton(
          tooltip: 'Close',
          icon: Icon(
            Icons.close_rounded,
            color: VarnamalaTheme.textPrimaryColor(context),
          ),
          // Disable close once complete (the completion dialog drives exit).
          onPressed: s.complete ? null : onClose,
        ),
        title: Column(
          children: [
            Text(
              s.name,
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w700,
                color: VarnamalaTheme.textPrimaryColor(context),
              ),
            ),
            if (s.stage != null) ...[
              const SizedBox(height: 2),
              Text(
                s.stage!,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                  color: VarnamalaTheme.textSecondaryColor(context),
                ),
              ),
            ],
          ],
        ),
        centerTitle: true,
        actions: [
          if (s.aiEligible)
            IconButton(
              tooltip: 'AI hint',
              icon: Icon(
                Icons.auto_awesome_rounded,
                color: VarnamalaTheme.textPrimaryColor(context),
              ),
              onPressed: onAiHint,
            ),
        ],
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(4),
          child: LinearProgressIndicator(
            value: s.progress,
            backgroundColor: VarnamalaTheme.peacockTeal.withValues(alpha: 0.1),
            valueColor: const AlwaysStoppedAnimation<Color>(
              VarnamalaTheme.peacockTeal,
            ),
          ),
        ),
      ),
    );
  }

  bool _aiEligible(LessonViewModel vm) {
    final i = vm.currentInteraction;
    if (i == null) return false;
    return interactionAiHintEligible(i);
  }
}

/// Lesson body. Rebuilds only when the current interaction / submission state
/// / load status changes — not on unrelated VM notify cycles (e.g. score
/// side-effects). The renderer subtree is wrapped in a [RepaintBoundary] so
/// post-submission option-tile colour transitions don't propagate repaints up
/// to the AppBar.
class _LessonBody extends StatelessWidget {
  final LessonViewModel vm;
  final Set<InteractionRenderer> renderers;
  final bool loadFailed;
  final String lessonId;
  final VoidCallback onRetry;
  final OnInteractionSubmit onSubmit;
  final VoidCallback onAdvance;

  const _LessonBody({
    required this.vm,
    required this.renderers,
    required this.loadFailed,
    required this.lessonId,
    required this.onRetry,
    required this.onSubmit,
    required this.onAdvance,
  });

  @override
  Widget build(BuildContext context) {
    if (loadFailed) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.error_outline_rounded, size: 48),
              const SizedBox(height: 12),
              Text(
                'Could not load lesson',
                style: Theme.of(context).textTheme.titleMedium,
              ),
              const SizedBox(height: 8),
              Text(
                lessonId,
                style: Theme.of(context).textTheme.bodySmall,
              ),
              const SizedBox(height: 16),
              TextButton(
                onPressed: onRetry,
                child: const Text('Retry'),
              ),
            ],
          ),
        ),
      );
    }

    return Selector<LessonViewModel, Lesson?>(
      selector: (context, vm) => vm.lesson,
      builder: (context, lesson, _) {
        if (lesson == null) {
          return const Center(
            child: CircularProgressIndicator(
              color: VarnamalaTheme.peacockTeal,
              strokeWidth: 3,
            ),
          );
        }
        return _buildContent(context, lesson);
      },
    );
  }

  Widget _buildContent(BuildContext context, Lesson lesson) {
    // Rebuild when either the current interaction OR its submission state
    // changes. InteractionState has value-equality so a submission (which
    // stores a new InteractionState for the same item id) flips the selector
    // value and rebuilds the body — including the check button — without
    // dragging the AppBar (its own selector) into the rebuild.
    return Selector<LessonViewModel, (Interaction?, InteractionState)>(
      selector: (context, vm) =>
          (vm.currentInteraction, vm.currentInteractionState),
      builder: (context, selected, _) {
        final interaction = selected.$1;
        final interactionState = selected.$2;
        if (interaction == null) {
          return _emptyContent();
        }
        final renderer = lookupRenderer(renderers, interaction);
        final readingPassage = lesson.content.readingPassage;
        final legacyPassage = lesson.content.passage;
        final showCheck =
            interactionState.submitted && !renderer.autoAdvance;

        return Column(
          children: [
            if (vm.currentStageName != null)
              LessonStageBanner(
                name: vm.currentStageName!,
                accent: VarnamalaTheme.peacockTeal,
              ),
            if (readingPassage != null)
              LessonReadingPassageCard(passage: readingPassage)
            else if (legacyPassage.isNotEmpty)
              LessonLegacyReadingPassage(text: legacyPassage),
            Expanded(
              child: RepaintBoundary(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.only(top: 8, bottom: 16),
                  // Key by the interaction's stable id so a new interaction
                  // creates a fresh State — no stale selection/answer
                  // carry-over between two consecutive interactions that
                  // share a renderer type. (No AnimatedSwitcher here: a fade
                  // transition stacks old+new children and breaks the
                  // unbounded-height layout inside a scroll view.)
                  child: KeyedSubtree(
                    key: ValueKey(vm.currentInteractionId),
                    child: renderer.build(
                      interaction,
                      interactionState,
                      onSubmit,
                    ),
                  ),
                ),
              ),
            ),
            if (showCheck)
              SafeArea(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
                  child: LessonCheckButton(
                    label:
                        interactionState.correct == true ? 'CONTINUE' : 'GOT IT',
                    enabled: true,
                    onPressed: onAdvance,
                  ),
                ),
              ),
          ],
        );
      },
    );
  }

  Widget _emptyContent() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.menu_book_rounded,
            size: 48,
            color: VarnamalaTheme.textHint.withValues(alpha: 0.3),
          ),
          const SizedBox(height: 12),
          const Text(
            'No content',
            style: TextStyle(
              fontSize: 16,
              color: VarnamalaTheme.textHint,
            ),
          ),
        ],
      ),
    );
  }
}
