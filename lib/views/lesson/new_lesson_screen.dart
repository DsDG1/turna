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
import 'package:words625/domain/course/interaction.dart';
import 'package:words625/domain/course/lesson_content.dart';
import 'package:words625/domain/course/reading_question.dart';
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

  @override
  void initState() {
    super.initState();
    _vm = context.read<LessonViewModel>();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _vm.loadLesson(widget.lessonId);
    });
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
            // Loading
            if (vm.lesson == null) {
              return const Center(
                child: CircularProgressIndicator(
                  color: VarnamalaTheme.peacockTeal,
                  strokeWidth: 3,
                ),
              );
            }

            // Complete — show dialog
            if (vm.isComplete) {
              _showCompletionDialog(context, vm);
            }

            // Check for ShowWord auto-advance
            _handleAutoAdvance(vm);

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

  Widget _buildLessonBody(LessonViewModel vm) {
    if (vm.isReadingLesson) {
      return _buildReadingBody(vm);
    }
    return _buildInteractionBody(vm);
  }

  // --- Interaction (normal/listening/review/challenge) ---

  Widget _buildInteractionBody(LessonViewModel vm) {
    final interaction = vm.currentInteraction;
    if (interaction == null) {
      return _buildEmptyContent();
    }

    final renderer = lookupRenderer(_renderers, interaction);

    return Column(
      children: [
        // Stage name banner
        if (vm.currentStageName != null)
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
            color: VarnamalaTheme.peacockTeal.withValues(alpha: 0.04),
            child: Text(
              vm.currentStageName!,
              style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: VarnamalaTheme.peacockTeal,
                letterSpacing: 0.5,
              ),
            ),
          ),

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

        // Advance button (shown after submission for non-ShowWord)
        if (vm.hasSubmitted && interaction is! ShowWord)
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

  // --- Reading lesson ---

  Widget _buildReadingBody(LessonViewModel vm) {
    final question = vm.currentReadingQuestion;
    if (question == null) {
      return _buildEmptyContent();
    }

    final readingStage = vm.currentReadingStage;

    return Column(
      children: [
        // Stage header
        if (readingStage != null)
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
            color: VarnamalaTheme.leagueAmethyst.withValues(alpha: 0.04),
            child: Text(
              readingStage.name,
              style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w600,
                color: VarnamalaTheme.leagueAmethyst,
                letterSpacing: 0.5,
              ),
            ),
          ),

        // Reading passage (shown on stage start)
        if (vm.currentReadingStage != null &&
            (vm.lesson?.content is ReadingContent))
          Builder(builder: (context) {
            final content = vm.lesson!.content as ReadingContent;
            if (content.text.isNotEmpty) {
              return Container(
                width: double.infinity,
                margin: const EdgeInsets.all(16),
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color:
                      VarnamalaTheme.leagueAmethyst.withValues(alpha: 0.05),
                  borderRadius:
                      BorderRadius.circular(VarnamalaTheme.radiusMedium),
                  border: Border.all(
                    color: VarnamalaTheme.leagueAmethyst
                        .withValues(alpha: 0.15),
                  ),
                ),
                child: Text(
                  content.text,
                  style: const TextStyle(
                    fontSize: 16,
                    height: 1.6,
                    color: VarnamalaTheme.textPrimary,
                  ),
                ),
              );
            }
            return const SizedBox.shrink();
          }),

        // Reading question
        Expanded(
          child: _ReadingQuestionWidget(
            question: question,
            state: vm.currentInteractionState,
            onSubmit: (correct, {userAnswerText}) {
              vm.submitInteraction(correct, userAnswerText: userAnswerText);
            },
            onAdvance: vm.hasSubmitted ? () => vm.advance() : null,
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

  // --- Auto-advance for ShowWord ---

  void _handleAutoAdvance(LessonViewModel vm) {
    if (_autoAdvanceScheduled) return;
    if (!vm.hasSubmitted) return;
    if (vm.currentInteraction is! ShowWord) return;

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
    if (!mounted) return;

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
}

// ──────────────────────────────────────────────────────────────
// Reading question widgets
// ──────────────────────────────────────────────────────────────

class _ReadingQuestionWidget extends StatefulWidget {
  final ReadingQuestion question;
  final InteractionState state;
  final void Function(bool correct, {String? userAnswerText}) onSubmit;
  final VoidCallback? onAdvance;

  const _ReadingQuestionWidget({
    required this.question,
    required this.state,
    required this.onSubmit,
    required this.onAdvance,
  });

  @override
  State<_ReadingQuestionWidget> createState() =>
      _ReadingQuestionWidgetState();
}

class _ReadingQuestionWidgetState extends State<_ReadingQuestionWidget> {
  // MCQ state
  int? _selectedIndex;

  // True/False state
  bool? _selectedBool;

  // Short answer state
  final TextEditingController _controller = TextEditingController();

  @override
  void initState() {
    super.initState();
    if (widget.state.submitted && widget.state.userAnswerText != null) {
      _controller.text = widget.state.userAnswerText!;
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return widget.question.when(
      mcq: (prompt, options, correctIndex) =>
          _buildMcq(prompt, options, correctIndex),
      trueFalse: (statement, answer) =>
          _buildTrueFalse(statement, answer),
      shortAnswer: (prompt, expectedAnswer) =>
          _buildShortAnswer(prompt, expectedAnswer),
    );
  }

  Widget _buildMcq(String prompt, List<String> options, int correctIndex) {
    final submitted = widget.state.submitted;
    final correct = widget.state.correct;

    return InteractionBody(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text(
            'Reading comprehension',
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: VarnamalaTheme.textHint,
              letterSpacing: 0.4,
            ),
          ),
          const SizedBox(height: 12),
          Text(
            prompt,
            style: const TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.w600,
              color: VarnamalaTheme.textPrimary,
            ),
          ),
          const SizedBox(height: 20),
          for (var idx = 0; idx < options.length; idx++) ...[
            _OptionTile(
              label: options[idx],
              isSelected: _selectedIndex == idx,
              isCorrect: submitted && idx == correctIndex,
              isWrong: submitted && correct == false && _selectedIndex == idx,
              onTap: submitted
                  ? null
                  : () => setState(() => _selectedIndex = idx),
            ),
            if (idx < options.length - 1) const SizedBox(height: 10),
          ],
          const SizedBox(height: 24),
          if (!submitted)
            LessonCheckButton(
              label: 'CHECK',
              enabled: _selectedIndex != null,
              onPressed: _selectedIndex != null
                  ? () => widget.onSubmit(
                        _selectedIndex == correctIndex,
                        userAnswerText: options[_selectedIndex!],
                      )
                  : null,
            )
          else
            LessonCheckButton(
              label: correct == true ? 'CONTINUE' : 'GOT IT',
              enabled: true,
              onPressed: widget.onAdvance,
            ),
        ],
      ),
    );
  }

  Widget _buildTrueFalse(String statement, bool answer) {
    final submitted = widget.state.submitted;
    final correct = widget.state.correct;

    return InteractionBody(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text(
            'True or False',
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: VarnamalaTheme.textHint,
              letterSpacing: 0.4,
            ),
          ),
          const SizedBox(height: 16),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: VarnamalaTheme.peacockTeal.withValues(alpha: 0.06),
              borderRadius:
                  BorderRadius.circular(VarnamalaTheme.radiusLarge),
            ),
            child: Text(
              statement,
              style: const TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.w600,
                color: VarnamalaTheme.textPrimary,
              ),
            ),
          ),
          const SizedBox(height: 24),
          Row(
            children: [
              Expanded(
                child: _BoolOption(
                  label: 'True',
                  value: true,
                  isSelected: _selectedBool == true,
                  isCorrect: submitted && answer == true,
                  isWrong: submitted &&
                      correct == false &&
                      _selectedBool == true,
                  onTap: submitted
                      ? null
                      : () => setState(() => _selectedBool = true),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _BoolOption(
                  label: 'False',
                  value: false,
                  isSelected: _selectedBool == false,
                  isCorrect: submitted && answer == false,
                  isWrong: submitted &&
                      correct == false &&
                      _selectedBool == false,
                  onTap: submitted
                      ? null
                      : () => setState(() => _selectedBool = false),
                ),
              ),
            ],
          ),
          const SizedBox(height: 24),
          if (!submitted)
            LessonCheckButton(
              label: 'CHECK',
              enabled: _selectedBool != null,
              onPressed: _selectedBool != null
                  ? () => widget.onSubmit(_selectedBool == answer,
                      userAnswerText: _selectedBool! ? 'True' : 'False')
                  : null,
            )
          else
            LessonCheckButton(
              label: correct == true ? 'CONTINUE' : 'GOT IT',
              enabled: true,
              onPressed: widget.onAdvance,
            ),
        ],
      ),
    );
  }

  Widget _buildShortAnswer(String prompt, String expectedAnswer) {
    final submitted = widget.state.submitted;
    final correct = widget.state.correct;
    final canSubmit = !submitted && _controller.text.trim().isNotEmpty;

    bool matches(String input) =>
        input.trim().toLowerCase() == expectedAnswer.trim().toLowerCase();

    return InteractionBody(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text(
            'Short answer',
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: VarnamalaTheme.textHint,
              letterSpacing: 0.4,
            ),
          ),
          const SizedBox(height: 12),
          Text(
            prompt,
            style: const TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.w600,
              color: VarnamalaTheme.textPrimary,
            ),
          ),
          const SizedBox(height: 24),
          TextField(
            controller: _controller,
            enabled: !submitted,
            autofocus: !submitted,
            style: const TextStyle(
              fontSize: 18,
              color: VarnamalaTheme.textPrimary,
            ),
            decoration: InputDecoration(
              hintText: 'Type your answer...',
              filled: true,
              fillColor: submitted
                  ? (correct == true
                      ? VarnamalaTheme.success.withValues(alpha: 0.10)
                      : VarnamalaTheme.error.withValues(alpha: 0.08))
                  : Colors.white,
            ),
            onChanged: (_) => setState(() {}),
            onSubmitted: (_) {
              if (canSubmit) {
                widget.onSubmit(
                  matches(_controller.text),
                  userAnswerText: _controller.text,
                );
              }
            },
          ),
          if (submitted && correct == false) ...[
            const SizedBox(height: 16),
            Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              decoration: BoxDecoration(
                color: VarnamalaTheme.success.withValues(alpha: 0.10),
                borderRadius:
                    BorderRadius.circular(VarnamalaTheme.radiusMedium),
              ),
              child: Row(
                children: [
                  const Icon(Icons.check_circle,
                      color: VarnamalaTheme.successDark),
                  const SizedBox(width: 8),
                  Expanded(
                    child: RichText(
                      text: TextSpan(
                        style: const TextStyle(
                          fontSize: 14,
                          color: VarnamalaTheme.textPrimary,
                        ),
                        children: [
                          const TextSpan(text: 'Correct answer: '),
                          TextSpan(
                            text: expectedAnswer,
                            style: const TextStyle(
                                fontWeight: FontWeight.w700),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
          const SizedBox(height: 24),
          if (!submitted)
            LessonCheckButton(
              label: 'CHECK',
              enabled: canSubmit,
              onPressed: canSubmit
                  ? () => widget.onSubmit(
                        matches(_controller.text),
                        userAnswerText: _controller.text,
                      )
                  : null,
            )
          else
            LessonCheckButton(
              label: correct == true ? 'CONTINUE' : 'GOT IT',
              enabled: true,
              onPressed: widget.onAdvance,
            ),
        ],
      ),
    );
  }
}

// ──────────────────────────────────────────────────────────────
// Shared reading option tile
// ──────────────────────────────────────────────────────────────

class _OptionTile extends StatelessWidget {
  final String label;
  final bool isSelected;
  final bool isCorrect;
  final bool isWrong;
  final VoidCallback? onTap;

  const _OptionTile({
    required this.label,
    required this.isSelected,
    required this.isCorrect,
    required this.isWrong,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    Color border = VarnamalaTheme.textHint.withValues(alpha: 0.25);
    Color background = Colors.white;
    Color textColor = VarnamalaTheme.textPrimary;
    Widget? trailing;

    if (isCorrect) {
      border = VarnamalaTheme.success;
      background = VarnamalaTheme.success.withValues(alpha: 0.10);
      trailing = const Icon(Icons.check_circle, color: VarnamalaTheme.success);
    } else if (isWrong) {
      border = VarnamalaTheme.error;
      background = VarnamalaTheme.error.withValues(alpha: 0.08);
      trailing = const Icon(Icons.cancel, color: VarnamalaTheme.error);
    } else if (isSelected) {
      border = VarnamalaTheme.peacockTeal;
      background = VarnamalaTheme.peacockTeal.withValues(alpha: 0.06);
    }

    return Material(
      color: background,
      shape: RoundedRectangleBorder(
        side: BorderSide(color: border, width: 2),
        borderRadius: BorderRadius.circular(VarnamalaTheme.radiusMedium),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(VarnamalaTheme.radiusMedium),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  label,
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w500,
                    color: textColor,
                  ),
                ),
              ),
              if (trailing != null) trailing,
            ],
          ),
        ),
      ),
    );
  }
}

