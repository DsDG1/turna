// Flutter imports:
import 'package:flutter/material.dart';

// Package imports:
import 'package:auto_route/auto_route.dart';
import 'package:provider/provider.dart';

// Project imports:
import 'package:turna/application/cosmetic_provider.dart';
import 'package:turna/application/gems_provider.dart';
import 'package:turna/domain/cosmetics/avatar_ring.dart';
import 'package:turna/l10n/app_strings.dart';
import 'package:turna/views/settings/widgets/settings_common.dart';
import 'package:turna/views/theme.dart';
import 'package:turna/views/widgets/avatar_with_ring.dart';

/// Minimal gem-spend list for avatar rings (settings sub-page).
@RoutePage()
class AvatarRingsPage extends StatelessWidget {
  const AvatarRingsPage({super.key});

  @override
  Widget build(BuildContext context) {
    final cosmetics = context.watch<CosmeticProvider>();
    final gems = context.watch<GemsProvider>().balance;

    return Scaffold(
      backgroundColor: TurnaTheme.surfaceColor(context),
      appBar: AppBar(
        backgroundColor: TurnaTheme.surfaceColor(context),
        elevation: 0,
        centerTitle: true,
        title: Text(AppStrings.cosmeticsTitle),
      ),
      body: ListView(
        padding: const EdgeInsets.only(top: 8, bottom: 24),
        children: [
          SettingsCard(
            children: [
              Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                child: Row(
                  children: [
                    Icon(
                      Icons.diamond_rounded,
                      size: 20,
                      color: TurnaTheme.brandTeal.withValues(alpha: 0.9),
                    ),
                    const SizedBox(width: 10),
                    Text(
                      AppStrings.cosmeticsGemsBalance(gems),
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                            fontWeight: FontWeight.w600,
                            color: TurnaTheme.textSecondaryColor(context),
                          ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          SettingsCard(
            children: [
              for (var i = 0; i < CosmeticCatalog.rings.length; i++) ...[
                if (i > 0) settingsTileDivider(context),
                _RingTile(
                  ring: CosmeticCatalog.rings[i],
                  gems: gems,
                  unlocked: cosmetics.isUnlocked(CosmeticCatalog.rings[i].id),
                  equipped: cosmetics.isEquipped(CosmeticCatalog.rings[i].id),
                  onAction: () => _onAction(
                    context,
                    cosmetics,
                    CosmeticCatalog.rings[i],
                  ),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }

  Future<void> _onAction(
    BuildContext context,
    CosmeticProvider cosmetics,
    AvatarRing ring,
  ) async {
    final result = await cosmetics.unlockAndEquip(ring.id);
    if (!context.mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    switch (result) {
      case CosmeticActionResult.insufficientGems:
        messenger.showSnackBar(
          SnackBar(content: Text(AppStrings.cosmeticsInsufficientGems)),
        );
      case CosmeticActionResult.unlockedAndEquipped:
        messenger.showSnackBar(
          SnackBar(content: Text(AppStrings.cosmeticsRedeemed)),
        );
      case CosmeticActionResult.equipped:
        messenger.showSnackBar(
          SnackBar(content: Text(AppStrings.cosmeticsEquipped)),
        );
      case CosmeticActionResult.unknownId:
        break;
    }
  }
}

class _RingTile extends StatelessWidget {
  const _RingTile({
    required this.ring,
    required this.gems,
    required this.unlocked,
    required this.equipped,
    required this.onAction,
  });

  final AvatarRing ring;
  final int gems;
  final bool unlocked;
  final bool equipped;
  final VoidCallback onAction;

  @override
  Widget build(BuildContext context) {
    final title = AppStrings.cosmeticsRingTitle(ring.id);
    final canAfford = ring.isFree || gems >= ring.price;
    final canAct = unlocked || canAfford;

    return Material(
      color: equipped
          ? TurnaTheme.brandTeal.withValues(alpha: 0.06)
          : Colors.transparent,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        child: Row(
          children: [
            // Equipped: thin teal accent bar.
            Container(
              width: 3,
              height: 44,
              margin: const EdgeInsets.only(right: 10),
              decoration: BoxDecoration(
                color: equipped
                    ? TurnaTheme.brandTeal
                    : Colors.transparent,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            AvatarWithRing(
              radius: 24,
              ring: ring,
              gapColor: TurnaTheme.cardBg(context),
              backgroundColor: TurnaTheme.brandTeal.withValues(alpha: 0.12),
              child: const Icon(
                Icons.person_rounded,
                size: 24,
                color: TurnaTheme.brandTeal,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                          fontWeight: FontWeight.w600,
                        ),
                  ),
                  const SizedBox(height: 3),
                  if (ring.isFree)
                    Text(
                      AppStrings.cosmeticsFree,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: TurnaTheme.textHintColor(context),
                          ),
                    )
                  else
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.diamond_rounded,
                          size: 14,
                          color: canAfford || unlocked
                              ? TurnaTheme.brandTeal.withValues(alpha: 0.85)
                              : TurnaTheme.textHintColor(context),
                        ),
                        const SizedBox(width: 4),
                        Text(
                          AppStrings.cosmeticsRingPrice(ring.price),
                          style:
                              Theme.of(context).textTheme.bodySmall?.copyWith(
                                    color: canAfford || unlocked
                                        ? TurnaTheme.textSecondaryColor(context)
                                        : TurnaTheme.textHintColor(context),
                                    fontWeight: FontWeight.w600,
                                  ),
                        ),
                      ],
                    ),
                ],
              ),
            ),
            if (equipped)
              Text(
                AppStrings.cosmeticsInUse,
                style: Theme.of(context).textTheme.labelLarge?.copyWith(
                      color: TurnaTheme.brandTeal,
                      fontWeight: FontWeight.w700,
                    ),
              )
            else if (unlocked)
              OutlinedButton(
                onPressed: onAction,
                style: OutlinedButton.styleFrom(
                  foregroundColor: TurnaTheme.brandTeal,
                  side: BorderSide(
                    color: TurnaTheme.brandTeal.withValues(alpha: 0.45),
                  ),
                  padding:
                      const EdgeInsets.symmetric(horizontal: 14, vertical: 0),
                  minimumSize: const Size(0, 34),
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  visualDensity: VisualDensity.compact,
                ),
                child: Text(AppStrings.cosmeticsUse),
              )
            else
              FilledButton.tonal(
                onPressed: canAct ? onAction : null,
                style: FilledButton.styleFrom(
                  foregroundColor: TurnaTheme.brandTeal,
                  padding:
                      const EdgeInsets.symmetric(horizontal: 14, vertical: 0),
                  minimumSize: const Size(0, 34),
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  visualDensity: VisualDensity.compact,
                ),
                child: Text(AppStrings.cosmeticsRedeem),
              ),
          ],
        ),
      ),
    );
  }
}
