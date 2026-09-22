// Flutter imports:
import 'package:flutter/material.dart';

// Package imports:
import 'package:auto_route/auto_route.dart';

// Project imports:
import 'package:turna/application/ai/ai_error_mapper.dart';
import 'package:turna/l10n/app_strings.dart';
import 'package:turna/routing/routing.gr.dart';
import 'package:turna/core/theme.dart';

/// Maps [AiErrorMapping] flags onto retry / configure actions.
class AiErrorBanner extends StatelessWidget {
  const AiErrorBanner({
    super.key,
    required this.mapping,
    this.onRetry,
  });

  final AiErrorMapping mapping;
  final VoidCallback? onRetry;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            mapping.message,
            style: const TextStyle(color: TurnaTheme.error),
          ),
          Row(
            children: [
              if (mapping.canRetry && onRetry != null)
                TextButton(
                  onPressed: onRetry,
                  child: Text(AppStrings.aiRetry),
                ),
              if (mapping.canConfigure)
                TextButton(
                  onPressed: () =>
                      context.router.push(const AiApiConfigRoute()),
                  child: Text(AppStrings.aiGoToSettings),
                ),
            ],
          ),
        ],
      ),
    );
  }
}
