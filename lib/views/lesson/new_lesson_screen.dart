// Dart imports:
import 'dart:math';

// Flutter imports:
import 'package:flutter/material.dart';

// Package imports:
import 'package:auto_route/annotations.dart';
import 'package:provider/provider.dart';

// Project imports:
import 'package:words625/application/lesson_viewmodel.dart';
import 'package:words625/di/injection.dart';
import 'package:words625/domain/course/reading_passage.dart';
import 'package:words625/views/lesson/components/interactions/interaction_renderer.dart';
import 'package:words625/views/theme.dart';

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
      _showCompletionDialog(context, vm);
      return;
    }
    // Mastery lesson failed — show retry dialog
    if (vm.isMastery && !vm.masteryPassed && vm.lesson != null) {
      _showMasteryRetryDialog(context, vm);
      return;
    }
    _handleAutoAdvance(vm);
  }

  @override
  Widget build(BuildContext context) {
    return ChangeNotifierProvider.value(
      value: _vm,
      child: Scaffold(
        backgroundColor: Colors.white,
        appBar: _buildAppBar(),
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

  PreferredSizeWidget _buildAppBar() {
    return AppBar(
      backgroundColor: Colors.white,
      elevation: 0,
      leading: IconButton(
        icon: const Icon(Icons.close_rounded, color: VarnamalaTheme.textPrimary),
        onPressed: () => _vm.isComplete
            ? null
            : Navigator.of(context).maybePop(),
      ),
      title: Column(
        children: [
          Text(
            _vm.lesson?.name ?? 'Lesson',
            style: const TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w700,
              color: VarnamalaTheme.textPrimary,
            ),
          ),
          if (_vm.currentStageName != null) ...[
            const SizedBox(height: 2),
            Text(
              _vm.currentStageName!,
              style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w500,
                color: VarnamalaTheme.textSecondary,
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

  /// Single rendering path for every lesson type. The optional reading
  /// passage renders above the stage content; the interaction body is
  /// dispatched by the renderer registry; the Continue/Got-It button shows
  /// after submission unless the renderer opts into auto-advance.
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
        // Stage name banner
        if (vm.currentStageName != null)
          _StageBanner(
            name: vm.currentStageName!,
            accent: VarnamalaTheme.peacockTeal,
          ),

        // Reading passage (structured model first, legacy string fallback)
        if (readingPassage != null)
          _ReadingPassage(passage: readingPassage)
        else if (legacyPassage.isNotEmpty)
          _LegacyReadingPassage(text: legacyPassage),

        // Renderer content
        Expanded(
          child: renderer.build(
            interaction,
            vm.currentInteractionState,
            (correct, {userAnswerText}) {
              vm.submitInteraction(correct, userAnswerText: userAnswerText);
            },
          ),
        ),

        // Advance button (shown after submission for non-auto-advance types)
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

  // --- Auto-advance for renderers that opt in (e.g. ShowWord) ---

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

  // --- Completion dialog ---

  Future<void> _showCompletionDialog(BuildContext context, LessonViewModel vm) async {
    // Prevent multiple dialogs
    if (!mounted || _dialogShown) return;
    _dialogShown = true;

    await Future.delayed(const Duration(milliseconds: 300));
    if (!mounted) return;

    const styles = [
      _CelebrationStyle(
        icon: Icons.celebration_rounded,
        accent: VarnamalaTheme.peacockTurquoise,
        title: 'Lesson Complete!',
        subtitle: 'Brilliant focus. You cleared this lesson.',
      ),
      _CelebrationStyle(
        icon: Icons.flash_on_rounded,
        accent: VarnamalaTheme.warning,
        title: 'That Was Fast!',
        subtitle: 'You are climbing fast. Keep the streak alive.',
      ),
      _CelebrationStyle(
        icon: Icons.auto_awesome_rounded,
        accent: VarnamalaTheme.leagueAmethyst,
        title: 'Excellent Work!',
        subtitle: 'Every lesson gets you closer to mastery.',
      ),
    ];
    final style = styles[Random().nextInt(styles.length)];

    await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => Dialog(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(VarnamalaTheme.radiusXLarge),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: style.accent.withValues(alpha: 0.12),
                  shape: BoxShape.circle,
                ),
                child: Icon(style.icon, color: style.accent, size: 40),
              ),
              const SizedBox(height: 20),
              Text(
                style.title,
                style: Theme.of(context)
                    .textTheme
                    .headlineSmall
                    ?.copyWith(fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 8),
              Text(
                style.subtitle,
                style: Theme.of(context).textTheme.bodyMedium,
              ),
              const SizedBox(height: 28),
              SizedBox(
                width: double.infinity,
                height: 48,
                child: ElevatedButton(
                  onPressed: () => Navigator.of(ctx).pop(true),
                  child: const Text(
                    'Continue',
                    style:
                        TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              TextButton(
                onPressed: () => Navigator.of(ctx).pop(true),
                child: Text(
                  'Back to Courses',
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: VarnamalaTheme.textHint,
                        fontWeight: FontWeight.w500,
                      ),
                ),
              ),
            ],
          ),
        ),
      ),
    );

    // Pop back to course tree
    if (mounted) {
      Navigator.of(context).maybePop();
    }
  }

  // --- Mastery retry dialog ---

  Future<void> _showMasteryRetryDialog(BuildContext context, LessonViewModel vm) async {
    if (!mounted || _dialogShown) return;
    _dialogShown = true;

    await Future.delayed(const Duration(milliseconds: 300));
    if (!mounted) return;

    final total = vm.lesson!.flattenedStages.fold<int>(
      0, (sum, s) => sum + s.items.length,
    );
    final accuracy = total == 0 ? 0 : ((vm.lesson!.isMastery ? vm.lesson!.flattenedStages.fold<int>(0, (sum, s) => sum + s.items.length) : 0) * 100).toInt(); // placeholder
    // Use actual correct count from VM if exposed; fallback to estimate
    final correct = vm.lesson!.flattenedStages.fold<int>(0, (sum, s) => sum + s.items.length); // will be replaced with actual

    final result = await showDialog<MasteryDialogResult>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => Dialog(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(VarnamalaTheme.radiusXLarge),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: VarnamalaTheme.error.withValues(alpha: 0.12),
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.refresh_rounded, color: VarnamalaTheme.error, size: 40),
              ),
              const SizedBox(height: 20),
              Text(
                'Not Yet',
                style: Theme.of(context)
                    .textTheme
                    .headlineSmall
                    ?.copyWith(fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 8),
              Text(
                'You need 80% accuracy to pass. Try again!',
                style: Theme.of(context).textTheme.bodyMedium,
              ),
              const SizedBox(height: 28),
              SizedBox(
                width: double.infinity,
                height: 48,
                child: ElevatedButton(
                  onPressed: () => Navigator.of(ctx).pop(MasteryDialogResult.retry),
                  child: const Text(
                    'Try Again',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              TextButton(
                onPressed: () => Navigator.of(ctx).pop(MasteryDialogResult.back),
                child: Text(
                  'Back to Courses',
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: VarnamalaTheme.textHint,
                        fontWeight: FontWeight.w500,
                      ),
                ),
              ),
            ],
          ),
        ),
      ),
    );

    _dialogShown = false;

    if (!mounted) return;

    switch (result) {
      case MasteryDialogResult.retry:
        vm.retryMastery();
        break;
      case MasteryDialogResult.back:
        Navigator.of(context).maybePop();
        break;
      case null:
        break;
    }
  }
}

enum MasteryDialogResult { retry, back }

// ──────────────────────────────────────────────────────────────
// Reading passage — rendered above the stage content on reading lessons
// ──────────────────────────────────────────────────────────────

class _ReadingPassage extends StatelessWidget {
  final ReadingPassage passage;

  const _ReadingPassage({required this.passage});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.all(16),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: VarnamalaTheme.leagueAmethyst.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(VarnamalaTheme.radiusMedium),
        border: Border.all(
          color: VarnamalaTheme.leagueAmethyst.withValues(alpha: 0.15),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            passage.title,
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w700,
                  color: VarnamalaTheme.textPrimary,
                ),
          ),
          const SizedBox(height: 12),
          ...passage.paragraphs.expand((paragraph) => [
                Text(
                  paragraph,
                  style: const TextStyle(
                    fontSize: 16,
                    height: 1.6,
                    color: VarnamalaTheme.textPrimary,
                  ),
                ),
                const SizedBox(height: 12),
              ]),
        ],
      ),
    );
  }
}

