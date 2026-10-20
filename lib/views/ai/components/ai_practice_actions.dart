// Flutter imports:
import 'package:flutter/material.dart';

// Package imports:
import 'package:auto_route/auto_route.dart';
import 'package:provider/provider.dart';

// Project imports:
import 'package:turna/application/ai/practice/ai_practice_generator.dart';
import 'package:turna/application/ai/practice/ai_practice_job_queue.dart';
import 'package:turna/core/theme.dart';
import 'package:turna/domain/ai/ai_course.dart';
import 'package:turna/l10n/app_strings.dart';
import 'package:turna/routing/routing.gr.dart';
import 'package:turna/views/widgets/turna_snack_bar.dart';

/// Shared library actions (open / pin / retry / delete) used by both the AI
/// Hub preview and the full library page.

Future<void> openAiPractice(BuildContext context, AiCourse item) async {
  if (!item.isPlayable) return;
  await context.router.push(AiPracticeRunRoute(practiceId: item.id));
}

Future<void> deleteAiPractices(
  BuildContext context,
  List<AiCourse> items,
) async {
  if (items.isEmpty) return;
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: Text(AppStrings.aiPracticeDeleteTitle),
      content: Text(AppStrings.aiPracticeDeleteBody(items.length)),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(dialogContext).pop(false),
          child: Text(AppStrings.commonCancel),
        ),
        FilledButton(
          style: FilledButton.styleFrom(backgroundColor: TurnaTheme.error),
          onPressed: () => Navigator.of(dialogContext).pop(true),
          child: Text(AppStrings.aiPracticeDelete),
        ),
      ],
    ),
  );
  if (confirmed != true || !context.mounted) return;
  final queue = context.read<AiPracticeJobQueue>();
  try {
    await queue.deleteMany(items.map((item) => item.id));
  } catch (e) {
    if (!context.mounted) return;
    TurnaSnackBar.show(context, AppStrings.aiPracticeDeleteFailed(e));
    return;
  }
  if (!context.mounted) return;
  TurnaSnackBar.show(
    context,
    AppStrings.aiPracticeDeleted(items.length),
  );
}

Future<void> togglePin(
  BuildContext context,
  AiCourse item, {
  required bool pinned,
}) async {
  final queue = context.read<AiPracticeJobQueue>();
  await queue.setPinned([item.id], pinned: pinned);
  if (!context.mounted) return;
  TurnaSnackBar.show(
    context,
    pinned
        ? AppStrings.aiPracticePinnedToast
        : AppStrings.aiPracticeUnpinnedToast,
  );
}

Future<void> retryAiPractice(
  BuildContext context,
  AiCourse item,
) async {
  await context.read<AiPracticeJobQueue>().retry(item.id);
}

Future<void> adjustAiPractice(
  BuildContext context,
  AiCourse item,
) async {
  final controller = TextEditingController();
  try {
    final instruction = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(AppStrings.aiPracticeAdjust),
        content: TextField(
          controller: controller,
          autofocus: true,
          maxLines: 3,
          decoration: InputDecoration(
            hintText: AppStrings.aiPracticeAdjustHint,
            border: const OutlineInputBorder(),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: Text(AppStrings.commonCancel),
          ),
          FilledButton(
            onPressed: () =>
                Navigator.of(dialogContext).pop(controller.text.trim()),
            child: Text(AppStrings.commonApply),
          ),
        ],
      ),
    );
    if (instruction == null || instruction.isEmpty) return;
    if (!context.mounted) return;
    final queue = context.read<AiPracticeJobQueue>();
    await queue.adjust(item.id, instruction);
    if (!context.mounted) return;
    final updated = queue.byId(item.id);
    if (updated?.status == AiPracticeStatus.ready) {
      TurnaSnackBar.show(context, AppStrings.aiPracticeAdjusted);
    } else {
      TurnaSnackBar.show(
        context,
        AppStrings.aiPracticeAdjustFailed(
          updated?.errorMessage ?? AppStrings.aiPracticeRunnerEmpty,
        ),
      );
    }
  } on AiPracticeGenerationException catch (e) {
    if (!context.mounted) return;
    TurnaSnackBar.show(context, AppStrings.aiPracticeAdjustFailed(e.message));
  } catch (e) {
    if (!context.mounted) return;
    TurnaSnackBar.show(context, AppStrings.aiPracticeAdjustFailed(e));
  } finally {
    controller.dispose();
  }
}

Future<void> cancelAiPractice(
  BuildContext context,
  AiCourse item,
) async {
  await context.read<AiPracticeJobQueue>().cancel(item.id);
}
