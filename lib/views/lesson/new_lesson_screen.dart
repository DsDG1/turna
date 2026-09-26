// Dart imports:
import 'dart:async';
import 'dart:math';

// Flutter imports:
import 'package:flutter/material.dart';

// Package imports:
import 'package:auto_route/auto_route.dart';
import 'package:provider/provider.dart';

// Project imports:
import 'package:turna/application/ai/ai_explain_prefs.dart';
import 'package:turna/application/ai/ai_hint_provider.dart';
import 'package:turna/application/ai/ai_course_provider.dart';
import 'package:turna/application/ai/ai_lesson_helper_provider.dart';
import 'package:turna/application/ai/ai_lesson_undo_store.dart';
import 'package:turna/application/ai/engine/ai_engine_config_holder.dart';
import 'package:turna/application/ai/learner_ai_context_assembler.dart';
import 'package:turna/application/course_pack/imported_languages.dart';
import 'package:turna/application/course_provider.dart';
import 'package:turna/application/game_provider.dart';
import 'package:turna/application/gems_provider.dart';
import 'package:turna/application/language_registry.dart';
import 'package:turna/application/lesson_viewmodel.dart';
import 'package:turna/domain/course/course_scope.dart';
import 'package:turna/di/injection.dart';
import 'package:turna/domain/course/interaction.dart';
import 'package:turna/core/logger.dart';
import 'package:turna/domain/course/lesson.dart';
import 'package:turna/l10n/app_strings.dart';
import 'package:turna/routing/routing.gr.dart';
import 'package:turna/service/tab_router.dart';
import 'package:turna/views/lesson/components/ai_hint_sheet.dart';
import 'package:turna/views/ai/ai_lesson_helper_sheet.dart';
import 'package:turna/views/lesson/components/interactions/interaction_renderer.dart';
import 'package:turna/views/lesson/components/lesson_dialogs.dart';
import 'package:turna/views/lesson/components/lesson_stage_widgets.dart';
import 'package:turna/views/lesson/components/lesson_ai_undo_banner.dart';
import 'package:turna/views/lesson/components/practice_session_body.dart';
import 'package:turna/views/widgets/study_activity_scope.dart';
import 'package:turna/views/widgets/turna_snack_bar.dart';
import 'package:turna/core/theme.dart';

@RoutePage()
class NewLessonPage extends StatefulWidget {
  final String lessonId;

  const NewLessonPage({super.key, required this.lessonId});

  @override
  State<NewLessonPage> createState() => _NewLessonPageState();
}

