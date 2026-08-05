// Flutter imports:
import 'package:flutter/material.dart';

// Project imports:
import 'package:turna/application/ai/ai_explain_prefs.dart';
import 'package:turna/views/theme.dart';

/// Horizontal wrap of quick-follow-up chips. Tapping calls [onChip] with the
/// chip label (equals an ask turn).
class AiQuickChipsBar extends StatelessWidget {
  const AiQuickChipsBar({
    super.key,
    required this.onChip,
    this.hasUserAnswer = false,
    this.enabled = true,
  });

  final ValueChanged<String> onChip;
  final bool hasUserAnswer;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    final chips = AiQuickChips.forContext(hasUserAnswer: hasUserAnswer);
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      child: Row(
        children: [
          for (final label in chips) ...[
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: ActionChip(
                label: Text(label),
                tooltip: label,
                onPressed: enabled ? () => onChip(label) : null,
                backgroundColor: TurnaTheme.cardBg(context),
                side: BorderSide(
                  color: TurnaTheme.brandTeal.withValues(alpha: 0.35),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