class _LegacyReadingPassage extends StatelessWidget {
  final String text;

  const _LegacyReadingPassage({required this.text});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.all(16),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: VarnamalaTheme.leagueAmethyst.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(VarnamalaTheme.radiusMedium),
        border: Border.all(
          color: VarnamalaTheme.leagueAmethyst.withValues(alpha: 0.15),
        ),
      ),
      child: Text(
        text,
        style: const TextStyle(
          fontSize: 16,
          height: 1.6,
          color: VarnamalaTheme.textPrimary,
        ),
      ),
    );
  }
}

// ──────────────────────────────────────────────────────────────
// Stage banner
// ──────────────────────────────────────────────────────────────

class _StageBanner extends StatelessWidget {
  final String name;
  final Color accent;

  const _StageBanner({required this.name, required this.accent});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
      color: accent.withValues(alpha: 0.04),
      child: Text(
        name,
        style: TextStyle(
          fontSize: 13,
          fontWeight: FontWeight.w600,
          color: accent,
          letterSpacing: 0.5,
        ),
      ),
    );
  }
}

// ──────────────────────────────────────────────────────────────
// Celebration styles
// ──────────────────────────────────────────────────────────────

class _CelebrationStyle {
  final IconData icon;
  final Color accent;
  final String title;
  final String subtitle;

  const _CelebrationStyle({
    required this.icon,
    required this.accent,
    required this.title,
    required this.subtitle,
  });
}