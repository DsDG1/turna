// Dart imports:
import 'dart:async';
import 'dart:math';

// Flutter imports:
import 'package:flutter/material.dart';

// Package imports:
import 'package:auto_route/annotations.dart';
import 'package:provider/provider.dart';

// Project imports:
import 'package:turna/application/course_provider.dart';
import 'package:turna/application/daily_challenge_assembler.dart';
import 'package:turna/application/game_provider.dart';
import 'package:turna/application/gems_provider.dart';
import 'package:turna/application/lesson_viewmodel.dart';
import 'package:turna/di/injection.dart';
import 'package:turna/l10n/app_strings.dart';
import 'package:turna/views/lesson/components/interactions/interaction_renderer.dart';
import 'package:turna/views/lesson/components/lesson_dialogs.dart';
import 'package:turna/views/lesson/components/practice_session_body.dart';
import 'package:turna/core/theme.dart';
import 'package:turna/views/widgets/practice_empty_state.dart';
import 'package:turna/views/widgets/study_activity_scope.dart';

/// The number of random questions a daily challenge serves.
const int kDailyChallengeCount = 15;

@RoutePage()
class DailyChallengePage extends StatefulWidget {
  const DailyChallengePage({super.key});

  @override
  State<DailyChallengePage> createState() => _DailyChallengePageState();
}

class _DailyChallengePageState extends State<DailyChallengePage>
    with StudyActivityScopeMixin<DailyChallengePage> {
  late final LessonViewModel _vm;
  final Set<InteractionRenderer> _renderers = getIt<Set<InteractionRenderer>>();
  final Random _random = Random();
  bool _autoAdvanceScheduled = false;
  bool _dialogShown = false;
  bool _empty = false;
  String? _blockedMessage;

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
    // Backup mutual-exclusion scope (plan P0): studying here must not race
    // a remote backup snapshot.
    final blocked = enterStudyScope('daily_challenge');
    if (blocked != null) {
      if (mounted) setState(() => _blockedMessage = blocked.toString());
      return;
    }
    final courseProvider = context.read<CourseProvider>();
    // Yield to the event loop so the loading spinner renders before the
    // potentially CPU-heavy assembly work runs on the UI thread.
    final lesson =
        await Future(() => DailyChallengeAssembler(courseProvider).assemble(
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
        backgroundColor: TurnaTheme.scaffoldBg(context),
        appBar: _buildAppBar(context),
        body: Consumer<LessonViewModel>(
          builder: (context, vm, _) {
            if (_blockedMessage != null) {
              return PracticeEmptyState(
                icon: Icons.cloud_off_outlined,
                accentColor: TurnaTheme.textHint,
                title: _blockedMessage!,
                actionLabel: AppStrings.commonBack,
                onAction: () => Navigator.of(context).maybePop(),
              );
            }
            if (_empty) {
              return _buildEmptyDeck();
            }
            if (vm.lesson == null) {
              return const Center(
                child: CircularProgressIndicator(
                  color: TurnaTheme.brandTeal,
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
    final subtitle = total > 0
        ? AppStrings.playDailyQuestion(current, total)
        : AppStrings.playDailyChallengeFallback;
    return AppBar(
      backgroundColor: TurnaTheme.surfaceColor(context),
      elevation: 0,
      leading: IconButton(
        tooltip: AppStrings.commonClose,
        icon: Icon(
          Icons.close_rounded,
          color: TurnaTheme.textPrimaryColor(context),
        ),
        onPressed: () =>
            vm.isComplete ? null : Navigator.of(context).maybePop(),
      ),
      title: Column(
        children: [
          Text(
            AppStrings.playDailyTitle,
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w700,
              color: TurnaTheme.textPrimaryColor(context),
            ),
          ),
          const SizedBox(height: 2),
          Text(
            subtitle,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w500,
              color: TurnaTheme.textSecondaryColor(context),
            ),
          ),
        ],
      ),
      centerTitle: true,
      bottom: PreferredSize(
        preferredSize: const Size.fromHeight(4),
        child: LinearProgressIndicator(
          value: vm.progress,
          backgroundColor: TurnaTheme.leagueAmethyst.withValues(alpha: 0.1),
          valueColor: const AlwaysStoppedAnimation<Color>(
            TurnaTheme.leagueAmethyst,
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

    return PracticeSessionBody(
      stageName: vm.currentStageName,
      stageAccent: TurnaTheme.leagueAmethyst,
      showCheck: vm.hasSubmitted && !renderer.autoAdvance,
      checkLabel: vm.isAnswerCorrect
          ? AppStrings.playDailyContinue
          : AppStrings.playDailyGotIt,
      onAdvance: () => vm.advance(),
      child: renderer.build(
        interaction,
        vm.currentInteractionState,
        (correct, {userAnswerText, reviewQuality}) {
          vm.submitInteraction(
            correct,
            userAnswerText: userAnswerText,
            reviewQuality: reviewQuality,
          );
        },
      ),
    );
  }

  Widget _buildEmptyDeck() {
    return PracticeEmptyState(
      icon: Icons.quiz_rounded,
      accentColor: TurnaTheme.textHint,
      title: AppStrings.playDailyNoQuestions,
      message: AppStrings.playDailyCompleteFewLessons,
      actionLabel: AppStrings.commonBack,
      onAction: () => Navigator.of(context).maybePop(),
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
