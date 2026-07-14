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
import 'package:varnamala/routing/routing.gr.dart';
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
      child: Consumer<LessonViewModel>(
        builder: (context, vm, _) => Scaffold(
          backgroundColor: VarnamalaTheme.scaffoldBg(context),
          appBar: _buildAppBar(context, vm),
          body: _buildBodyContent(context, vm),
        ),
      ),
    );
  }

  Widget _buildBodyContent(BuildContext context, LessonViewModel vm) {
    if (_loadFailed) {
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
                widget.lessonId,
                style: Theme.of(context).textTheme.bodySmall,
              ),
              const SizedBox(height: 16),
              TextButton(
                onPressed: () {
                  setState(() => _loadFailed = false);
                  _openLesson();
                },
                child: const Text('Retry'),
              ),
            ],
          ),
        ),
      );
    }

    if (vm.lesson == null) {
      return const Center(
        child: CircularProgressIndicator(
          color: VarnamalaTheme.peacockTeal,
          strokeWidth: 3,
        ),
      );
    }

    return _buildLessonBody(vm);
  }

  PreferredSizeWidget _buildAppBar(BuildContext context, LessonViewModel vm) {
    return AppBar(
      backgroundColor: VarnamalaTheme.surfaceColor(context),
      elevation: 0,
      leading: IconButton(
        tooltip: 'Close',
        icon: Icon(
          Icons.close_rounded,
          color: VarnamalaTheme.textPrimaryColor(context),
        ),
        onPressed: () => vm.isComplete
            ? null
            : Navigator.of(context).maybePop(),
      ),
      title: Column(
        children: [
          Text(
            vm.lesson?.name ?? 'Lesson',
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w700,
              color: VarnamalaTheme.textPrimaryColor(context),
            ),
          ),
          if (vm.currentStageName != null) ...[
            const SizedBox(height: 2),
            Text(
              vm.currentStageName!,
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
        if (_aiButtonEligible(vm))
          IconButton(
            tooltip: 'AI 讲解',
            icon: Icon(
              Icons.auto_awesome_rounded,
              color: VarnamalaTheme.textPrimaryColor(context),
            ),
            onPressed: () => _openAiHint(context, vm),
          ),
      ],
      bottom: PreferredSize(
        preferredSize: const Size.fromHeight(4),
        child: LinearProgressIndicator(
          value: vm.progress,
          backgroundColor: VarnamalaTheme.peacockTeal.withValues(alpha: 0.1),
          valueColor: const AlwaysStoppedAnimation<Color>(
            VarnamalaTheme.peacockTeal,
          ),
        ),
      ),
    );
  }

  /// The AI hint button is shown for interactions that carry a text prompt
  /// worth explaining. See [interactionAiHintEligible] — audio-driven types
  /// (no text prompt) opt out there, on the model.
  bool _aiButtonEligible(LessonViewModel vm) {
    final i = vm.currentInteraction;
    if (i == null) return false;
    return interactionAiHintEligible(i);
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
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
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
        title: const Text('AI 未配置'),
        content: const Text('请先在 设置 → AI API Configuration 中填写 '
            'Base URL / API Key / Model 后再使用 AI 讲解。'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('稍后'),
          ),
          FilledButton(
            onPressed: () {
              Navigator.of(dialogContext).pop();
              context.router.push(const SettingsRoute());
            },
            child: const Text('去设置'),
          ),
        ],
      ),
    );
  }

  Widget _buildLessonBody(LessonViewModel vm) {
    final interaction = vm.currentInteraction;
    if (interaction == null) {
      return _buildEmptyContent();
    }

    final renderer = lookupRenderer(_renderers, interaction);
    final readingPassage = vm.lesson?.content.readingPassage;
    final legacyPassage = vm.lesson?.content.passage ?? '';

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
          child: SingleChildScrollView(
            padding: const EdgeInsets.only(top: 8, bottom: 16),
            child: renderer.build(
              interaction,
              vm.currentInteractionState,
              (correct, {userAnswerText}) {
                vm.submitInteraction(correct, userAnswerText: userAnswerText);
              },
            ),
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

  Widget _buildEmptyContent() {
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
