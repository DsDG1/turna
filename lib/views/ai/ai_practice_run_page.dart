// Dart imports:
import 'dart:async';
import 'dart:convert';

// Flutter imports:
import 'package:flutter/material.dart';

// Package imports:
import 'package:auto_route/auto_route.dart';
import 'package:provider/provider.dart';

// Project imports:
import 'package:turna/application/ai/ai_explain_prefs.dart';
import 'package:turna/application/ai/ai_hint_provider.dart';
import 'package:turna/application/ai/ai_target_language_resolver.dart';
import 'package:turna/application/ai/engine/ai_engine_config_holder.dart';
import 'package:turna/application/ai/learner_ai_context_assembler.dart';
import 'package:turna/application/ai/practice/ai_practice_job_queue.dart';
import 'package:turna/application/ai/practice/ai_practice_models.dart';
import 'package:turna/application/lesson_viewmodel.dart';
import 'package:turna/core/ohos_target.dart';
import 'package:turna/core/text_styles.dart';
import 'package:turna/core/theme.dart';
import 'package:turna/core/turna_icon_id.dart';
import 'package:turna/di/injection.dart';
import 'package:turna/domain/course/interaction.dart';
import 'package:turna/domain/course/lesson.dart';
import 'package:turna/domain/course/section.dart';
import 'package:turna/l10n/app_strings.dart';
import 'package:turna/routing/routing.gr.dart';
import 'package:turna/views/lesson/components/ai_hint_sheet.dart';
import 'package:turna/views/lesson/components/dialogue_scene_header.dart';
import 'package:turna/views/lesson/components/guide_session_body.dart';
import 'package:turna/views/lesson/components/interactions/interaction_renderer.dart';
import 'package:turna/views/lesson/components/lesson_stage_widgets.dart';
import 'package:turna/views/lesson/components/practice_session_body.dart';
import 'package:turna/views/widgets/session_shell.dart';
import 'package:turna/views/widgets/study_activity_scope.dart';
import 'package:turna/views/widgets/turna_icon.dart';
import 'package:turna/views/widgets/turna_sheet.dart';
import 'package:turna/views/widgets/turna_top_bar.dart';

/// Plays a generated section straight from the practice library.
///
/// The section is **not** written into the course DB: `LessonViewModel`
/// receives an in-memory lesson (`loadLessonInstance`), exactly like the Daily
/// Challenge. Wrong answers still flow through the view-model, but course
/// progress / achievements are not touched because there is no course-tree
/// lesson id to complete.
@RoutePage()
class AiPracticeRunPage extends StatefulWidget {
  const AiPracticeRunPage({super.key, required this.practiceId});

  final String practiceId;

  @override
  State<AiPracticeRunPage> createState() => _AiPracticeRunPageState();
}

