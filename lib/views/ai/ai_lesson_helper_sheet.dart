// Flutter imports:
import 'package:flutter/material.dart';

// Package imports:
import 'package:provider/provider.dart';

// Project imports:
import 'package:turna/application/ai/ai_course_provider.dart';
import 'package:turna/application/ai/ai_lesson_helper_provider.dart';
import 'package:turna/application/ai/engine/ai_engine_config_holder.dart';
import 'package:turna/application/lesson_viewmodel.dart';
import 'package:turna/domain/course/lesson.dart';
import 'package:turna/l10n/app_strings.dart';
import 'package:turna/views/theme.dart';

/// Bottom sheet for editing the current lesson with AI.
///
/// Reads the current lesson from [LessonViewModel] and uses
/// [AiLessonHelperProvider] to transform it.
class AiLessonHelperSheet extends StatefulWidget {
  const AiLessonHelperSheet({Key? key}) : super(key: key);

  @override
  State<AiLessonHelperSheet> createState() => _AiLessonHelperSheetState();
}

class _AiLessonHelperSheetState extends State<AiLessonHelperSheet> {
  final TextEditingController _instructionCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    final lesson = context.read<LessonViewModel>().lesson;
    if (lesson != null) {
      context.read<AiLessonHelperProvider>().setLesson(lesson);
    }
  }

  @override
  void dispose() {
    _instructionCtrl.dispose();
    super.dispose();
  }

  Future<void> _onTransform() async {
    final instruction = _instructionCtrl.text.trim();
    if (instruction.isEmpty) return;
    await context.read<AiLessonHelperProvider>().transform(
          config: context.read<AiEngineConfigHolder>().config,
          instruction: instruction,
        );
  }

  Future<void> _onApply() async {
    final provider = context.read<AiLessonHelperProvider>();
    final resultJson = provider.resultJson;
    if (resultJson == null) return;

    Lesson transformed;
    try {
      transformed = Lesson.fromJson(resultJson);
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(AppStrings.aiLessonHelperInvalidJson(e))),
      );
      return;
    }

    final courseProvider = context.read<AiCourseProvider>();
    try {
      await courseProvider.updateLessonInDb(transformed);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(AppStrings.aiLessonHelperLessonUpdated)),
      );
      Navigator.of(context).maybePop();
      // Ask the lesson viewmodel to reload so the new content appears.
      final vm = context.read<LessonViewModel>();
      await vm.loadLesson(transformed.id);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(AppStrings.aiLessonHelperUpdateFailed(e))),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _header(context),
            const SizedBox(height: 12),
            _instructionInput(),
            const SizedBox(height: 12),
            _quickChips(),
            const SizedBox(height: 12),
            _body(context),
            const SizedBox(height: 12),
            _actions(context),
          ],
        ),
      ),
    );
  }

  Widget _header(BuildContext context) {
    return Row(
      children: [
        const Icon(Icons.auto_fix_high,
            color: TurnaTheme.peacockTeal, size: 22),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            AppStrings.aiLessonHelperTitle,
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
          ),
        ),
        IconButton(
          tooltip: AppStrings.commonClose,
          icon: const Icon(Icons.close, size: 22),
          onPressed: () => Navigator.of(context).maybePop(),
        ),
      ],
    );
  }

  Widget _instructionInput() {
    return TextField(
      controller: _instructionCtrl,
      maxLines: 2,
      decoration: InputDecoration(
        hintText: AppStrings.aiLessonHelperHint,
        labelText: AppStrings.aiLessonHelperInstructionLabel,
        border: const OutlineInputBorder(),
        isDense: true,
      ),
    );
  }

  Widget _quickChips() {
    final suggestions = [
      'Make easier',
      'Make harder',
      'Add 3 exercises',
      'Change to listening',
      'Polish prompts',
    ];
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        for (final s in suggestions)
          ActionChip(
            label: Text(s),
            onPressed: () {
              _instructionCtrl.text = s;
              _onTransform();
            },
          ),
      ],
    );
  }

  Widget _body(BuildContext context) {
    return Selector<AiLessonHelperProvider, AiLessonHelperState>(
      selector: (_, p) => p.state,
      builder: (context, state, _) {
        switch (state) {
          case AiLessonHelperState.idle:
            return const SizedBox.shrink();
          case AiLessonHelperState.loading:
            return const Padding(
              padding: EdgeInsets.symmetric(vertical: 24),
              child: Center(
                child: CircularProgressIndicator(
                  color: TurnaTheme.peacockTeal,
                  strokeWidth: 3,
                ),
              ),
            );
          case AiLessonHelperState.error:
            final error = context.read<AiLessonHelperProvider>().error;
            return Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: TurnaTheme.error.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(TurnaTheme.radiusMedium),
              ),
              child: Text(
                error != null
                    ? AppStrings.aiLessonHelperError(error)
                    : AppStrings.aiLessonHelperErrorUnknown,
                style: const TextStyle(color: TurnaTheme.error),
              ),
            );
          case AiLessonHelperState.ready:
          case AiLessonHelperState.applying:
            return _preview(context);
        }
      },
    );
  }

  Widget _preview(BuildContext context) {
    final explanation = context.select(
      (AiLessonHelperProvider p) => p.explanation,
    );
    return Container(
      constraints: const BoxConstraints(maxHeight: 240),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: TurnaTheme.cardBg(context),
        borderRadius: BorderRadius.circular(TurnaTheme.radiusMedium),
        border: Border.all(color: TurnaTheme.divider),
      ),
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              AppStrings.aiLessonHelperPreviewTitle,
              style: Theme.of(context).textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
            ),
            if (explanation != null && explanation.isNotEmpty) ...[
              const SizedBox(height: 8),
              Text(explanation),
            ] else ...[
              const SizedBox(height: 8),
              Text(AppStrings.aiLessonHelperTransformationReady),
            ],
          ],
        ),
      ),
    );
  }

  Widget _actions(BuildContext context) {
    return Selector<AiLessonHelperProvider, AiLessonHelperState>(
      selector: (_, p) => p.state,
      builder: (context, state, _) {
        final ready = state == AiLessonHelperState.ready ||
            state == AiLessonHelperState.applying;
        final busy = state == AiLessonHelperState.loading ||
            state == AiLessonHelperState.applying;
        return Row(
          children: [
            Expanded(
              child: FilledButton.icon(
                onPressed: busy ? null : _onTransform,
                icon: const Icon(Icons.auto_awesome),
                label: Text(AppStrings.aiLessonHelperTransform),
              ),
            ),
            if (ready) ...[
              const SizedBox(width: 12),
              Expanded(
                child: FilledButton.icon(
                  onPressed:
                      state == AiLessonHelperState.applying ? null : _onApply,
                  icon: const Icon(Icons.check),
                  label: Text(AppStrings.commonApply),
                ),
              ),
            ],
          ],
        );
      },
    );
  }
}