class _BoolOption extends StatelessWidget {
  final String label;
  final bool value;
  final bool isSelected;
  final bool isCorrect;
  final bool isWrong;
  final VoidCallback? onTap;

  const _BoolOption({
    required this.label,
    required this.value,
    required this.isSelected,
    required this.isCorrect,
    required this.isWrong,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    Color border = VarnamalaTheme.textHint.withValues(alpha: 0.25);
    Color background = Colors.white;
    Color textColor = VarnamalaTheme.textPrimary;
    Widget? trailing;

    if (isCorrect) {
      border = VarnamalaTheme.success;
      background = VarnamalaTheme.success.withValues(alpha: 0.10);
      trailing = const Icon(Icons.check_circle, color: VarnamalaTheme.success);
    } else if (isWrong) {
      border = VarnamalaTheme.error;
      background = VarnamalaTheme.error.withValues(alpha: 0.08);
      trailing = const Icon(Icons.cancel, color: VarnamalaTheme.error);
    } else if (isSelected) {
      border = VarnamalaTheme.peacockTeal;
      background = VarnamalaTheme.peacockTeal.withValues(alpha: 0.06);
    }

    return Material(
      color: background,
      shape: RoundedRectangleBorder(
        side: BorderSide(color: border, width: 2),
        borderRadius: BorderRadius.circular(VarnamalaTheme.radiusMedium),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(VarnamalaTheme.radiusMedium),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 16),
          child: Center(
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  label,
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                    color: textColor,
                  ),
                ),
                if (trailing != null) ...[
                  const SizedBox(width: 8),
                  trailing,
                ],
              ],
            ),
          ),
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
