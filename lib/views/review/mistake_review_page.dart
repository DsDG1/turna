// Flutter imports:
import 'dart:math';

import 'package:flutter/material.dart';

// Package imports:
import 'package:auto_route/auto_route.dart';
import 'package:provider/provider.dart';

// Project imports:
import 'package:varnamala/application/game_provider.dart';
import 'package:varnamala/application/gems_provider.dart';
import 'package:varnamala/application/lesson_viewmodel.dart';
import 'package:varnamala/application/mistake_provider.dart';
import 'package:varnamala/application/mistake_review_assembler.dart';
import 'package:varnamala/di/injection.dart';
import 'package:varnamala/domain/course/interaction.dart';
import 'package:varnamala/l10n/app_strings.dart';
import 'package:varnamala/routing/routing.gr.dart';
import 'package:varnamala/views/lesson/components/interactions/interaction_renderer.dart';
import 'package:varnamala/views/lesson/components/lesson_dialogs.dart';
import 'package:varnamala/views/lesson/components/lesson_stage_widgets.dart';
import 'package:varnamala/views/theme.dart';

@RoutePage()
class MistakeReviewPage extends StatefulWidget {
  const MistakeReviewPage({super.key});

  @override
  State<MistakeReviewPage> createState() => _MistakeReviewPageState();
}

class _MistakeReviewPageState extends State<MistakeReviewPage> {
  late final LessonViewModel _vm;
  final Set<InteractionRenderer> _renderers = getIt<Set<InteractionRenderer>>();
  final Random _random = Random();
  bool _empty = false;
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
                final showCheck =
                    selected.$4 && !renderer.autoAdvance;
                return Column(
                  children: [
                    if (selected.$3 != null)
                      LessonStageBanner(
                        name: selected.$3!,
                        accent: VarnamalaTheme.error,
                      ),
                    Expanded(
                      child: renderer.build(
                        interaction,
                        selected.$2,
                        (correct, {userAnswerText}) {
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
                            label: selected.$5 ? AppStrings.commonContinue : AppStrings.commonGotIt,
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
        AppStrings.reviewMistakeReviewTitle,
        style: TextStyle(
          fontSize: 16,
          fontWeight: FontWeight.w700,
          color: VarnamalaTheme.textPrimaryColor(context),
        ),
      ),
      centerTitle: true,
      actions: [
        IconButton(
          tooltip: AppStrings.reviewViewMistakeList,
          icon: Icon(
            Icons.list_rounded,
            color: VarnamalaTheme.textPrimaryColor(context),
          ),
          onPressed: () => context.router.push(const MistakeListRoute()),
        ),
      ],
      bottom: _empty
          ? null
          : PreferredSize(
              preferredSize: const Size.fromHeight(4),
              child: Selector<LessonViewModel, double>(
                selector: (context, vm) => vm.progress,
                builder: (context, progress, _) => LinearProgressIndicator(
                  value: progress,
                  backgroundColor:
                      VarnamalaTheme.error.withValues(alpha: 0.1),
                  valueColor:
                      const AlwaysStoppedAnimation<Color>(VarnamalaTheme.error),
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
            Text(
              AppStrings.reviewNoMistakes,
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