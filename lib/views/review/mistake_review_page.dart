// Flutter imports:
import 'dart:math';

import 'package:flutter/material.dart';

// Package imports:
import 'package:auto_route/auto_route.dart';
import 'package:provider/provider.dart';

// Project imports:
import 'package:turna/application/game_provider.dart';
import 'package:turna/application/gems_provider.dart';
import 'package:turna/application/lesson_viewmodel.dart';
import 'package:turna/application/mistake_provider.dart';
import 'package:turna/application/mistake_review_assembler.dart';
import 'package:turna/di/injection.dart';
import 'package:turna/domain/course/interaction.dart';
import 'package:turna/l10n/app_strings.dart';
import 'package:turna/routing/routing.gr.dart';
import 'package:turna/views/lesson/components/interactions/interaction_renderer.dart';
import 'package:turna/views/lesson/components/lesson_dialogs.dart';
import 'package:turna/views/lesson/components/practice_session_body.dart';
import 'package:turna/core/theme.dart';
import 'package:turna/core/turna_icon_id.dart';
import 'package:turna/views/widgets/practice_empty_state.dart';
import 'package:turna/views/widgets/session_shell.dart';
import 'package:turna/views/widgets/study_activity_scope.dart';
import 'package:turna/views/widgets/turna_icon.dart';
import 'package:turna/views/widgets/turna_loader.dart';
import 'package:turna/views/widgets/turna_top_bar.dart';

@RoutePage()
class MistakeReviewPage extends StatefulWidget {
  const MistakeReviewPage({super.key});

  @override
  State<MistakeReviewPage> createState() => _MistakeReviewPageState();
}

class _MistakeReviewPageState extends State<MistakeReviewPage>
    with StudyActivityScopeMixin<MistakeReviewPage> {
  late final LessonViewModel _vm;
  final Set<InteractionRenderer> _renderers = getIt<Set<InteractionRenderer>>();
  final Random _random = Random();
  bool _empty = false;
  String? _blockedMessage;
  bool _dialogShown = false;
  bool _autoAdvanceScheduled = false;
  bool _cleared = false;
  MistakeReviewAssembly? _assembly;

  @override
  void initState() {
    super.initState();
    _vm = context.read<LessonViewModel>();
    _vm.addListener(_onVmChanged);
    WidgetsBinding.instance.addPostFrameCallback((_) => _start());
  }

  @override
  void dispose() {
    _vm.removeListener(_onVmChanged);
    super.dispose();
  }

  Future<void> _start() async {
    // Backup mutual-exclusion scope (plan P0): studying here must not race
    // a remote backup snapshot.
    final blocked = enterStudyScope('mistake_review');
    if (blocked != null) {
      if (mounted) setState(() => _blockedMessage = blocked.toString());
      return;
    }
    final mistakes = context.read<MistakeProvider>().entries;
    final assembly = MistakeReviewAssembler.assemble(mistakes);
    final lesson = assembly.lesson;
    final isEmpty = lesson.flattenedStages.every((s) => s.items.isEmpty);
    if (!mounted) return;
    setState(() {
      _assembly = assembly;
      _empty = isEmpty;
    });
    if (!isEmpty) {
      // recordMistakes: false — wrong answers here must not re-record fresh
      // mistake entries (would create a feedback loop); this session prunes
      // the log itself on completion.
      _vm.loadLessonInstance(lesson, recordMistakes: false);
    }
  }

  void _onVmChanged() {
    if (!mounted) return;
    if (_vm.isComplete) {
      _clearMastered();
      _showCompletionDialog();
      return;
    }
    _handleAutoAdvance(_vm);
  }

  /// "做完则掌握" — clear only the mistakes answered correctly. Zip the
  /// assembly's entryIds (1:1 with the synthetic lesson items, lesson order)
  /// with the VM's questionResults (also lesson order, only submitted items —
  /// on completion every item is submitted, so the lists align).
  void _clearMastered() {
    if (_cleared || _assembly == null) return;
    final results = _vm.questionResults;
    final entryIds = _assembly!.entryIds;
    final correctIds = <String>{};
    for (var i = 0; i < results.length && i < entryIds.length; i++) {
      if (results[i].correct && entryIds[i] != null) {
        correctIds.add(entryIds[i]!);
      }
    }
    if (correctIds.isEmpty) {
      _cleared = true;
      return;
    }
    _cleared = true;
    context.read<MistakeProvider>().removeByIds(correctIds);
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
      random: _random,
    );
    _dialogShown = false;
  }

  @override
  Widget build(BuildContext context) {
    final isNonSession = _blockedMessage != null || _empty;
    final listAction = IconButton(
      tooltip: AppStrings.reviewViewMistakeList,
      icon: const TurnaIcon(TurnaIconId.list, size: 20),
      onPressed: () => context.router.push(const MistakeListRoute()),
    );
    return Scaffold(
      backgroundColor: TurnaTheme.scaffoldBg(context),
      appBar: isNonSession
          ? TurnaTopBar(
                  title: AppStrings.reviewMistakeReviewTitle,
                  actions: [listAction],
                )
                as PreferredSizeWidget
          : _MistakeReviewProgressBar(listAction: listAction),
      body: _blockedMessage != null
          ? PracticeEmptyState(
              title: _blockedMessage!,
              actionLabel: AppStrings.commonBack,
              onAction: () => Navigator.of(context).maybePop(),
            )
          : _empty
          ? _buildEmpty()
          : Selector<
              LessonViewModel,
              (Interaction?, InteractionState, String?, bool, bool)
            >(
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
                  return Center(child: TurnaLoader.page());
                }
                final renderer = lookupRenderer(_renderers, interaction);
                return PracticeSessionBody(
                  stageName: selected.$3,
                  stageAccent: TurnaTheme.error,
                  interactionKey: ValueKey(vm.currentInteractionId),
                  wrapRendererBoundary: true,
                  submitted: selected.$4,
                  autoAdvance: renderer.autoAdvance,
                  continueLabel: selected.$5
                      ? AppStrings.commonContinue
                      : AppStrings.commonGotIt,
                  onAdvance: () => vm.advance(),
                  child: renderer.build(interaction, selected.$2, (
                    correct, {
                    userAnswerText,
                    reviewQuality,
                  }) {
                    vm.submitInteraction(
                      correct,
                      userAnswerText: userAnswerText,
                      reviewQuality: reviewQuality,
                    );
                  }),
                );
              },
            ),
    );
  }

  Widget _buildEmpty() {
    return PracticeEmptyState(
      title: AppStrings.reviewMistakeEmptyTitle,
      message: AppStrings.reviewMistakeEmptyHint,
      actionLabel: AppStrings.commonBack,
      onAction: () => Navigator.of(context).maybePop(),
    );
  }
}

class _MistakeReviewProgressBar extends StatelessWidget
    implements PreferredSizeWidget {
  const _MistakeReviewProgressBar({required this.listAction});

  final Widget listAction;

  @override
  Size get preferredSize =>
      const Size.fromHeight(SessionProgressBand.bandHeight);

  @override
  Widget build(BuildContext context) {
    final (current, total) = context.select<LessonViewModel, (int, int)>(
      (vm) => (vm.currentQuestionNumber, vm.totalInteractionCount),
    );
    return SessionProgressBand(
      currentIndex: current,
      totalCount: total,
      style: SessionProgressStyle.dots,
      exitTooltip: AppStrings.commonClose,
      onExit: () => Navigator.of(context).maybePop(),
      actions: [listAction],
    );
  }
}
