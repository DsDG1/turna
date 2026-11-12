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
import 'package:turna/views/lesson/components/lesson_stage_widgets.dart';
import 'package:turna/views/widgets/session_shell.dart';
import 'package:turna/views/widgets/turna_page_content.dart';
import 'package:turna/core/motion.dart';
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

/// 每日挑战 ——「湿地雾光」R07：接会话骨架（SessionProgressBand dots +
/// SessionActionBand + SessionPrimaryAction）。
///
/// 题面与判分接缝不动：题目仍由 [DailyChallengeAssembler] 装配、经
/// [LessonViewModel] 驱动同一批 [InteractionRenderer]；核对型题目的
/// 「核对 / 继续」CTA 草稿契约（[LessonActionScope] / [LessonActionDraft]）
/// 与课时壳（PracticeSessionBody）完全一致，只是动作带换成了会话骨架件。
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
        appBar: const _ChallengeAppBar(),
        body: Consumer<LessonViewModel>(
          builder: (context, vm, _) {
            if (_blockedMessage != null) {
              return PracticeEmptyState(
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
            return _ChallengeSessionBody(
              vm: vm,
              renderers: _renderers,
              continueLabel: vm.isAnswerCorrect
                  ? AppStrings.playDailyContinue
                  : AppStrings.playDailyGotIt,
              onAdvance: () => vm.advance(),
            );
          },
        ),
      ),
    );
  }

  Widget _buildEmptyDeck() {
    return PracticeEmptyState(
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
      random: _random,
    );
    _dialogShown = false;
  }
}

/// 挑战正文：阶段条 + 题面（草稿契约同课时壳）+ 会话动作带。
///
/// 与 [PracticeSessionBody] 的分工：那条是课时域的正文壳（P1 课时壳），
/// 本组件是练习域的会话骨架版——结构镜像（阶段条 / [LessonActionScope]
/// 注入 / 底栏草稿订阅），动作带与主操作换成 [SessionActionBand] /
/// [SessionPrimaryAction]。
class _ChallengeSessionBody extends StatefulWidget {
  const _ChallengeSessionBody({
    required this.vm,
    required this.renderers,
    required this.continueLabel,
    required this.onAdvance,
  });

  final LessonViewModel vm;
  final Set<InteractionRenderer> renderers;
  final String continueLabel;
  final VoidCallback onAdvance;

  @override
  State<_ChallengeSessionBody> createState() => _ChallengeSessionBodyState();
}

class _ChallengeSessionBodyState extends State<_ChallengeSessionBody> {
  LessonActionDraft _draft = LessonActionDraft();
  bool _wasSubmitted = false;

  @override
  void initState() {
    super.initState();
    _wasSubmitted = widget.vm.hasSubmitted;
    _draft.attach(_onDraftChanged);
  }

  @override
  void didUpdateWidget(covariant _ChallengeSessionBody old) {
    super.didUpdateWidget(old);
    // 换题信号：题目标识变了，或刚提交完又被复位。上一题的「能否提交」
    // 不能渗到下一题（与 PracticeSessionBody 相同的复位规则）。
    final newItem = old.vm.currentInteractionId != widget.vm.currentInteractionId ||
        (_wasSubmitted && !widget.vm.hasSubmitted);
    _wasSubmitted = widget.vm.hasSubmitted;
    if (newItem) {
      _draft.detach(_onDraftChanged);
      _draft = LessonActionDraft();
      _draft.attach(_onDraftChanged);
    }
  }

  @override
  void dispose() {
    _draft.detach(_onDraftChanged);
    super.dispose();
  }

  /// 草稿的通知一律在帧后发出（微任务），这里直接 setState 是安全的。
  void _onDraftChanged() {
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final vm = widget.vm;
    final interaction = vm.currentInteraction;
    if (interaction == null) {
      return const Center(
        child: CircularProgressIndicator(color: TurnaTheme.brandTeal),
      );
    }
    final renderer = lookupRenderer(widget.renderers, interaction);
    final autoAdvance = renderer.autoAdvance;
    final submitted = vm.hasSubmitted;

    final Widget body = Column(
      children: [
        if (vm.currentStageName != null)
          LessonStageBanner(
            name: vm.currentStageName!,
            accent: TurnaTheme.leagueAmethyst,
          ),
        Expanded(
          child: LessonActionScope(
            draft: _draft,
            child: SingleChildScrollView(
              padding: const EdgeInsets.only(top: 8, bottom: 8),
              // 单题入场：淡入 + 上移（reduceMotion 时立即呈现）。
              child: _EnterTransition(
                key: ValueKey(vm.currentInteractionId),
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
              ),
            ),
          ),
        ),
        if (!autoAdvance) _buildActionBand(submitted),
      ],
    );

    final content = TurnaPageContent(maxWidth: 720, child: body);
    // 安全区只收一次：有动作带时由 SessionActionBand 自己吞底部 inset，
    // 没有动作带（自动推进型）时退回到整列。
    if (!autoAdvance) return content;
    return SafeArea(top: false, left: false, right: false, child: content);
  }

  Widget _buildActionBand(bool submitted) {
    // 提交后永远有动作带（继续/知道了）；提交前只有托管了 CTA 的题型才有。
    final hasBar = submitted || _draft.hasCta;
    if (!hasBar) return const SizedBox.shrink();

    final enabled = submitted || _draft.canSubmit;
    return SessionActionBand(
      child: SessionPrimaryAction(
        label: submitted ? widget.continueLabel : AppStrings.lessonCheck,
        onPressed: enabled
            ? (submitted ? widget.onAdvance : _draft.submit)
            : null,
      ),
    );
  }
}

/// 单题入场：淡入 + 从下方 8px 滑到位（同课时壳的节奏）。
class _EnterTransition extends StatelessWidget {
  const _EnterTransition({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final reduceMotion = MediaQuery.disableAnimationsOf(context);
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: TurnaMotion.scaled(TurnaMotion.base, reduceMotion),
      curve: Curves.easeOutCubic,
      builder: (context, t, child) => Opacity(
        opacity: t,
        child: Transform.translate(
          offset: Offset(0, 8 * (1 - t)),
          child: child,
        ),
      ),
      child: child,
    );
  }
}

/// 挑战页顶栏：SessionProgressBand 的响应式装配（AppBar 槽要求
/// PreferredSizeWidget，Selector 不是）。
class _ChallengeAppBar extends StatelessWidget implements PreferredSizeWidget {
  const _ChallengeAppBar();

  @override
  Size get preferredSize =>
      const Size.fromHeight(SessionProgressBand.bandHeight);

  @override
  Widget build(BuildContext context) {
    final (current, total) = context.select<LessonViewModel, (int, int)>(
      (vm) => (vm.currentQuestionNumber, vm.totalInteractionCount),
    );
    final complete =
        context.select<LessonViewModel, bool>((vm) => vm.isComplete);
    return SessionProgressBand(
      currentIndex: current,
      totalCount: total,
      style: SessionProgressStyle.dots,
      exitTooltip: AppStrings.commonClose,
      // 完成对话框已在展示时不再给退出键（对齐旧 leading 的 null 态）。
      onExit: complete ? () {} : () => Navigator.of(context).maybePop(),
    );
  }
}
