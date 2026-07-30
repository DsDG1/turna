// Dart imports:
import 'dart:async';
import 'dart:math';

// Flutter imports:
import 'package:flutter/material.dart';

// Package imports:
import 'package:auto_route/annotations.dart';
import 'package:provider/provider.dart';

// Project imports:
import 'package:varnamala/application/course_provider.dart';
import 'package:varnamala/application/daily_challenge_assembler.dart';
import 'package:varnamala/application/game_provider.dart';
import 'package:varnamala/application/gems_provider.dart';
import 'package:varnamala/application/lesson_viewmodel.dart';
import 'package:varnamala/di/injection.dart';
import 'package:varnamala/l10n/app_strings.dart';
import 'package:varnamala/views/lesson/components/interactions/interaction_renderer.dart';
import 'package:varnamala/views/lesson/components/lesson_dialogs.dart';
import 'package:varnamala/views/lesson/components/lesson_stage_widgets.dart';
import 'package:varnamala/views/theme.dart';

/// The number of random questions a daily challenge serves.
const int kDailyChallengeCount = 15;

@RoutePage()
class DailyChallengePage extends StatefulWidget {
  const DailyChallengePage({super.key});

  @override
  State<DailyChallengePage> createState() => _DailyChallengePageState();
}

class _DailyChallengePageState extends State<DailyChallengePage> {
  late final LessonViewModel _vm;
  final Set<InteractionRenderer> _renderers =
      getIt<Set<InteractionRenderer>>();
  final Random _random = Random();
  bool _autoAdvanceScheduled = false;
  bool _dialogShown = false;
  bool _empty = false;

  @override
  void initState() {
    super.initState();
    _vm = context.read<LessonViewModel>();
    _vm.addListener(_onVmChanged);
    WidgetsBinding.instance.addPostFrameCallback((_) => _startChallenge());
  }

  @override
  void dispose() {
    _vm.removeListener(_onVmChanged);
    super.dispose();
  }

  Future<void> _startChallenge() async {
    final courseProvider = context.read<CourseProvider>();
    // Yield to the event loop so the loading spinner renders before the
    // potentially CPU-heavy assembly work runs on the UI thread.
    final lesson = await Future(() => DailyChallengeAssembler(courseProvider).assemble(
      count: kDailyChallengeCount,
      random: _random,
    ));
    if (!mounted) return;
    final isEmpty = lesson.flattenedStages.isEmpty ||
        lesson.flattenedStages.every((s) => s.items.isEmpty);
    setState(() => _empty = isEmpty);
    _vm.loadLessonInstance(lesson);
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
    _handleAutoAdvance(vm);
  }

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider.value(
      value: _vm,
      child: Scaffold(
        backgroundColor: VarnamalaTheme.scaffoldBg(context),
        appBar: _buildAppBar(context),
        body: Consumer<LessonViewModel>(
          builder: (context, vm, _) {
            if (_empty) {
              return _buildEmptyDeck();
            }
            if (vm.lesson == null) {
              return const Center(
                child: CircularProgressIndicator(
                  color: VarnamalaTheme.peacockTeal,
                  strokeWidth: 3,
                ),
              );
            }
            return _buildChallengeBody(vm);
          },
        ),
      ),
    );
  }

  PreferredSizeWidget _buildAppBar(BuildContext context) {
    final vm = _vm;
    final total = vm.totalInteractionCount;
    final current = vm.currentQuestionNumber;
    final subtitle = total > 0 ? AppStrings.playDailyQuestion(current, total) : AppStrings.playDailyChallengeFallback;
    return AppBar(
      backgroundColor: VarnamalaTheme.surfaceColor(context),
      elevation: 0,
      leading: IconButton(
        tooltip: AppStrings.commonClose,
        icon: Icon(
          Icons.close_rounded,
          color: VarnamalaTheme.textPrimaryColor(context),
        ),
        onPressed: () => vm.isComplete ? null : Navigator.of(context).maybePop(),
      ),
      title: Column(
        children: [
          Text(
            AppStrings.playDailyTitle,
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w700,
              color: VarnamalaTheme.textPrimaryColor(context),
            ),
          ),
          const SizedBox(height: 2),
          Text(
            subtitle,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w500,
              color: VarnamalaTheme.textSecondaryColor(context),
            ),
          ),
        ],
      ),
      centerTitle: true,
      bottom: PreferredSize(
        preferredSize: const Size.fromHeight(4),
        child: LinearProgressIndicator(
          value: vm.progress,
          backgroundColor: VarnamalaTheme.leagueAmethyst.withValues(alpha: 0.1),
          valueColor: const AlwaysStoppedAnimation<Color>(
            VarnamalaTheme.leagueAmethyst,
          ),
        ),
      ),
    );
  }

  Widget _buildChallengeBody(LessonViewModel vm) {
    final interaction = vm.currentInteraction;
    if (interaction == null) {
      return _buildEmptyDeck();
    }

    final renderer = lookupRenderer(_renderers, interaction);

    return Column(
      children: [
        if (vm.currentStageName != null)
          LessonStageBanner(
            name: vm.currentStageName!,
            accent: VarnamalaTheme.leagueAmethyst,
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
                label: vm.isAnswerCorrect ? AppStrings.playDailyContinue : AppStrings.playDailyGotIt,
                enabled: true,
                onPressed: () => vm.advance(),
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildEmptyDeck() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.quiz_rounded,
              size: 48,
              color: VarnamalaTheme.textHint.withValues(alpha: 0.4),
            ),
            const SizedBox(height: 12),
            Text(
              AppStrings.playDailyNoQuestions,
              style: Theme.of(context).textTheme.titleMedium,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              AppStrings.playDailyCompleteFewLessons,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: VarnamalaTheme.textSecondaryColor(context),
                  ),
              textAlign: TextAlign.center,
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
}