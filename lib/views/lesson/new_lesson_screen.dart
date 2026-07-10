// Dart imports:
import 'dart:async';
import 'dart:math';

// Flutter imports:
import 'package:flutter/material.dart';

// Package imports:
import 'package:auto_route/annotations.dart';
import 'package:provider/provider.dart';

// Project imports:
import 'package:varnamala/application/lesson_viewmodel.dart';
import 'package:varnamala/di/injection.dart';
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
    if (vm.isMastery && !vm.masteryPassed && vm.lesson != null) {
      _showMasteryRetryDialog();
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
          },
        ),
      ),
    );
  }

  PreferredSizeWidget _buildAppBar(BuildContext context) {
    return AppBar(
      backgroundColor: VarnamalaTheme.surfaceColor(context),
      elevation: 0,
      leading: IconButton(
        icon: Icon(
          Icons.close_rounded,
          color: VarnamalaTheme.textPrimaryColor(context),
        ),
        onPressed: () => _vm.isComplete
            ? null
            : Navigator.of(context).maybePop(),
      ),
      title: Column(
        children: [
          Text(
            _vm.lesson?.name ?? 'Lesson',
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w700,
              color: VarnamalaTheme.textPrimaryColor(context),
            ),
          ),
          if (_vm.currentStageName != null) ...[
            const SizedBox(height: 2),
            Text(
              _vm.currentStageName!,
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
      bottom: PreferredSize(
        preferredSize: const Size.fromHeight(4),
        child: LinearProgressIndicator(
          value: _vm.progress,
          backgroundColor: VarnamalaTheme.peacockTeal.withValues(alpha: 0.1),
          valueColor: const AlwaysStoppedAnimation<Color>(
            VarnamalaTheme.peacockTeal,
          ),
        ),
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
    await showLessonCompletionDialog(
      context: context,
      isMounted: () => mounted,
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
        break;
    }
  }
}
