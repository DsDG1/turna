// Dart imports:
import 'dart:math';

// Flutter imports:
import 'package:flutter/material.dart';

// Package imports:
import 'package:auto_route/annotations.dart';
import 'package:provider/provider.dart';

// Project imports:
import 'package:varnamala/application/game_provider.dart';
import 'package:varnamala/application/gems_provider.dart';
import 'package:varnamala/application/lesson_viewmodel.dart';
import 'package:varnamala/application/mistake_provider.dart';
import 'package:varnamala/application/weak_word_quiz_assembler.dart';
import 'package:varnamala/di/injection.dart';
import 'package:varnamala/views/lesson/components/interactions/interaction_renderer.dart';
import 'package:varnamala/views/lesson/components/lesson_dialogs.dart';
import 'package:varnamala/views/lesson/components/lesson_stage_widgets.dart';
import 'package:varnamala/views/theme.dart';

@RoutePage()
class WeakWordsPage extends StatefulWidget {
  const WeakWordsPage({super.key});

  @override
  State<WeakWordsPage> createState() => _WeakWordsPageState();
}

class _WeakWordsPageState extends State<WeakWordsPage> {
  late final LessonViewModel _vm;
  final Set<InteractionRenderer> _renderers =
      getIt<Set<InteractionRenderer>>();
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
    return ListenableBuilder(
      listenable: _vm,
      builder: (context, _) {
        return Scaffold(
          backgroundColor: VarnamalaTheme.scaffoldBg(context),
          appBar: AppBar(
            backgroundColor: VarnamalaTheme.surfaceColor(context),
            elevation: 0,
            leading: IconButton(
              tooltip: 'Close',
              icon: Icon(
                Icons.close_rounded,
                color: VarnamalaTheme.textPrimaryColor(context),
              ),
              onPressed: () => Navigator.of(context).maybePop(),
            ),
            title: Text(
              'Weak Words',
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
                    child: LinearProgressIndicator(
                      value: _vm.progress,
                      backgroundColor:
                          VarnamalaTheme.error.withValues(alpha: 0.1),
                      valueColor: const AlwaysStoppedAnimation<Color>(
                        VarnamalaTheme.error,
                      ),
                    ),
                  ),
          ),
          body: _empty ? _buildEmpty() : _buildBody(_vm),
        );
      },
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
              'Keep practicing — no weak words yet.\n'
              'Words you miss twice in 30 days will show up here.',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                    color: VarnamalaTheme.textSecondaryColor(context),
                  ),
            ),
            const SizedBox(height: 16),
            TextButton(
              onPressed: () => Navigator.of(context).maybePop(),
              child: const Text('Back'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBody(LessonViewModel vm) {
    final interaction = vm.currentInteraction;
    if (interaction == null) {
      return const Center(child: CircularProgressIndicator());
    }
    final renderer = lookupRenderer(_renderers, interaction);
    return Column(
      children: [
        if (vm.currentStageName != null)
          LessonStageBanner(
            name: vm.currentStageName!,
            accent: VarnamalaTheme.error,
          ),
        Expanded(
          child: renderer.build(
            interaction,
            vm.currentInteractionState,
            (correct, {userAnswerText}) {
              vm.submitInteraction(correct, userAnswerText: userAnswerText);
            },
          ),
        ),
        if (vm.hasSubmitted && !renderer.autoAdvance)
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
              child: LessonCheckButton(
                label: vm.isAnswerCorrect ? 'CONTINUE' : 'GOT IT',
                enabled: true,
                onPressed: () => vm.advance(),
              ),
            ),
          ),
      ],
    );
  }
}
