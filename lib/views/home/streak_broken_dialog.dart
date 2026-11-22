// Flutter imports:
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

// Project imports:
import 'package:turna/application/game_provider.dart';
import 'package:turna/core/spacing.dart';
import 'package:turna/core/text_styles.dart';
import 'package:turna/core/theme.dart';
import 'package:turna/core/turna_icon_id.dart';
import 'package:turna/l10n/app_strings.dart';
import 'package:turna/views/widgets/turna_geometry.dart';
import 'package:turna/views/widgets/turna_icon.dart';
import 'package:turna/views/widgets/turna_sheet.dart';

/// Broken-streak explanation with an honest, optional display-only voucher.
class StreakBrokenDialog extends StatefulWidget {
  const StreakBrokenDialog({super.key});

  @override
  State<StreakBrokenDialog> createState() => _StreakBrokenDialogState();
}

class _StreakBrokenDialogState extends State<StreakBrokenDialog> {
  bool _usingVoucher = false;

  @override
  Widget build(BuildContext context) {
    GameProvider? game;
    try {
      game = context.read<GameProvider>();
    } catch (_) {
      // Keep the legacy explanatory dialog usable in minimal widget trees.
    }
    final streak = game?.streakProvider;
    final canProtect = streak?.canProtectPendingBreak ?? false;

    Widget buildPanel({int? voucherCount}) {
      return TurnaDialogPanel(
        title: AppStrings.homeStreakBrokenTitle,
        body: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const TurnaGeometry(
              kind: TurnaGeometryKind.brokenStreak,
              size: 96,
              accent: TurnaTheme.anatolianClay,
            ),
            const SizedBox(height: AppSpacing.lg),
            Text(
              AppStrings.homeStreakBroken,
              style: AppTextStyles.bodyText(context),
            ),
            if (canProtect) ...[
              const SizedBox(height: AppSpacing.md),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Padding(
                    padding: EdgeInsets.only(top: 2),
                    child: TurnaIcon(
                      TurnaIconId.shield,
                      size: 16,
                      color: TurnaTheme.brandTeal,
                    ),
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  Expanded(
                    child: Text(
                      AppStrings.streakVoucherExplain(
                        streak!.pendingPreviousStreak ?? 0,
                      ),
                      style: AppTextStyles.captionSm(context),
                    ),
                  ),
                ],
              ),
            ],
          ],
        ),
        actions: [
          if (canProtect)
            TurnaSheetAction(
              label: _usingVoucher
                  ? AppStrings.streakVoucherApplying
                  : AppStrings.streakVoucherUse(voucherCount ?? 0),
              onPressed: (voucherCount ?? 0) <= 0 || _usingVoucher
                  ? null
                  : () async {
                      setState(() => _usingVoucher = true);
                      final protected = await streak!.protectPendingBreak();
                      if (!context.mounted) return;
                      if (protected) {
                        Navigator.of(context).pop();
                      } else {
                        setState(() => _usingVoucher = false);
                      }
                    },
            ),
          TurnaSheetAction(
            label: AppStrings.commonGotIt,
            primary: true,
            onPressed: () => Navigator.of(context).pop(),
          ),
        ],
      );
    }

    if (!canProtect) return buildPanel();
    return FutureBuilder<int>(
      future: streak!.voucherBalance,
      builder: (context, snapshot) => buildPanel(voucherCount: snapshot.data),
    );
  }
}
