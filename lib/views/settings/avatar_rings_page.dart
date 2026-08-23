import 'package:auto_route/auto_route.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:turna/application/accessibility_capabilities.dart';
import 'package:turna/application/cosmetic_provider.dart';
import 'package:turna/application/gems_provider.dart';
import 'package:turna/data/gem_ledger_dao.dart';
import 'package:turna/domain/cosmetics/avatar_ring.dart';
import 'package:turna/domain/cosmetics/cosmetic_item.dart';
import 'package:turna/l10n/app_strings.dart';
import 'package:turna/views/settings/widgets/settings_common.dart';
import 'package:turna/views/theme.dart';
import 'package:turna/views/widgets/avatar_with_ring.dart';

/// Slot-based cosmetic shop. The historical route name is retained so old
/// deep links continue to work.
@RoutePage()
class AvatarRingsPage extends StatefulWidget {
  const AvatarRingsPage({super.key});

  @override
  State<AvatarRingsPage> createState() => _AvatarRingsPageState();
}

class _AvatarRingsPageState extends State<AvatarRingsPage> {
  static const _visibleSlots = [
    CosmeticSlot.avatarRing,
    CosmeticSlot.profileTheme,
    CosmeticSlot.completionEffect,
  ];

  final Set<String> _busyItems = {};
  int? _voucherCount;
  int? _voucherPurchasesThisMonth;
  bool _voucherBusy = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadVoucherInfo());
  }

  Future<void> _loadVoucherInfo() async {
    if (!mounted) return;
    final gems = context.read<GemsProvider>();
    final values = await Future.wait([
      gems.streakVoucherBalance,
      gems.streakVoucherPurchasesInMonth(),
    ]);
    if (!mounted) return;
    setState(() {
      _voucherCount = values[0];
      _voucherPurchasesThisMonth = values[1];
    });
  }

  Future<void> _buyVoucher() async {
    if (_voucherBusy) return;
    setState(() => _voucherBusy = true);
    final result = await context.read<GemsProvider>().purchaseStreakVoucher(
          idempotencyKey:
              'voucher-shop-${DateTime.now().microsecondsSinceEpoch}',
        );
    await _loadVoucherInfo();
    if (!mounted) return;
    setState(() => _voucherBusy = false);
    final message = switch (result) {
      GemConsumablePurchaseResult.success => '已获得 1 张连续学习保护券',
      GemConsumablePurchaseResult.insufficientFunds =>
        AppStrings.cosmeticsInsufficientGems,
      GemConsumablePurchaseResult.monthlyLimitReached => '本月最多购买 2 张保护券',
    };
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    final cosmetics = context.watch<CosmeticProvider>();
    final gems = context.watch<GemsProvider>().balance;
    final voucherLimitReached = (_voucherPurchasesThisMonth ?? 0) >=
        GemsProvider.streakVoucherMonthlyPurchaseLimit;

    return DefaultTabController(
      length: _visibleSlots.length,
      child: Scaffold(
        backgroundColor: TurnaTheme.surfaceColor(context),
        appBar: AppBar(
          backgroundColor: TurnaTheme.surfaceColor(context),
          elevation: 0,
          centerTitle: true,
          title: Text(AppStrings.cosmeticsTitle),
          bottom: TabBar(
            tabs: [
              for (final slot in _visibleSlots)
                Tab(text: AppStrings.cosmeticsSlotTitle(slot.name)),
            ],
          ),
        ),
        body: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
              child: SettingsCard(
                children: [
                  Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 12,
                    ),
                    child: Row(
                      children: [
                        const Icon(
                          Icons.diamond_rounded,
                          size: 20,
                          color: TurnaTheme.brandTeal,
                        ),
                        const SizedBox(width: 10),
                        Text(
                          AppStrings.cosmeticsGemsBalance(gems),
                          style:
                              Theme.of(context).textTheme.bodyMedium?.copyWith(
                                    fontWeight: FontWeight.w700,
                                  ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
              child: SettingsCard(
                children: [
                  SettingsTile(
                    icon: Icons.shield_rounded,
                    title: '连续学习保护券',
                    subtitle: voucherLimitReached
                        ? '持有 ${_voucherCount ?? 0} 张 · '
                            '本月购买已达上限 '
                            '${_voucherPurchasesThisMonth ?? 0}/'
                            '${GemsProvider.streakVoucherMonthlyPurchaseLimit} · '
                            '只保护连续显示，不修改学习记录'
                        : '持有 ${_voucherCount ?? 0} 张 · '
                            '本月已购 ${_voucherPurchasesThisMonth ?? 0}/'
                            '${GemsProvider.streakVoucherMonthlyPurchaseLimit} · '
                            '只保护连续显示，不修改学习记录',
                    trailing: FilledButton.tonalIcon(
                      key: const Key('streak-voucher-purchase'),
                      onPressed: _voucherBusy || voucherLimitReached
                          ? null
                          : _buyVoucher,
                      icon: _voucherBusy
                          ? const SizedBox.square(
                              dimension: 15,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.diamond_rounded, size: 16),
                      label: Text('${GemsProvider.streakVoucherPrice}'),
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              child: TabBarView(
                children: [
                  for (final slot in _visibleSlots)
                    _CatalogList(
                      items: CosmeticCatalog.itemsForSlot(slot),
                      gems: gems,
                      cosmetics: cosmetics,
                      busyItems: _busyItems,
                      onAction: _onAction,
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _onAction(CosmeticItem item) async {
    if (_busyItems.contains(item.id)) return;
    setState(() => _busyItems.add(item.id));
    final result =
        await context.read<CosmeticProvider>().unlockAndEquipItem(item.id);
    if (!mounted) return;
    setState(() => _busyItems.remove(item.id));
    final message = switch (result) {
      CosmeticActionResult.insufficientGems =>
        AppStrings.cosmeticsInsufficientGems,
      CosmeticActionResult.unlockedAndEquipped => AppStrings.cosmeticsRedeemed,
      CosmeticActionResult.equipped => AppStrings.cosmeticsEquipped,
      CosmeticActionResult.unknownId => '',
    };
    if (message.isNotEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(message)),
      );
    }
  }
}

class _CatalogList extends StatelessWidget {
  const _CatalogList({
    required this.items,
    required this.gems,
    required this.cosmetics,
    required this.busyItems,
    required this.onAction,
  });

  final List<CosmeticItem> items;
  final int gems;
  final CosmeticProvider cosmetics;
  final Set<String> busyItems;
  final ValueChanged<CosmeticItem> onAction;

  @override
  Widget build(BuildContext context) {
    return ListView(
      key: PageStorageKey(items.isEmpty ? 'empty' : items.first.slot.name),
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
      children: [
        SettingsCard(
          children: [
            for (var i = 0; i < items.length; i++) ...[
              if (i > 0) settingsTileDivider(context),
              _CosmeticTile(
                item: items[i],
                gems: gems,
                unlocked: cosmetics.isUnlocked(items[i].id),
                equipped: cosmetics.isItemEquipped(items[i].id),
                busy: busyItems.contains(items[i].id),
                onAction: () => onAction(items[i]),
              ),
            ],
          ],
        ),
      ],
    );
  }
}

class _CosmeticTile extends StatelessWidget {
  const _CosmeticTile({
    required this.item,
    required this.gems,
    required this.unlocked,
    required this.equipped,
    required this.busy,
    required this.onAction,
  });

  final CosmeticItem item;
  final int gems;
  final bool unlocked;
  final bool equipped;
  final bool busy;
  final VoidCallback onAction;

  @override
  Widget build(BuildContext context) {
    final canAfford = item.isFree || gems >= item.price;
    final enabled = !busy && (unlocked || canAfford);
    final highContrast = accessibilityOf(context).highContrast;
    final largeText = MediaQuery.textScalerOf(context).scale(1) >= 1.5;
    final stateLabel = equipped
        ? AppStrings.cosmeticsInUse
        : unlocked
            ? AppStrings.cosmeticsOwned
            : canAfford
                ? AppStrings.cosmeticsRedeem
                : AppStrings.cosmeticsInsufficientGems;
    return Semantics(
      label: '${AppStrings.cosmeticsItemTitle(item.id)}，'
          '${equipped ? AppStrings.cosmeticsInUse : unlocked ? AppStrings.cosmeticsOwned : AppStrings.cosmeticsRingPrice(item.price)}',
      button: !equipped,
      enabled: enabled,
      value: stateLabel,
      child: Material(
        color: equipped
            ? TurnaTheme.brandTeal.withValues(alpha: 0.09)
            : Colors.transparent,
        shape: RoundedRectangleBorder(
          side: BorderSide(
            color: equipped || highContrast
                ? TurnaTheme.textPrimaryColor(context)
                : TurnaTheme.statCardBorder(context),
            width: highContrast ? 2 : 1,
          ),
          borderRadius: BorderRadius.circular(TurnaTheme.radiusMedium),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
          child: largeText
              ? Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _ItemPreview(item: item),
                        const SizedBox(width: 12),
                        Expanded(child: _details(context, canAfford)),
                      ],
                    ),
                    const SizedBox(height: 12),
                    _action(enabled),
                  ],
                )
              : Row(
                  children: [
                    _ItemPreview(item: item),
                    const SizedBox(width: 12),
                    Expanded(child: _details(context, canAfford)),
                    const SizedBox(width: 8),
                    _action(enabled),
                  ],
                ),
        ),
      ),
    );
  }

  Widget _details(BuildContext context, bool canAfford) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          AppStrings.cosmeticsItemTitle(item.id),
          style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                fontWeight: FontWeight.w700,
              ),
        ),
        const SizedBox(height: 4),
        Wrap(
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            Icon(
              unlocked ? Icons.check_circle : Icons.diamond_rounded,
              size: 15,
              color: unlocked || canAfford
                  ? TurnaTheme.brandTeal
                  : TurnaTheme.textHintColor(context),
            ),
            const SizedBox(width: 4),
            Text(
              item.isFree
                  ? AppStrings.cosmeticsFree
                  : unlocked
                      ? AppStrings.cosmeticsOwned
                      : AppStrings.cosmeticsRingPrice(item.price),
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _action(bool enabled) {
    if (equipped) {
      return Chip(
        avatar: const Icon(Icons.check, size: 16),
        label: Text(AppStrings.cosmeticsInUse),
      );
    }
    return FilledButton.tonal(
      onPressed: enabled ? onAction : null,
      child: busy
          ? const SizedBox.square(
              dimension: 16,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          : Text(
              unlocked ? AppStrings.cosmeticsUse : AppStrings.cosmeticsRedeem,
            ),
    );
  }
}

class _ItemPreview extends StatelessWidget {
  const _ItemPreview({required this.item});

  final CosmeticItem item;

  @override
  Widget build(BuildContext context) {
    if (item.slot == CosmeticSlot.avatarRing) {
      return AvatarWithRing(
        radius: 23,
        ring: CosmeticCatalog.ringById(item.id),
        child: const Icon(Icons.person_rounded, color: TurnaTheme.brandTeal),
      );
    }
    return Container(
      width: 52,
      height: 52,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            item.accentColor ?? TurnaTheme.brandTeal,
            item.secondaryColor ??
                (item.accentColor ?? TurnaTheme.brandTeal)
                    .withValues(alpha: 0.45),
          ],
        ),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: TurnaTheme.textPrimaryColor(context)),
      ),
      child: Icon(item.icon, color: Colors.white),
    );
  }
}
