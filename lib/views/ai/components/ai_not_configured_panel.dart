// Flutter imports:
import 'package:flutter/material.dart';

// Project imports:
import 'package:turna/l10n/app_strings.dart';
import 'package:turna/views/ai/ai_api_config_page.dart';
import 'package:turna/views/theme.dart';

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
      padding: EdgeInsets.all(compact ? 12 : 24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.auto_awesome_outlined,
            size: compact ? 36 : 48,
            color: TurnaTheme.amethystLeague.withValues(alpha: 0.8),
          ),
          const SizedBox(height: 12),
          Text(
            AppStrings.aiNotConfiguredTitle,
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w700,
                ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 8),
          Text(
            AppStrings.aiNotConfiguredBody,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: TurnaTheme.textSecondaryColor(context),
                ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 16),
          FilledButton.icon(
            onPressed: () async {
              await Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => const AiApiConfigPage(),
                ),
              );
              onConfigured?.call();
            },
            icon: const Icon(Icons.settings_rounded),
            label: Text(AppStrings.aiNotConfiguredCta),
            style: FilledButton.styleFrom(
              backgroundColor: TurnaTheme.brandTeal,
            ),
          ),
        ],
      ),
    );
  }
}
