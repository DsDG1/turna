import 'package:flutter/material.dart';
import 'package:turna/core/theme.dart';
import 'package:turna/views/widgets/turna_geometry.dart';
import 'package:turna/views/widgets/turna_page_content.dart';

class PracticeEmptyState extends StatelessWidget {
  final IconData icon;
  final Color? accentColor;
  final String title;
  final String? message;
  final String? actionLabel;
  final VoidCallback? onAction;

  const PracticeEmptyState({
    super.key,
    this.icon = Icons.check_circle_rounded,
    this.accentColor,
    required this.title,
    this.message,
    this.actionLabel,
    this.onAction,
  });

  @override
  Widget build(BuildContext context) {
    final accent = accentColor ?? TurnaTheme.brandTeal;

    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
        child: TurnaPageContent(
          maxWidth: 480,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TurnaGeometryBadge(
                icon: icon,
                accent: accent,
                kind: TurnaGeometryKind.achievement,
              ),
              const SizedBox(height: 20),
              Text(
                title,
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.w800,
                    ),
              ),
              if (message != null && message!.isNotEmpty) ...[
                const SizedBox(height: 8),
                Text(
                  message!,
                  textAlign: TextAlign.center,
                  style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                        color: TurnaTheme.textSecondaryColor(context),
                        height: 1.5,
                      ),
                ),
              ],
              if (actionLabel != null && onAction != null) ...[
                const SizedBox(height: 24),
                ConstrainedBox(
                  constraints: const BoxConstraints(minHeight: 48),
                  child: FilledButton.tonal(
                    onPressed: onAction,
                    child: Text(actionLabel!),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
