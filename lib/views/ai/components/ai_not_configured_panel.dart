// Flutter imports:
import 'package:flutter/material.dart';

// Package imports:
import 'package:auto_route/auto_route.dart';

// Project imports:
import 'package:turna/core/spacing.dart';
import 'package:turna/core/theme.dart';
import 'package:turna/core/turna_icon_id.dart';
import 'package:turna/l10n/app_strings.dart';
import 'package:turna/routing/routing.gr.dart';
import 'package:turna/views/widgets/turna_icon.dart';

/// Empty-state panel when AI API is not configured. Primary CTA opens config.
class AiNotConfiguredPanel extends StatelessWidget {
  const AiNotConfiguredPanel({
    super.key,
    this.onConfigured,
    this.compact = false,
  });

  final VoidCallback? onConfigured;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.all(compact ? AppSpacing.md : AppSpacing.xl),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TurnaIcon(
            TurnaIconId.spark,
            size: compact ? 36 : 48,
            color: TurnaTheme.brandTeal.withValues(alpha: 0.8),
          ),
          const SizedBox(height: AppSpacing.md),
          Text(
            AppStrings.aiNotConfiguredTitle,
            style: Theme.of(context).textTheme.titleMedium
                ?.copyWith(fontWeight: FontWeight.w700),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: AppSpacing.sm),
          Text(
            AppStrings.aiNotConfiguredBody,
            style: Theme.of(context).textTheme.bodyMedium
                ?.copyWith(color: TurnaTheme.textSecondaryColor(context)),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: AppSpacing.lg),
          FilledButton.icon(
            onPressed: () async {
              await context.router.push(const AiApiConfigRoute());
              onConfigured?.call();
            },
            icon: const TurnaIcon(
              TurnaIconId.wrench,
              size: 18,
              color: TurnaTheme.textOnPrimary,
            ),
            label: Text(AppStrings.aiNotConfiguredCta),
            style: FilledButton.styleFrom(
              backgroundColor: TurnaTheme.brandTeal,
              foregroundColor: TurnaTheme.textOnPrimary,
            ),
          ),
        ],
      ),
    );
  }
}
