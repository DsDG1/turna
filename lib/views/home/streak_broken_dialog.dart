// Flutter imports:
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

// Project imports:
import 'package:turna/application/game_provider.dart';
import 'package:turna/gen/assets.gen.dart';
import 'package:turna/l10n/app_strings.dart';
import 'package:turna/core/text_styles.dart';
import 'package:turna/core/theme.dart';

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
    // R18 同构：radius 24 + sectionTitle 标题 + bodyText 正文（与
    // showTurnaConfirmDialog 同一容器语言；保护券双操作保留原行为）。
    return AlertDialog(
      backgroundColor: TurnaTheme.cardBg(context),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(TurnaTheme.radiusXLarge),
      ),
      title: Text(
        AppStrings.homeStreakBrokenTitle,
        style: AppTextStyles.sectionTitle(context),
      ),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Assets.images.offFire.image(
            height: 88,
            fit: BoxFit.contain,
            semanticLabel: AppStrings.homeStreakBrokenTitle,
          ),
          const SizedBox(height: 16),
          Text(AppStrings.homeStreakBroken,
              style: AppTextStyles.bodyText(context)),
          if (streak?.canProtectPendingBreak ?? false) ...[
            const SizedBox(height: 12),
            Text(
              AppStrings.streakVoucherExplain(
                  streak!.pendingPreviousStreak ?? 0),
              style: AppTextStyles.captionSm(context),
            ),
          ],
        ],
      ),
      actions: [
        if (streak?.canProtectPendingBreak ?? false)
          FutureBuilder<int>(
            future: streak!.voucherBalance,
            builder: (context, snapshot) {
              final count = snapshot.data ?? 0;
              return OutlinedButton.icon(
                onPressed: count <= 0 || _usingVoucher
                    ? null
                    : () async {
                        setState(() => _usingVoucher = true);
                        final protected = await streak.protectPendingBreak();
                        if (!context.mounted) return;
                        if (protected) {
                          Navigator.of(context).pop();
                        } else {
                          setState(() => _usingVoucher = false);
                        }
                      },
                icon: const Icon(Icons.shield_rounded),
                label: Text(
                  _usingVoucher
                      ? AppStrings.streakVoucherApplying
                      : AppStrings.streakVoucherUse(count),
                ),
              );
            },
          ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(AppStrings.commonGotIt),
        ),
      ],
    );
  }
}
