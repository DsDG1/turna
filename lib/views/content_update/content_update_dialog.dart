// Flutter imports:
import 'package:flutter/material.dart';

// Project imports:
import 'package:varnamala/views/theme.dart';

/// User choice for the content-update prompt (ADR 0002).
enum ContentUpdateChoice { keepProgress, resetProgress }

/// Non-dismissible dialog shown once per course content-version bump when the
/// user has existing progress (ADR 0002). "Keep progress" is the default
/// (non-destructive); "Reset progress" clears lesson/SRS/mistake/study-log
/// state so the user starts fresh with the updated course.
///
/// The dialog returns a [ContentUpdateChoice] via `showDialog`. Callers must
/// persist the acknowledged version on either choice so the dialog does not
/// recur for the same version.
class ContentUpdateDialog extends StatelessWidget {
  const ContentUpdateDialog({super.key});

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(VarnamalaTheme.radiusLarge),
      ),
      title: const Text('Course updated'),
      content: const Text(
        'The Swahili course has been updated with new words and lessons. '
        'You can start over or continue with your current progress.',
      ),
      actions: [
        TextButton(
          onPressed: () =>
              Navigator.of(context).pop(ContentUpdateChoice.keepProgress),
          child: const Text('Keep progress'),
        ),
        TextButton(
          onPressed: () =>
              Navigator.of(context).pop(ContentUpdateChoice.resetProgress),
          style: TextButton.styleFrom(foregroundColor: VarnamalaTheme.error),
          child: const Text('Reset progress'),
        ),
      ],
    );
  }
}