class _NewLessonPageState extends State<NewLessonPage>
    with StudyActivityScopeMixin<NewLessonPage> {
  late final LessonViewModel _vm;
  final Set<InteractionRenderer> _renderers = getIt<Set<InteractionRenderer>>();
  final Random _random = Random();
  bool _autoAdvanceScheduled = false;
  bool _dialogShown = false;

  /// Once the completion dialog has been shown for this lesson pass, never
  /// re-show it on a subsequent VM notify (the VM stays `isComplete` until a
  /// retry/reset, so any stray notify after dismissal would otherwise pop the
  /// dialog a second time). Reset together with `_dialogShown` on retry.
  bool _completionDialogShown = false;
  bool _loadFailed = false;
  final ScrollController _lessonScroll = ScrollController();
  String? _scrolledInteractionId;

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
    _lessonScroll.dispose();
    super.dispose();
  }

  Future<void> _openLesson() async {
    // Backup mutual-exclusion scope (plan P0): while this screen studies a
    // lesson, a remote backup must not snapshot. A backup running right
    // now fails the load visibly instead of racing the snapshot.
    final blocked = enterStudyScope('lesson');
    if (blocked != null) {
      if (mounted) setState(() => _loadFailed = true);
      return;
    }
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
    final id = vm.currentInteractionId;
    if (id != _scrolledInteractionId) {
      _scrolledInteractionId = id;
      if (_lessonScroll.hasClients) {
        _lessonScroll.jumpTo(0);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider.value(
      value: _vm,
      child: Builder(
        builder: (context) => PopScope(
          canPop: false,
          onPopInvokedWithResult: (didPop, _) {
            if (!didPop) _onClosePressed(context);
          },
          child: Scaffold(
            backgroundColor: TurnaTheme.scaffoldBg(context),
            appBar: _LessonAppBar(
              vm: _vm,
              onClose: () => _onClosePressed(context),
              onAiHint: () => _openAiHint(context, _vm),
              onAiHelper: () => _openAiHelper(context, _vm),
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
              onSubmit: (correct, {userAnswerText, reviewQuality}) {
                _vm.submitInteraction(
                  correct,
                  userAnswerText: userAnswerText,
                  reviewQuality: reviewQuality,
                );
              },
              onAdvance: () => _vm.advance(),
              onRestoreAiLesson: _restoreAiLesson,
              scrollController: _lessonScroll,
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _onClosePressed(BuildContext context) async {
    if (_vm.isComplete) {
      // Unconditional pop bypasses canPop so this doesn't re-enter the
      // pop callback (the ai_api_config_page pop-loop fix, same landmine).
      Navigator.of(context).pop();
      return;
    }
    final go = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(AppStrings.lessonExitConfirmTitle),
        content: Text(AppStrings.lessonExitConfirmBody),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(AppStrings.commonCancel),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(AppStrings.lessonExitAnyway),
          ),
        ],
      ),
    );
    if (go == true && context.mounted) {
      Navigator.of(context).pop();
    }
  }

  /// Build the question snapshot, trigger an explanation, and pop up the
  /// hint sheet. If no API config is set, route the user to settings instead.
  Future<void> _openAiHint(BuildContext context, LessonViewModel vm) async {
    final interaction = vm.currentInteraction;
    if (interaction == null) return;

    final config = context.read<AiEngineConfigHolder>().config;
    if (!config.isComplete) {
      await _showAiConfigPrompt(context);
      return;
    }

    final languageCode = switch (context.read<CourseProvider>().scope) {
      BuiltinCourseScope(languageCode: final code) => code,
      _ => LanguageRegistry.instance.defaultCode,
    };
    final ctx = AiQuestionContext(
      // Overlay first: an imported course's display name lives in the
      // `importedLang:` meta, not the packed registry (which would
      // synthesize the raw code).
      language: ImportedLanguageRegistry.instance.displayNameOrNull(
            languageCode,
          ) ??
          LanguageRegistry.instance.displayName(languageCode),
      typeLabel: interactionTypeLabel(interaction),
      promptLabel: interactionPromptLabel(interaction),
      optionsLabel: interactionOptionsLabel(interaction),
      correctLabel: interactionCorrectAnswerLabel(interaction),
      userAnswer: vm.currentInteractionState.userAnswerText,
    );

    final hintProvider = context.read<AiHintProvider>();
    hintProvider.reset();

    // Inject learner context (mistakes/weak terms) when the shared prefs
    // allow it, so the first streamed reply already sees the snapshot.
    AiExplainPrefsStore? prefsStore;
    try {
      prefsStore = context.read<AiExplainPrefsStore>();
    } catch (_) {
      // Optional dependency: AI context injection stays disabled without it.
    }
    final learner = await LearnerAiContextAssembler.assembleIfInjectEnabled(
      languageName: ctx.language,
      prefs: prefsStore,
    );
    hintProvider.setLearnerContext(learner.isEmpty ? null : learner);

    if (!context.mounted) return;
    unawaited(hintProvider.explainQuestion(config: config, ctx: ctx));

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: TurnaTheme.cardBg(context),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(
          top: Radius.circular(TurnaTheme.radiusXLarge),
        ),
      ),
      builder: (_) => AiHintSheet(
        onEnterChat: () {
          context.router.push(AiHintChatRoute(context: ctx));
        },
      ),
    );
  }

  Future<void> _openAiHelper(BuildContext context, LessonViewModel vm) async {
    final config = context.read<AiEngineConfigHolder>().config;
    if (!config.isComplete) {
      await _showAiConfigPrompt(context);
      return;
    }

    final lesson = vm.lesson;
    if (lesson == null) return;

    final helperProvider = context.read<AiLessonHelperProvider>();
    helperProvider.setLesson(lesson);

    if (!context.mounted) return;
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: TurnaTheme.cardBg(context),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(
          top: Radius.circular(TurnaTheme.radiusXLarge),
        ),
      ),
      builder: (_) => const AiLessonHelperSheet(),
    );
  }

  Future<void> _restoreAiLesson(Lesson snapshot) async {
    await AiLessonUndoStore.instance.clear();
    if (getIt.isRegistered<AiLessonHelperProvider>()) {
      getIt<AiLessonHelperProvider>().takeApplyUndo();
    }
    try {
      await getIt<AiCourseProvider>().updateLessonInDb(snapshot);
      await _vm.loadLesson(snapshot.id);
    } catch (e, st) {
      logger.w('Persisted lesson undo failed', error: e, stackTrace: st);
      if (getIt.isRegistered<AiLessonHelperProvider>()) {
        getIt<AiLessonHelperProvider>().armApplyUndo(snapshot);
      }
      await AiLessonUndoStore.instance.save(snapshot);
      if (!mounted) return;
      TurnaSnackBar.show(context, AppStrings.aiLessonHelperUndoFailed);
    }
  }

  Future<void> _showAiConfigPrompt(BuildContext context) async {
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(AppStrings.aiNotConfiguredTitle),
        content: Text(AppStrings.aiNotConfiguredMessageLesson),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: Text(AppStrings.commonLater),
          ),
          FilledButton(
            onPressed: () {
              Navigator.of(dialogContext).pop();
              getIt<TabRouter>().switchTo(TabDestination.settings);
            },
            child: Text(AppStrings.aiGoToSettings),
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
      footnote: _vm.officialRedoFlushFailed
          ? AppStrings.lessonAnkiRedoFlushFailed
          : null,
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
        // Unconditional pop — maybePop behind PopScope(canPop: false)
        // re-enters this pop callback forever.
        navigator.pop();
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
  final VoidCallback onAiHelper;

  const _LessonAppBar({
    required this.vm,
    required this.onClose,
    required this.onAiHint,
    required this.onAiHelper,
  });

  @override
  Size get preferredSize => const Size.fromHeight(kToolbarHeight + 4);

  @override
  Widget build(BuildContext context) {
    return Selector<
        LessonViewModel,
        ({
          String name,
          String? stage,
          bool complete,
          double progress,
          bool aiEligible,
          int question,
          int total,
        })>(
      selector: (context, vm) => (
        name: vm.lesson?.name ?? AppStrings.lessonLessonFallback,
        stage: vm.currentStageName,
        complete: vm.isComplete,
        progress: vm.progress,
        aiEligible: _aiEligible(vm),
        question: vm.currentQuestionNumber,
        total: vm.totalInteractionCount,
      ),
      builder: (context, s, _) => AppBar(
        backgroundColor: TurnaTheme.surfaceColor(context),
        elevation: 0,
        leading: IconButton(
          tooltip: AppStrings.commonClose,
          icon: Icon(
            Icons.close_rounded,
            color: TurnaTheme.textPrimaryColor(context),
          ),
          onPressed: onClose,
        ),
        title: Column(
          children: [
            Text(
              s.name,
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w700,
                color: TurnaTheme.textPrimaryColor(context),
              ),
            ),
            if (s.stage != null) ...[
              const SizedBox(height: 2),
              Text(
                s.total > 0
                    ? '${s.stage!}  ${AppStrings.lessonQuestionIndex(s.question, s.total)}'
                    : s.stage!,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                  color: TurnaTheme.textSecondaryColor(context),
                ),
              ),
            ],
          ],
        ),
        centerTitle: true,
        actions: [
          IconButton(
            tooltip: AppStrings.lessonAiHelperTooltip,
            icon: Icon(
              Icons.auto_fix_high,
              color: TurnaTheme.textPrimaryColor(context),
            ),
            onPressed: onAiHelper,
          ),
          if (s.aiEligible)
            IconButton(
              tooltip: AppStrings.lessonAiHintTooltip,
              icon: Icon(
                Icons.lightbulb_rounded,
                color: TurnaTheme.textPrimaryColor(context),
              ),
              onPressed: onAiHint,
            ),
        ],
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(4),
          child: LinearProgressIndicator(
            value: s.progress,
            backgroundColor: TurnaTheme.brandTeal.withValues(alpha: 0.1),
            valueColor: const AlwaysStoppedAnimation<Color>(
              TurnaTheme.brandTeal,
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
  final Future<void> Function(Lesson snapshot) onRestoreAiLesson;
  final ScrollController scrollController;

  const _LessonBody({
    required this.vm,
    required this.renderers,
    required this.loadFailed,
    required this.lessonId,
    required this.onRetry,
    required this.onSubmit,
    required this.onAdvance,
    required this.onRestoreAiLesson,
    required this.scrollController,
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
                AppStrings.lessonCouldNotLoadLesson,
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
                child: Text(AppStrings.commonRetry),
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
              color: TurnaTheme.brandTeal,
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
          return _emptyContent(context);
        }
        final renderer = lookupRenderer(renderers, interaction);
        final readingPassage = lesson.content.readingPassage;
        final legacyPassage = lesson.content.passage;
        final showCheck = interactionState.submitted && !renderer.autoAdvance;
        Widget? header;
        if (readingPassage != null) {
          header = ConstrainedBox(
            constraints: BoxConstraints(
              maxHeight: MediaQuery.sizeOf(context).height * 0.4,
            ),
            child: LessonReadingPassageCard(passage: readingPassage),
          );
        } else if (legacyPassage.isNotEmpty) {
          header = ConstrainedBox(
            constraints: BoxConstraints(
              maxHeight: MediaQuery.sizeOf(context).height * 0.4,
            ),
            child: LessonLegacyReadingPassage(text: legacyPassage),
          );
        }

        return Column(
          children: [
            LessonAiUndoBanner(
              lessonId: lesson.id,
              onRestore: onRestoreAiLesson,
            ),
            Expanded(
              child: PracticeSessionBody(
                stageName: vm.currentStageName,
                stageAccent: TurnaTheme.brandTeal,
                header: header,
                scrollController: scrollController,
                interactionKey: ValueKey(vm.currentInteractionId),
                wrapRendererBoundary: true,
                showCheck: showCheck,
                checkLabel: interactionState.correct == true
                    ? AppStrings.lessonContinueUpper
                    : AppStrings.lessonGotItUpper,
                onAdvance: onAdvance,
                child: renderer.build(
                  interaction,
                  interactionState,
                  onSubmit,
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _emptyContent(BuildContext context) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            Icons.menu_book_rounded,
            size: 48,
            color: TurnaTheme.textHint.withValues(alpha: 0.3),
          ),
          const SizedBox(height: 12),
          Text(
            AppStrings.lessonNoContent,
            style: const TextStyle(
              fontSize: 16,
              color: TurnaTheme.textHint,
            ),
          ),
        ],
      ),
    );
  }
}
