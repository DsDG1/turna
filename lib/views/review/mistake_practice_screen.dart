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
import 'package:turna/views/theme.dart';

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
    final interaction =
        context.read<MistakeProvider>().toInteraction(widget.entry);

    if (interaction == null) {
      return Scaffold(
        appBar: AppBar(title: Text(AppStrings.reviewPracticeTitle)),
        body: Center(
          child: Text(AppStrings.reviewCannotPractice),
        ),
      );
    }

    final renderer = lookupRenderer(_renderers, interaction);

    return Scaffold(
      backgroundColor: TurnaTheme.scaffoldBg(context),
      appBar: AppBar(
        backgroundColor: TurnaTheme.surfaceColor(context),
        elevation: 0,
        iconTheme: IconThemeData(
          color: TurnaTheme.textPrimaryColor(context),
        ),
        title: Text(
          AppStrings.reviewPracticeMistakeTitle,
          style: TextStyle(
            color: TurnaTheme.textPrimaryColor(context),
            fontSize: 16,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(
                child: RepaintBoundary(
                  // Same overflow fix as `mistake_review_page.dart`: the
                  // renderer body is a `Column` and a long prompt + many
                  // options can exceed the viewport, producing
                  // `BOTTOM OVERFLOWED BY N PIXELS` stripes. Wrapping it in
                  // a scroll view makes the content reachable.
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.only(top: 8, bottom: 16),
                    child: KeyedSubtree(
                      key: ValueKey(widget.entry.id),
                      child: renderer.build(
                        interaction,
                        InteractionState(
                          submitted: _submitted,
                          correct: _correct,
                          userAnswerText:
                              _submitted ? widget.entry.userAnswer : null,
                        ),
                        (correct, {userAnswerText, reviewQuality}) {
                          setState(() {
                            _submitted = true;
                            _correct = correct;
                          });
                          if (correct) {
                            context
                                .read<MistakeProvider>()
                                .recordRewrite(widget.entry.id);
                          }
                        },
                      ),
                    ),
                  ),
                ),
              ),
              if (_submitted) ...[
                const SizedBox(height: 16),
                LessonCheckButton(
                  label: AppStrings.lessonContinueUpper,
                  enabled: true,
                  onPressed: () => Navigator.of(context).pop(),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
