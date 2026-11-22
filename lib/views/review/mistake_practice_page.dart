// Flutter imports:
import 'package:flutter/material.dart';

// Package imports:
import 'package:auto_route/annotations.dart';
import 'package:provider/provider.dart';

// Project imports:
import 'package:turna/application/mistake_provider.dart';
import 'package:turna/di/injection.dart';
import 'package:turna/domain/course/mistake_entry.dart';
import 'package:turna/l10n/app_strings.dart';
import 'package:turna/views/lesson/components/interactions/interaction_renderer.dart';
import 'package:turna/views/widgets/session_shell.dart';
import 'package:turna/views/widgets/turna_top_bar.dart';
import 'package:turna/core/spacing.dart';
import 'package:turna/core/theme.dart';

@RoutePage()
class MistakePracticePage extends StatefulWidget {
  final MistakeEntry entry;

  const MistakePracticePage({super.key, required this.entry});

  @override
  State<MistakePracticePage> createState() => _MistakePracticePageState();
}

class _MistakePracticePageState extends State<MistakePracticePage> {
  final Set<InteractionRenderer> _renderers = getIt<Set<InteractionRenderer>>();
  bool _submitted = false;
  bool? _correct;

  @override
  Widget build(BuildContext context) {
    final interaction = context.read<MistakeProvider>().toInteraction(
      widget.entry,
    );

    if (interaction == null) {
      return Scaffold(
        backgroundColor: TurnaTheme.scaffoldBg(context),
        appBar: TurnaTopBar(title: AppStrings.reviewPracticeTitle),
        body: Center(child: Text(AppStrings.reviewCannotPractice)),
      );
    }

    final renderer = lookupRenderer(_renderers, interaction);

    return Scaffold(
      backgroundColor: TurnaTheme.scaffoldBg(context),
      appBar: TurnaTopBar(title: AppStrings.reviewPracticeMistakeTitle),
      body: SafeArea(
        // Same overflow fix as `mistake_review_page.dart`: the renderer body
        // is a `Column` and a long prompt + many options can exceed the
        // viewport. Wrapping it in a scroll view makes the content reachable.
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.pageMargin,
            AppSpacing.md,
            AppSpacing.pageMargin,
            AppSpacing.lg,
          ),
          child: KeyedSubtree(
            key: ValueKey(widget.entry.id),
            child: renderer.build(
              interaction,
              InteractionState(
                submitted: _submitted,
                correct: _correct,
                userAnswerText: _submitted ? widget.entry.userAnswer : null,
              ),
              (correct, {userAnswerText, reviewQuality}) {
                setState(() {
                  _submitted = true;
                  _correct = correct;
                });
                if (correct) {
                  context.read<MistakeProvider>().recordRewrite(
                    widget.entry.id,
                  );
                }
              },
            ),
          ),
        ),
      ),
      // 稳定底部动作（R09）：提交后收束为单一下一步；提交前的核对 CTA 由
      // 题面 renderer 自管（无 LessonActionScope 时的既有回退行为）。
      bottomNavigationBar: _submitted
          ? SessionActionBand(
              child: SessionPrimaryAction(
                label: AppStrings.lessonContinueUpper,
                onPressed: () => Navigator.of(context).pop(),
              ),
            )
          : null,
    );
  }
}
