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
import 'package:turna/views/lesson/components/lesson_stage_widgets.dart';
import 'package:turna/views/theme.dart';
import 'package:turna/views/widgets/practice_empty_state.dart';

@RoutePage()
class WeakWordsPage extends StatefulWidget {
  const WeakWordsPage({super.key});

  @override
  State<WeakWordsPage> createState() => _WeakWordsPageState();
}

class _WeakWordsPageState extends State<WeakWordsPage> {
  late final LessonViewModel _vm;
  final Set<InteractionRenderer> _renderers = getIt<Set<InteractionRenderer>>();
  final Random _random = Random();
  bool _empty = false;
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
      questionResults: _vm.questionResults,
      random: _random,
    );
    _dialogShown = false;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: TurnaTheme.scaffoldBg(context),
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
                        accent: TurnaTheme.error,
                      ),
                    Expanded(
                      child: renderer.build(
                        interaction,
                        selected.$2,
                        (correct, {userAnswerText, reviewQuality}) {
                          vm.submitInteraction(
                            correct,
                            userAnswerText: userAnswerText,
                            reviewQuality: reviewQuality,
                          );
                        },
                      ),
                    ),
                    if (showCheck)
                      SafeArea(
                        child: Padding(
                          padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
                          child: LessonCheckButton(
                            label: selected.$5
                                ? AppStrings.lessonContinueUpper
                                : AppStrings.lessonGotItUpper,
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
      backgroundColor: TurnaTheme.surfaceColor(context),
      elevation: 0,
      leading: IconButton(
        tooltip: AppStrings.commonClose,
        icon: Icon(
          Icons.close_rounded,
          color: TurnaTheme.textPrimaryColor(context),
        ),
        onPressed: () => Navigator.of(context).maybePop(),
      ),
      title: Text(
        AppStrings.playWeakWordsTitleAppBar,
        style: TextStyle(
          fontSize: 16,
          fontWeight: FontWeight.w700,
          color: TurnaTheme.textPrimaryColor(context),
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
                  backgroundColor: TurnaTheme.error.withValues(alpha: 0.1),
                  valueColor:
                      const AlwaysStoppedAnimation<Color>(TurnaTheme.error),
                ),
              ),
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
