// Dart imports:
import 'dart:convert';

// Flutter imports:
import 'package:flutter/material.dart';

// Package imports:
import 'package:auto_route/auto_route.dart';
import 'package:provider/provider.dart';

// Project imports:
import 'package:turna/application/ai/practice/ai_practice_job_queue.dart';
import 'package:turna/application/lesson_viewmodel.dart';
import 'package:turna/core/theme.dart';
import 'package:turna/di/injection.dart';
import 'package:turna/domain/course/lesson.dart';
import 'package:turna/domain/course/section.dart';
import 'package:turna/l10n/app_strings.dart';
import 'package:turna/views/lesson/components/interactions/interaction_renderer.dart';
import 'package:turna/views/lesson/components/lesson_stage_widgets.dart';
import 'package:turna/views/lesson/components/practice_session_body.dart';
import 'package:turna/views/widgets/study_activity_scope.dart';

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

  List<Lesson> _lessons = const [];
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
    var item = queue.byId(widget.practiceId);
    if (item == null || item.sectionJson == null) {
      if (mounted) setState(() => _loadFailed = true);
      return;
    }
    try {
      final parsed = jsonDecode(item.sectionJson!) as Map<String, dynamic>;
      final section = Section.fromJson(parsed);
      final lessons = [
        for (final unit in section.units)
          for (final lesson in unit.lessons)
            if (_hasItems(lesson)) lesson,
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

  static bool _hasItems(Lesson lesson) =>
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
    final retry = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => AlertDialog(
        title: Text(AppStrings.aiPracticeRunnerTitle),
        content: Text(AppStrings.aiPracticeMasteryFailed),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: Text(AppStrings.aiPracticeEnd),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: Text(AppStrings.lessonTryAgain),
          ),
        ],
      ),
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

  Future<void> _showCompletion() async {
    if (_dialogShown) return;
    _dialogShown = true;
    final hasNext = _lessonIndex + 1 < _lessons.length;
    final total = _vm.totalInteractionCount;
    final correct = _vm.correctAnswers;
    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => AlertDialog(
        title: Text(AppStrings.aiPracticeRunnerSummary),
        content: Text('答对 $correct / $total'),
        actions: [
          if (hasNext)
            FilledButton(
              onPressed: () {
                Navigator.of(dialogContext).pop();
                _loadLessonAt(_lessonIndex + 1);
              },
              child: Text(AppStrings.aiPracticeRunnerNext),
            )
          else
            FilledButton(
              onPressed: () {
                Navigator.of(dialogContext).pop();
                Navigator.of(context).maybePop();
              },
              child: Text(AppStrings.aiPracticeRunnerFinish),
            ),
        ],
      ),
    );
    _dialogShown = false;
  }

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider.value(
      value: _vm,
      child: Scaffold(
        backgroundColor: TurnaTheme.scaffoldBg(context),
        appBar: AppBar(
          backgroundColor: TurnaTheme.surfaceColor(context),
          elevation: 0,
          leading: IconButton(
            tooltip: AppStrings.commonClose,
            icon: const Icon(Icons.close_rounded),
            onPressed: () => Navigator.of(context).maybePop(),
          ),
          title: Column(
            children: [
              Text(
                _lessons.isEmpty
                    ? AppStrings.aiPracticeRunnerTitle
                    : _lessons[_lessonIndex].name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                  color: TurnaTheme.textPrimaryColor(context),
                ),
              ),
              const SizedBox(height: 2),
              Text(
                '${AppStrings.aiPracticeRunnerTitle} · '
                '${_lessonIndex + 1}/${_lessons.isEmpty ? 1 : _lessons.length}',
                style: TextStyle(
                  fontSize: 12,
                  color: TurnaTheme.textSecondaryColor(context),
                ),
              ),
            ],
          ),
          centerTitle: true,
          bottom: PreferredSize(
            preferredSize: const Size.fromHeight(4),
            child: LinearProgressIndicator(
              value: _vm.progress,
              backgroundColor: TurnaTheme.brandTeal.withValues(alpha: 0.1),
              valueColor: const AlwaysStoppedAnimation<Color>(
                TurnaTheme.brandTeal,
              ),
            ),
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
    return Consumer<LessonViewModel>(
      builder: (context, vm, _) {
        final interaction = vm.currentInteraction;
        if (interaction == null) {
          return _message(AppStrings.aiPracticeRunnerEmpty);
        }
        final renderer = lookupRenderer(_renderers, interaction);
        final showCheck = vm.hasSubmitted && !renderer.autoAdvance;
        final passage = _lessons[_lessonIndex].content.readingPassage;
        Widget? header;
        if (passage != null) {
          header = ConstrainedBox(
            constraints: BoxConstraints(
              maxHeight: MediaQuery.sizeOf(context).height * 0.4,
            ),
            child: LessonReadingPassageCard(passage: passage),
          );
        }
        return PracticeSessionBody(
          stageName: vm.currentStageName,
          stageAccent: TurnaTheme.brandTeal,
          header: header,
          showCheck: showCheck,
          checkLabel: vm.isAnswerCorrect
              ? AppStrings.lessonContinueUpper
              : AppStrings.lessonGotItUpper,
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
      },
    );
  }

  Widget _message(String text) => Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.auto_awesome_rounded, size: 44),
              const SizedBox(height: 12),
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
