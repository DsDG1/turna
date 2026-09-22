// Dart imports:
import 'dart:async';

// Flutter imports:
import 'package:flutter/material.dart';

// Package imports:
import 'package:provider/provider.dart';

// Project imports:
import 'package:turna/application/ai/ai_course_provider.dart';
import 'package:turna/application/ai/ai_lesson_helper_provider.dart';
import 'package:turna/application/ai/ai_lesson_undo_store.dart';
import 'package:turna/application/ai/engine/ai_engine_config_holder.dart';
import 'package:turna/application/lesson_viewmodel.dart';
import 'package:turna/core/logger.dart';
import 'package:turna/di/injection.dart';
import 'package:turna/domain/course/interaction.dart';
import 'package:turna/domain/course/lesson.dart';
import 'package:turna/l10n/app_strings.dart';
import 'package:turna/core/theme.dart';
import 'package:turna/views/ai/components/ai_error_banner.dart';
import 'package:turna/views/widgets/turna_snack_bar.dart';

/// Bottom sheet for editing the current lesson with AI.
///
/// Reads the current lesson from [LessonViewModel] and uses
/// [AiLessonHelperProvider] to transform it.
class AiLessonHelperSheet extends StatefulWidget {
  const AiLessonHelperSheet({super.key});

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
      TurnaSnackBar.show(context, AppStrings.aiLessonHelperInvalidJson(e));
      return;
    }

    final original = provider.originalLesson;
    final beforeCount = original == null
        ? 0
        : original.flattenedStages.fold<int>(0, (n, s) => n + s.items.length);
    final afterCount =
        transformed.flattenedStages.fold<int>(0, (n, s) => n + s.items.length);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(AppStrings.aiLessonHelperApplyConfirmTitle),
        content: Text(
          '${AppStrings.aiLessonHelperApplyConfirmBody}\n'
          '${AppStrings.aiLessonHelperTitleChange(original?.name ?? AppStrings.emDash, transformed.name)}\n'
          '${AppStrings.aiLessonHelperCountChange(beforeCount, afterCount)}',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(AppStrings.commonCancel),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(AppStrings.commonApply),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    final courseProvider = context.read<AiCourseProvider>();
    final helper = context.read<AiLessonHelperProvider>();
    final snapshot = helper.originalLesson;
    try {
      await courseProvider.updateLessonInDb(transformed);
      if (!mounted) return;
      if (snapshot != null) {
        helper.armApplyUndo(snapshot);
        unawaited(AiLessonUndoStore.instance.save(snapshot));
      }
      final messenger = ScaffoldMessenger.of(context);
      final vm = context.read<LessonViewModel>();
      TurnaSnackBar.showVia(
        messenger,
        context,
        AppStrings.aiLessonHelperLessonUpdated,
        duration: const Duration(seconds: 5),
        action: SnackBarAction(
          label: AppStrings.commonUndo,
          onPressed: () {
            unawaited(_undoLessonApply(snapshot, messenger));
          },
        ),
      );
      unawaited(Navigator.of(context).maybePop());
      // Queue the reload so a fast undo is applied after this read, not lost
      // under it. Keep reload failures out of the write-failure snackbar.
      unawaited(helper.enqueueLessonReload(() async {
        try {
          await vm.loadLesson(transformed.id);
        } catch (e, st) {
          logger.w('lesson reload after apply failed',
              error: e, stackTrace: st);
        }
      }));
    } catch (e) {
      if (!mounted) return;
      TurnaSnackBar.show(context, AppStrings.aiLessonHelperUpdateFailed(e));
    }
  }

  Future<void> _undoLessonApply(
    Lesson? snapshot,
    ScaffoldMessengerState messenger,
  ) async {
    if (snapshot == null) return;
    final hostContext = messenger.context;
    final helper = getIt.isRegistered<AiLessonHelperProvider>()
        ? getIt<AiLessonHelperProvider>()
        : null;
    helper?.takeApplyUndo();
    unawaited(AiLessonUndoStore.instance.clear());
    try {
      await getIt<AiCourseProvider>().updateLessonInDb(snapshot);
      if (getIt.isRegistered<LessonViewModel>()) {
        final vm = getIt<LessonViewModel>();
        if (helper != null) {
          await helper.enqueueLessonReload(() => vm.loadLesson(snapshot.id));
        } else {
          await vm.loadLesson(snapshot.id);
        }
      }
    } catch (e, st) {
      logger.w('Lesson helper undo failed', error: e, stackTrace: st);
      helper?.armApplyUndo(snapshot);
      unawaited(AiLessonUndoStore.instance.save(snapshot));
      if (!hostContext.mounted) return;
      TurnaSnackBar.showVia(
        messenger,
        hostContext,
        AppStrings.aiLessonHelperUndoFailed,
        action: SnackBarAction(
          label: AppStrings.commonUndo,
          onPressed: () {
            unawaited(_undoLessonApply(snapshot, messenger));
          },
        ),
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
        const Icon(Icons.auto_fix_high, color: TurnaTheme.brandTeal, size: 22),
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
      AppStrings.aiLessonHelperChipMakeEasier,
      AppStrings.aiLessonHelperChipMakeHarder,
      AppStrings.aiLessonHelperChipAddExercises,
      AppStrings.aiLessonHelperChipListening,
      AppStrings.aiLessonHelperChipPolish,
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
                  color: TurnaTheme.brandTeal,
                  strokeWidth: 3,
                ),
              ),
            );
          case AiLessonHelperState.error:
            final mapping = context.read<AiLessonHelperProvider>().errorMapping;
            if (mapping == null) {
              return Text(AppStrings.aiLessonHelperErrorUnknown);
            }
            return AiErrorBanner(
              mapping: mapping,
              onRetry: _onTransform,
            );
          case AiLessonHelperState.ready:
          case AiLessonHelperState.applying:
            return _preview(context);
        }
      },
    );
  }

  Widget _preview(BuildContext context) {
    final provider = context.watch<AiLessonHelperProvider>();
    final explanation = provider.explanation;
    Lesson? next;
    try {
      final json = provider.resultJson;
      if (json != null) next = Lesson.fromJson(json);
    } catch (_) {
      next = null;
    }
    final original = provider.originalLesson;
    final before = original == null
        ? 0
        : original.flattenedStages.fold<int>(0, (n, s) => n + s.items.length);
    final after = next == null
        ? 0
        : next.flattenedStages.fold<int>(0, (n, s) => n + s.items.length);
    final typeLines = <String>[];
    if (next != null) {
      final counts = <String, int>{};
      for (final stage in next.flattenedStages) {
        for (final item in stage.items) {
          final label = interactionTypeLabel(item);
          counts[label] = (counts[label] ?? 0) + 1;
        }
      }
      counts.forEach((k, v) => typeLines.add('$k ×$v'));
    }
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
            const SizedBox(height: 8),
            Text(AppStrings.aiLessonHelperCountChange(before, after)),
            if (typeLines.isNotEmpty) ...[
              const SizedBox(height: 4),
              Text(typeLines.join(' · ')),
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
