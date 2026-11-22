// Dart imports:
import 'dart:math';

// Flutter imports:
import 'package:flutter/material.dart';

// Package imports:
import 'package:auto_route/annotations.dart';
import 'package:provider/provider.dart';

// Project imports:
import 'package:turna/application/game_provider.dart';
import 'package:turna/application/gems_provider.dart';
import 'package:turna/application/lesson_viewmodel.dart';
import 'package:turna/application/mistake_provider.dart';
import 'package:turna/application/weak_word_quiz_assembler.dart';
import 'package:turna/di/injection.dart';
import 'package:turna/domain/course/interaction.dart';
import 'package:turna/l10n/app_strings.dart';
import 'package:turna/views/lesson/components/interactions/interaction_renderer.dart';
import 'package:turna/views/lesson/components/lesson_dialogs.dart';
import 'package:turna/views/lesson/components/practice_session_body.dart';
import 'package:turna/core/theme.dart';
import 'package:turna/views/widgets/practice_empty_state.dart';
import 'package:turna/views/widgets/session_shell.dart';
import 'package:turna/views/widgets/study_activity_scope.dart';
import 'package:turna/views/widgets/turna_loader.dart';
import 'package:turna/views/widgets/turna_top_bar.dart';

@RoutePage()
class WeakWordsPage extends StatefulWidget {
  const WeakWordsPage({super.key});

  @override
  State<WeakWordsPage> createState() => _WeakWordsPageState();
}

class _WeakWordsPageState extends State<WeakWordsPage>
    with StudyActivityScopeMixin<WeakWordsPage> {
  late final LessonViewModel _vm;
  final Set<InteractionRenderer> _renderers = getIt<Set<InteractionRenderer>>();
  final Random _random = Random();
  bool _empty = false;
  String? _blockedMessage;
  bool _dialogShown = false;
  bool _autoAdvanceScheduled = false;

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
    final blocked = enterStudyScope('weak_words_practice');
    if (blocked != null) {
      if (mounted) setState(() => _blockedMessage = blocked.toString());
      return;
    }
    final mistakes = context.read<MistakeProvider>().entries;
    final weak = WeakWordQuizAssembler.aggregateWeakWords(mistakes);
    if (weak.isEmpty) {
      if (mounted) setState(() => _empty = true);
      return;
    }
    final lesson = WeakWordQuizAssembler.assembleFromWeakWords(
      weak,
      random: _random,
    );
    if (!mounted) return;
    final isEmpty = lesson.flattenedStages.every((s) => s.items.isEmpty);
    setState(() => _empty = isEmpty);
    if (!isEmpty) _vm.loadLessonInstance(lesson);
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
      random: _random,
    );
    _dialogShown = false;
  }

  @override
  Widget build(BuildContext context) {
    final isNonSession = _blockedMessage != null || _empty;
    return Scaffold(
      backgroundColor: TurnaTheme.scaffoldBg(context),
      appBar: isNonSession
          ? TurnaTopBar(title: AppStrings.playWeakWordsTitleAppBar)
          : const _WeakWordsProgressBar(),
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
                  submitted: selected.$4,
                  autoAdvance: renderer.autoAdvance,
                  continueLabel: selected.$5
                      ? AppStrings.lessonContinueUpper
                      : AppStrings.lessonGotItUpper,
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
      title: AppStrings.playWeakWordsSubtitleEmpty,
      message: AppStrings.playWeakWordsEmptyHint,
      actionLabel: AppStrings.commonBack,
      onAction: () => Navigator.of(context).maybePop(),
    );
  }
}

class _WeakWordsProgressBar extends StatelessWidget
    implements PreferredSizeWidget {
  const _WeakWordsProgressBar();

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
    );
  }
}
