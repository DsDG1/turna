// Flutter imports:
import 'package:flutter/material.dart';

// Project imports:
import 'package:turna/application/ai/ai_lesson_undo_store.dart';
import 'package:turna/core/theme.dart';
import 'package:turna/domain/course/lesson.dart';
import 'package:turna/l10n/app_strings.dart';

/// Offers to restore the lesson JSON saved before the last AI apply.
class LessonAiUndoBanner extends StatelessWidget {
  const LessonAiUndoBanner({
    super.key,
    required this.lessonId,
    required this.onRestore,
  });

  final String lessonId;
  final Future<void> Function(Lesson snapshot) onRestore;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: AiLessonUndoStore.instance,
      builder: (context, _) {
        final pending = AiLessonUndoStore.instance.peek();
        if (pending == null || pending.id != lessonId) {
          return const SizedBox.shrink();
        }
        return Material(
          color: TurnaTheme.cardBg(context),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    AppStrings.aiLessonHelperUndoAvailable,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: TurnaTheme.textSecondaryColor(context),
                        ),
                  ),
                ),
                TextButton(
                  onPressed: () => onRestore(pending),
                  child: Text(AppStrings.commonUndo),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
