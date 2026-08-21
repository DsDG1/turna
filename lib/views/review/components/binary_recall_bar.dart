import 'package:flutter/material.dart';
import 'package:turna/domain/review/recall_outcome.dart';
import 'package:turna/domain/review/review_ledger.dart';
import 'package:turna/l10n/app_strings.dart';
import 'package:turna/views/theme.dart';

/// Unified binary recall action bar.
///
/// Invariant: Only two buttons ("不记得" / "记得"), with optional authoritative interval labels.
class BinaryRecallBar extends StatelessWidget {
  final ValueChanged<RecallOutcome> onOutcome;
  final ReviewPreview? forgottenPreview;
  final ReviewPreview? rememberedPreview;
  final bool enabled;

  const BinaryRecallBar({
    super.key,
    required this.onOutcome,
    this.forgottenPreview,
    this.rememberedPreview,
    this.enabled = true,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: _RecallButton(
            label: AppStrings.reviewBinaryForgotten,
            interval: forgottenPreview?.intervalLabel,
            color: TurnaTheme.error,
            onPressed: enabled ? () => onOutcome(RecallOutcome.forgotten) : null,
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: _RecallButton(
            label: AppStrings.reviewBinaryRemembered,
            interval: rememberedPreview?.intervalLabel,
            color: TurnaTheme.brandTeal,
            onPressed: enabled ? () => onOutcome(RecallOutcome.remembered) : null,
          ),
        ),
      ],
    );
  }
}

class _RecallButton extends StatelessWidget {
  final String label;
  final String? interval;
  final Color color;
  final VoidCallback? onPressed;

  const _RecallButton({
    required this.label,
    this.interval,
    required this.color,
    this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 54,
      child: ElevatedButton(
        onPressed: onPressed,
        // styleFrom treats elevation as a base level (pressed: +6); pin all states flat.
        style: ElevatedButton.styleFrom(
          backgroundColor: color.withValues(alpha: 0.12),
          foregroundColor: color,
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          minimumSize: Size.zero,
          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
            side: BorderSide(color: color.withValues(alpha: 0.35), width: 1.5),
          ),
        ).copyWith(elevation: const WidgetStatePropertyAll<double>(0)),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              label,
              style: const TextStyle(
                fontWeight: FontWeight.w800,
                fontSize: 16,
                height: 1.15,
              ),
            ),
            if (interval != null && interval!.isNotEmpty) ...[
              const SizedBox(height: 2),
              Text(
                interval!,
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                  color: color.withValues(alpha: 0.8),
                  height: 1.15,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
