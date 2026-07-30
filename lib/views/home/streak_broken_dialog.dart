// Flutter imports:
import 'package:flutter/material.dart';

// Project imports:
import 'package:varnamala/gen/assets.gen.dart';
import 'package:varnamala/l10n/app_strings.dart';
import 'package:varnamala/views/theme.dart';

/// Lightweight dialog shown when [StreakCheckResult.broken] is detected on
/// app open. No streak repair / freeze / monetization — single dismiss CTA.
class StreakBrokenDialog extends StatelessWidget {
  const StreakBrokenDialog({super.key});

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(VarnamalaTheme.radiusLarge),
      ),
      title: Text(AppStrings.homeStreakBrokenTitle),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Assets.images.offFire.image(
            height: 88,
            fit: BoxFit.contain,
            semanticLabel: AppStrings.homeStreakBrokenTitle,
          ),
          const SizedBox(height: 16),
          Text(AppStrings.homeStreakBroken),
        ],
      ),
      actions: [
        FilledButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(AppStrings.commonGotIt),
        ),
      ],
    );
  }
}