class _AiPracticeRunPageState extends State<AiPracticeRunPage>
    with StudyActivityScopeMixin<AiPracticeRunPage> {
  late final LessonViewModel _vm;
  final Set<InteractionRenderer> _renderers = getIt<Set<InteractionRenderer>>();
  final ScrollController _scrollController = ScrollController();

  List<Lesson> _lessons = const [];
  AiTargetLanguage _targetLanguage = const AiTargetLanguage.generic();
  int _lessonIndex = 0;
  bool _loadFailed = false;
  bool _blocked = false;
  bool _dialogShown = false;
  bool _autoAdvanceScheduled = false;

  @override
  void initState() {
    super.initState();
    _vm = context.read<LessonViewModel>();
    _vm.addListener(_onVmChanged);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _load();
    });
  }

  @override
  void dispose() {
    _vm.removeListener(_onVmChanged);
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final blocked = enterStudyScope('ai_practice');
    if (blocked != null) {
      if (mounted) setState(() => _blocked = true);
      return;
    }
    final queue = context.read<AiPracticeJobQueue>();
    await queue.ensureLoaded();
    final item = queue.byId(widget.practiceId);
    if (item == null || item.sectionJson == null) {
      if (mounted) setState(() => _loadFailed = true);
      return;
    }
    try {
      String? specLanguageName;
      try {
        final reqMap = jsonDecode(item.requestJson);
        if (reqMap is Map<String, dynamic>) {
          specLanguageName = AiPracticeRequest.fromJson(reqMap)?.spec.language;
        }
      } catch (_) {
        // Optional spec metadata; fall back to languageCode below.
      }
      _targetLanguage = AiTargetLanguageResolver.fromLanguageCode(
        item.languageCode,
        fallbackDisplayName: specLanguageName,
      );

      final parsed = jsonDecode(item.sectionJson!) as Map<String, dynamic>;
      final section = Section.fromJson(parsed);
      final lessons = [
        for (final unit in section.units)
          for (final lesson in unit.lessons)
            if (_hasPlayableContent(lesson)) lesson,
      ];
      if (lessons.isEmpty) {
        if (mounted) setState(() => _loadFailed = true);
        return;
      }
      if (!mounted) return;
      _lessons = lessons;
      _loadLessonAt(0);
    } catch (_) {
      if (mounted) setState(() => _loadFailed = true);
    }
  }

  static bool _hasPlayableContent(Lesson lesson) =>
      lesson.content.pages.isNotEmpty ||
      lesson.flattenedStages.any((stage) => stage.items.isNotEmpty);

  void _loadLessonAt(int index) {
    if (index < 0 || index >= _lessons.length) return;
    _lessonIndex = index;
    _dialogShown = false;
    _vm.loadLessonInstance(_lessons[index]);
    if (mounted) setState(() {});
  }

  void _onVmChanged() {
    if (!mounted) return;
    if (_vm.isComplete) {
      _showCompletion();
      return;
    }
    if (_vm.masteryFailed) {
      _showMasteryFailed();
      return;
    }
    _handleAutoAdvance();
  }

  Future<void> _showMasteryFailed() async {
    if (_dialogShown) return;
    _dialogShown = true;
    final retry = await showTurnaConfirmDialog(
      context: context,
      title: AppStrings.aiPracticeRunnerTitle,
      message: AppStrings.aiPracticeMasteryFailed,
      confirmLabel: AppStrings.lessonTryAgain,
      cancelLabel: AppStrings.aiPracticeEnd,
    );
    _dialogShown = false;
    if (!mounted) return;
    if (retry == true) {
      _vm.retryMastery();
    } else {
      await Navigator.of(context).maybePop();
    }
  }

  void _handleAutoAdvance() {
    if (_autoAdvanceScheduled) return;
    if (!_vm.hasSubmitted) return;
    final interaction = _vm.currentInteraction;
    if (interaction == null) return;
    final renderer = lookupRenderer(_renderers, interaction);
    if (!renderer.autoAdvance) return;
    _autoAdvanceScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _autoAdvanceScheduled = false;
      if (mounted) _vm.advance();
    });
  }

  Future<void> _openAiHint(BuildContext context) async {
    final interaction = _vm.currentInteraction;
    if (interaction == null) return;
    final config = context.read<AiEngineConfigHolder>().config;
    if (!config.isComplete) {
      await context.router.push(const AiApiConfigRoute());
      return;
    }
    final ctx = AiQuestionContext(
      language: _targetLanguage.displayName,
      typeLabel: interactionTypeLabel(interaction),
      promptLabel: interactionPromptLabel(interaction),
      optionsLabel: interactionOptionsLabel(interaction),
      correctLabel: interactionCorrectAnswerLabel(interaction),
      userAnswer: _vm.currentInteractionState.userAnswerText,
    );
    final hintProvider = context.read<AiHintProvider>();
    hintProvider.reset();
    if (!_targetLanguage.isGeneric) {
      AiExplainPrefsStore? prefsStore;
      try {
        prefsStore = context.read<AiExplainPrefsStore>();
      } catch (_) {
        // Optional dependency.
      }
      final learner = await LearnerAiContextAssembler.assembleIfInjectEnabled(
        languageName: _targetLanguage.displayName,
        prefs: prefsStore,
      );
      hintProvider.setLearnerContext(learner.isEmpty ? null : learner);
    } else {
      hintProvider.setLearnerContext(null);
    }
    if (!context.mounted) return;
    unawaited(hintProvider.explainQuestion(config: config, ctx: ctx));
    await showTurnaSheet<void>(
      context: context,
      title: AppStrings.aiHintTitleWithType(ctx.typeLabel),
      isScrollControlled: true,
      body: AiHintSheet(
        onEnterChat: () {
          context.router.push(AiHintChatRoute(context: ctx));
        },
      ),
    );
  }

  Future<void> _showCompletion() async {
    if (_dialogShown) return;
    _dialogShown = true;
    final hasNext = _lessonIndex + 1 < _lessons.length;
    final total = _vm.totalInteractionCount;
    final correct = _vm.correctAnswers;
    await showTurnaFormDialog<void>(
      context: context,
      barrierDismissible: false,
      title: AppStrings.aiPracticeRunnerSummary,
      body: Text(
        AppStrings.aiPracticeRunnerScore(correct, total),
        style: AppTextStyles.bodyText(context)
            .copyWith(color: TurnaTheme.textSecondaryColor(context)),
      ),
      actions: [
        TurnaSheetAction(
          label: hasNext
              ? AppStrings.aiPracticeRunnerNext
              : AppStrings.aiPracticeRunnerFinish,
          primary: true,
          onPressed: () {
            Navigator.of(context).pop();
            if (hasNext) {
              _loadLessonAt(_lessonIndex + 1);
            } else {
              Navigator.of(context).maybePop();
            }
          },
        ),
      ],
    );
    _dialogShown = false;
  }

  @override
  Widget build(BuildContext context) {
    final currentLesson = _lessons.isEmpty ? null : _lessons[_lessonIndex];
    final showAiAction = !isDegraded(OhosDegradation.aiGeneration) &&
        currentLesson != null &&
        currentLesson.template != LessonTemplate.guide;
    return ChangeNotifierProvider.value(
      value: _vm,
      child: Scaffold(
        backgroundColor: TurnaTheme.scaffoldBg(context),
        appBar: TurnaTopBar(
          centerTitle: true,
          leading: IconButton(
            tooltip: AppStrings.commonClose,
            icon: const TurnaIcon(TurnaIconId.close, size: 20),
            onPressed: () => Navigator.of(context).maybePop(),
          ),
          title: currentLesson == null
              ? AppStrings.aiPracticeRunnerTitle
              : currentLesson.name,
          subtitle: '${AppStrings.aiPracticeRunnerTitle} · '
              '${_lessonIndex + 1}/${_lessons.isEmpty ? 1 : _lessons.length}',
          actions: [
            if (showAiAction)
              IconButton(
                tooltip: AppStrings.aiTutorTitle,
                icon: const TurnaIcon(
                  TurnaIconId.spark,
                  size: 20,
                  color: TurnaTheme.brandTeal,
                ),
                onPressed: () => _openAiHint(context),
              ),
          ],
          bottom: PreferredSize(
            preferredSize: const Size.fromHeight(4),
            child: SessionThinProgressBar(value: _vm.progress),
          ),
        ),
        body: SafeArea(
          child: _blocked || _loadFailed
              ? _message(AppStrings.aiPracticeRunnerEmpty)
              : _body(context),
        ),
      ),
    );
  }

  Widget _body(BuildContext context) {
    if (_lessons.isEmpty) return _message(AppStrings.aiPracticeRunnerEmpty);
    final lesson = _lessons[_lessonIndex];
    if (lesson.template == LessonTemplate.guide) {
      return GuideSessionBody(
        lesson: lesson,
        scrollController: _scrollController,
      );
    }
    return Consumer<LessonViewModel>(
      builder: (context, vm, _) {
        final interaction = vm.currentInteraction;
        if (interaction == null) {
          return _message(AppStrings.aiPracticeRunnerEmpty);
        }
        final renderer = lookupRenderer(_renderers, interaction);
        final passage = lesson.content.readingPassage;
        final dialogueScene = lesson.content.dialogueScene;
        final Widget? header = passage != null
            ? LessonReadingPassageCard(passage: passage)
            : dialogueScene != null
                ? DialogueSceneHeader(
                    scene: dialogueScene,
                    interactions: [
                      for (final s in lesson.flattenedStages) ...s.items,
                    ],
                    currentInteractionId: interaction.id,
                    currentSubmitted: vm.hasSubmitted,
                  )
                : null;
        return PracticeSessionBody(
          stageName: vm.currentStageName,
          stageAccent: TurnaTheme.brandTeal,
          header: header,
          scrollController: _scrollController,
          submitted: vm.hasSubmitted,
          autoAdvance: renderer.autoAdvance,
          continueLabel: vm.isAnswerCorrect
              ? AppStrings.lessonContinueUpper
              : AppStrings.lessonGotItUpper,
          onAdvance: () => vm.advance(),
          child: renderer.build(interaction, vm.currentInteractionState, (
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
    );
  }

  Widget _message(String text) => Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(text, textAlign: TextAlign.center),
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
