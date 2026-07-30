// Flutter imports:
import 'package:flutter/material.dart';

// Package imports:
import 'package:provider/provider.dart';

// Project imports:
import 'package:varnamala/application/fun_provider.dart';
import 'package:varnamala/l10n/app_strings.dart';
import 'package:varnamala/views/settings/widgets/settings_common.dart';
import 'package:varnamala/views/theme.dart';

/// A switch tile bound to [FunProvider], mirroring [AccessibilityToggleTile]
/// (which is bound to [AccessibilityProvider]).
class FunToggleTile extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final bool Function(FunProvider) valueSelector;
  final void Function(FunProvider, bool) onChanged;

  const FunToggleTile({
    super.key,
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.valueSelector,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final value = context.select<FunProvider, bool>(
      (fun) => valueSelector(fun),
    );

    return SettingsTile(
      icon: icon,
      title: title,
      subtitle: subtitle,
      trailing: settingsAdaptiveSwitch(
        value: value,
        onChanged: (newValue) =>
            onChanged(context.read<FunProvider>(), newValue),
      ),
    );
  }
}

/// The "Fun Lab" settings sub-page — joke cheat features presented with
/// self-deprecating humor.
class SettingsFunSection extends StatelessWidget {
  const SettingsFunSection({super.key});

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const _WarningBanner(),
        const SizedBox(height: 12),
        SettingsCard(
          children: [
            FunToggleTile(
              icon: Icons.videogame_asset_rounded,
              title: AppStrings.settingsFunAutoAnswerTitle,
              subtitle: AppStrings.settingsFunAutoAnswerSubtitle,
              valueSelector: (p) => p.autoAnswer,
              onChanged: (p, v) => _onAutoAnswerToggled(context, p, v),
            ),
            settingsTileDivider(context),
            SettingsActionTile(
              icon: Icons.star_rounded,
              title: AppStrings.settingsFunMaxScoreTitle,
              subtitle: AppStrings.settingsFunMaxScoreSubtitle,
              onTap: (context) => _confirmCheat(
                context,
                title: AppStrings.settingsFunMaxScoreDialogTitle,
                message: AppStrings.settingsFunMaxScoreDialogMessage,
                confirmText: AppStrings.settingsFunMaxScoreConfirm,
                onConfirm: (ctx) async {
                  await ctx.read<FunProvider>().cheatMaxScore();
                  if (ctx.mounted) {
                    _showSnack(ctx, AppStrings.settingsFunMaxScoreDone);
                  }
                },
              ),
            ),
            settingsTileDivider(context),
            SettingsActionTile(
              icon: Icons.diamond_rounded,
              title: AppStrings.settingsFunMaxGemsTitle,
              subtitle: AppStrings.settingsFunMaxGemsSubtitle,
              onTap: (context) => _confirmCheat(
                context,
                title: AppStrings.settingsFunMaxGemsDialogTitle,
                message: AppStrings.settingsFunMaxGemsDialogMessage,
                confirmText: AppStrings.settingsFunMaxGemsConfirm,
                onConfirm: (ctx) async {
                  await ctx.read<FunProvider>().cheatMaxGems();
                  if (ctx.mounted) {
                    _showSnack(ctx, AppStrings.settingsFunMaxGemsDone);
                  }
                },
              ),
            ),
            settingsTileDivider(context),
            SettingsActionTile(
              icon: Icons.emoji_events_rounded,
              title: AppStrings.settingsFunAllAchievementsTitle,
              subtitle: AppStrings.settingsFunAllAchievementsSubtitle,
              onTap: (context) => _confirmCheat(
                context,
                title: AppStrings.settingsFunAllAchievementsDialogTitle,
                message: AppStrings.settingsFunAllAchievementsDialogMessage,
                confirmText: AppStrings.settingsFunAllAchievementsConfirm,
                onConfirm: (ctx) async {
                  await ctx.read<FunProvider>().cheatUnlockAllAchievements();
                  if (ctx.mounted) {
                    _showSnack(ctx, AppStrings.settingsFunAllAchievementsDone);
                  }
                },
              ),
            ),
          ],
        ),
        const SizedBox(height: 24),
      ],
    );
  }

  void _onAutoAnswerToggled(
    BuildContext context,
    FunProvider provider,
    bool value,
  ) async {
    await provider.setAutoAnswer(value);
    if (!context.mounted) return;
    if (value) {
      _showSnack(context, AppStrings.settingsFunAutoAnswerOn);
    } else {
      _showSnack(context, AppStrings.settingsFunAutoAnswerOff);
    }
  }

  Future<void> _confirmCheat(
    BuildContext context, {
    required String title,
    required String message,
    required String confirmText,
    required Future<void> Function(BuildContext) onConfirm,
  }) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => SettingsConfirmDialog(
        title: title,
        message: message,
        confirmText: confirmText,
      ),
    );
    if (confirmed == true && context.mounted) {
      await onConfirm(context);
    }
  }

  void _showSnack(BuildContext context, String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message)),
    );
  }
}

class _WarningBanner extends StatelessWidget {
  const _WarningBanner();

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: VarnamalaTheme.error.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(VarnamalaTheme.radiusLarge),
        border: Border.all(
          color: VarnamalaTheme.error.withValues(alpha: 0.2),
        ),
      ),
      child: Row(
        children: [
          const Icon(
            Icons.warning_amber_rounded,
            color: VarnamalaTheme.error,
            size: 22,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              AppStrings.settingsFunWarning,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: VarnamalaTheme.textSecondaryColor(context),
                    height: 1.4,
                  ),
            ),
          ),
        ],
      ),
    );
  }
}
