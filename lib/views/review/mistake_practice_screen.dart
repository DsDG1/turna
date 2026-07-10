// Flutter imports:
import 'package:flutter/material.dart';

// Package imports:
import 'package:auto_route/annotations.dart';
import 'package:provider/provider.dart';

// Project imports:
import 'package:varnamala/application/mistake_provider.dart';
import 'package:varnamala/di/injection.dart';
import 'package:varnamala/domain/course/mistake_entry.dart';
import 'package:varnamala/views/lesson/components/interactions/interaction_renderer.dart';
import 'package:varnamala/views/theme.dart';

@RoutePage()
class MistakePracticePage extends StatefulWidget {
  final MistakeEntry entry;

  const MistakePracticePage({super.key, required this.entry});

  @override
  State<MistakePracticePage> createState() => _MistakePracticePageState();
}

class _MistakePracticePageState extends State<MistakePracticePage> {
  final Set<InteractionRenderer> _renderers =
      getIt<Set<InteractionRenderer>>();
  bool _submitted = false;
  bool? _correct;

  @override
  Widget build(BuildContext context) {
    final interaction =
        context.read<MistakeProvider>().toInteraction(widget.entry);

    if (interaction == null) {
      return Scaffold(
        appBar: AppBar(title: const Text('Practice')),
        body: const Center(
          child: Text('This mistake cannot be practiced.'),
        ),
      );
    }

    final renderer = lookupRenderer(_renderers, interaction);

    return Scaffold(
      backgroundColor: VarnamalaTheme.scaffoldBg(context),
      appBar: AppBar(
        backgroundColor: VarnamalaTheme.surfaceColor(context),
        elevation: 0,
        iconTheme: IconThemeData(
          color: VarnamalaTheme.textPrimaryColor(context),
        ),
        title: Text(
          'Practice Mistake',
          style: TextStyle(
            color: VarnamalaTheme.textPrimaryColor(context),
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
                child: renderer.build(
                  interaction,
                  InteractionState(
                    submitted: _submitted,
                    correct: _correct,
                    userAnswerText: _submitted ? widget.entry.userAnswer : null,
                  ),
                  (correct, {userAnswerText}) {
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
              if (_submitted) ...[
                const SizedBox(height: 16),
                LessonCheckButton(
                  label: 'CONTINUE',
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
