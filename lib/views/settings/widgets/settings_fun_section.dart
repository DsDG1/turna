// Flutter imports:
import 'package:flutter/material.dart';

// Package imports:
import 'package:provider/provider.dart';

// Project imports:
import 'package:turna/application/fun_lab_snapshot_service.dart';
import 'package:turna/application/fun_provider.dart';
import 'package:turna/l10n/app_strings.dart';
import 'package:turna/views/settings/widgets/settings_common.dart';
import 'package:turna/views/theme.dart';

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
    return ProviderBoundToggleTile<FunProvider>(
      icon: icon,
      title: title,
      subtitle: subtitle,
      valueSelector: valueSelector,
      onChanged: onChanged,
    );
  }
}

/// The "Fun Lab" settings sub-page — joke cheat features presented with
/// self-deprecating humor.
class SettingsFunSection extends StatelessWidget {
  const SettingsFunSection({super.key});

  @override
  Widget build(BuildContext context) {
    final fun = context.watch<FunProvider>();
    final unavailable = fun.isBusy || !fun.snapshotLoaded;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const _WarningBanner(),
        const SizedBox(height: 12),
        SettingsSectionTitle(
          icon: Icons.inventory_2_rounded,
          title: AppStrings.settingsFunSnapshotSection,
        ),
        const SizedBox(height: 4),
        SettingsCard(
          children: [
            SettingsTile(
              icon: fun.hasSnapshot
                  ? Icons.cloud_done_rounded
                  : Icons.cloud_off_rounded,
              title: AppStrings.settingsFunSnapshotStatusTitle,
              subtitle: _snapshotSubtitle(fun),
              trailing: unavailable
                  ? const SizedBox.square(
                      dimension: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : Icon(
                      fun.hasSnapshot
                          ? Icons.check_circle_rounded
                          : Icons.lock_outline_rounded,
                      color: fun.hasSnapshot
                          ? TurnaTheme.brandTeal
                          : TurnaTheme.textHint,
                    ),
            ),
            settingsTileDivider(context),
            SettingsActionTile(
              icon: Icons.save_rounded,
              title: fun.hasSnapshot
                  ? AppStrings.settingsFunSnapshotReplaceTitle
                  : AppStrings.settingsFunSnapshotCreateTitle,
              subtitle: fun.hasSnapshot
                  ? AppStrings.settingsFunSnapshotReplaceSubtitle
                  : AppStrings.settingsFunSnapshotCreateSubtitle,
              enabled: !unavailable,
              onTap: _createSnapshot,
            ),
            if (fun.hasSnapshot) ...[
              settingsTileDivider(context),
              SettingsActionTile(
                icon: Icons.restore_rounded,
                title: AppStrings.settingsFunSnapshotRestoreTitle,
                subtitle: AppStrings.settingsFunSnapshotRestoreSubtitle,
                enabled: !unavailable,
                onTap: _restoreSnapshot,
              ),
              settingsTileDivider(context),
              SettingsActionTile(
                icon: Icons.delete_outline_rounded,
                title: AppStrings.settingsFunSnapshotDeleteTitle,
                subtitle: AppStrings.settingsFunSnapshotDeleteSubtitle,
                enabled: !unavailable,
                onTap: _deleteSnapshot,
              ),
            ],
          ],
        ),
        const SizedBox(height: 16),
        SettingsSectionTitle(
          icon: Icons.science_rounded,
          title: AppStrings.settingsFunActionsSection,
        ),
        const SizedBox(height: 4),
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
              icon: Icons.more_time_rounded,
              title: AppStrings.settingsFunPostponeTitle,
              subtitle: AppStrings.settingsFunPostponeSubtitle,
              enabled: !unavailable,
              onTap: _postponeReviews,
            ),
            settingsTileDivider(context),
            SettingsActionTile(
              icon: Icons.star_rounded,
              title: AppStrings.settingsFunMaxScoreTitle,
              subtitle: AppStrings.settingsFunMaxScoreSubtitle,
              enabled: !unavailable,
              onTap: (context) => _guardedCheat(
                context,
                title: AppStrings.settingsFunMaxScoreDialogTitle,
                message: AppStrings.settingsFunMaxScoreDialogMessage,
                confirmText: AppStrings.settingsFunMaxScoreConfirm,
                successMessage: AppStrings.settingsFunMaxScoreDone,
                action: (p) => p.cheatMaxScore(),
              ),
            ),
            settingsTileDivider(context),
            SettingsActionTile(
              icon: Icons.diamond_rounded,
              title: AppStrings.settingsFunMaxGemsTitle,
              subtitle: AppStrings.settingsFunMaxGemsSubtitle,
              enabled: !unavailable,
              onTap: (context) => _guardedCheat(
                context,
                title: AppStrings.settingsFunMaxGemsDialogTitle,
                message: AppStrings.settingsFunMaxGemsDialogMessage,
                confirmText: AppStrings.settingsFunMaxGemsConfirm,
                successMessage: AppStrings.settingsFunMaxGemsDone,
                action: (p) => p.cheatMaxGems(),
              ),
            ),
            settingsTileDivider(context),
            SettingsActionTile(
              icon: Icons.emoji_events_rounded,
              title: AppStrings.settingsFunAllAchievementsTitle,
              subtitle: AppStrings.settingsFunAllAchievementsSubtitle,
              enabled: !unavailable,
              onTap: (context) => _guardedCheat(
                context,
                title: AppStrings.settingsFunAllAchievementsDialogTitle,
                message: AppStrings.settingsFunAllAchievementsDialogMessage,
                confirmText: AppStrings.settingsFunAllAchievementsConfirm,
                successMessage: AppStrings.settingsFunAllAchievementsDone,
                action: (p) => p.cheatUnlockAllAchievements(),
              ),
            ),
          ],
        ),
        const SizedBox(height: 24),
      ],
    );
  }

  String _snapshotSubtitle(FunProvider provider) {
    if (!provider.snapshotLoaded) return AppStrings.settingsFunSnapshotLoading;
    final snapshot = provider.snapshot;
    if (snapshot == null) return AppStrings.settingsFunSnapshotEmpty;
    final d = snapshot.createdAt;
    final time = '${d.year.toString().padLeft(4, '0')}-'
        '${d.month.toString().padLeft(2, '0')}-'
        '${d.day.toString().padLeft(2, '0')} '
        '${d.hour.toString().padLeft(2, '0')}:'
        '${d.minute.toString().padLeft(2, '0')}';
    return AppStrings.settingsFunSnapshotReady(time, snapshot.srsItemCount);
  }

  Future<void> _createSnapshot(BuildContext context) async {
    final provider = context.read<FunProvider>();
    if (provider.isBusy) return;
    final replacing = provider.hasSnapshot;
    final confirmed = await _confirm(
      context,
      title: replacing
          ? AppStrings.settingsFunSnapshotReplaceDialogTitle
          : AppStrings.settingsFunSnapshotCreateDialogTitle,
      message: replacing
          ? AppStrings.settingsFunSnapshotReplaceDialogMessage
          : AppStrings.settingsFunSnapshotCreateDialogMessage,
      confirmText: replacing
          ? AppStrings.settingsFunSnapshotReplaceConfirm
          : AppStrings.settingsFunSnapshotCreateConfirm,
    );
    if (!confirmed || !context.mounted) return;
    await _run(
      context,
      provider.createSnapshot,
      AppStrings.settingsFunSnapshotCreated,
    );
  }

  Future<void> _restoreSnapshot(BuildContext context) async {
    final confirmed = await _confirm(
      context,
      title: AppStrings.settingsFunSnapshotRestoreDialogTitle,
      message: AppStrings.settingsFunSnapshotRestoreDialogMessage,
      confirmText: AppStrings.settingsFunSnapshotRestoreConfirm,
    );
    if (!confirmed || !context.mounted) return;
    try {
      await context.read<FunProvider>().restoreSnapshot();
      if (context.mounted) {
        _showSnack(context, AppStrings.settingsFunSnapshotRestored);
      }
    } on FunLabSnapshotContentChanged {
      if (context.mounted) {
        _showSnack(context, AppStrings.settingsFunSnapshotContentChanged);
      }
    } catch (error) {
      if (context.mounted) {
        _showSnack(context, AppStrings.settingsFunOperationFailed(error));
      }
    }
  }

  Future<void> _deleteSnapshot(BuildContext context) async {
    final confirmed = await _confirm(
      context,
      title: AppStrings.settingsFunSnapshotDeleteDialogTitle,
      message: AppStrings.settingsFunSnapshotDeleteDialogMessage,
      confirmText: AppStrings.settingsFunSnapshotDeleteConfirm,
    );
    if (!confirmed || !context.mounted) return;
    await _run(
      context,
      context.read<FunProvider>().deleteSnapshot,
      AppStrings.settingsFunSnapshotDeleted,
    );
  }

  Future<void> _postponeReviews(BuildContext context) async {
    final provider = context.read<FunProvider>();
    if (!await _ensureSnapshot(context, provider)) return;
    try {
      final count = await provider.countPostponableReviews();
      if (!context.mounted) return;
      final confirmed = await _confirm(
        context,
        title: AppStrings.settingsFunPostponeDialogTitle,
        message: AppStrings.settingsFunPostponeDialogMessage(count),
        confirmText: AppStrings.settingsFunPostponeConfirm,
      );
      if (!confirmed || !context.mounted) return;
      final affected = await provider.postponeAllReviewsOneDay();
      if (context.mounted) {
        _showSnack(context, AppStrings.settingsFunPostponeDone(affected));
      }
    } catch (error) {
      if (context.mounted) {
        _showSnack(context, AppStrings.settingsFunOperationFailed(error));
      }
    }
  }

  Future<void> _guardedCheat(
    BuildContext context, {
    required String title,
    required String message,
    required String confirmText,
    required String successMessage,
    required Future<void> Function(FunProvider) action,
  }) async {
    final provider = context.read<FunProvider>();
    if (!await _ensureSnapshot(context, provider)) return;
    if (!context.mounted) return;
    final confirmed = await _confirm(
      context,
      title: title,
      message: message,
      confirmText: confirmText,
    );
    if (!confirmed || !context.mounted) return;
    await _run(context, () => action(provider), successMessage);
  }

  Future<bool> _ensureSnapshot(
    BuildContext context,
    FunProvider provider,
  ) async {
    if (provider.hasSnapshot) return true;
    final create = await _confirm(
      context,
      title: AppStrings.settingsFunSnapshotRequiredTitle,
      message: AppStrings.settingsFunSnapshotRequiredMessage,
      confirmText: AppStrings.settingsFunSnapshotCreateConfirm,
    );
    if (create && context.mounted) {
      await _run(
        context,
        provider.createSnapshot,
        AppStrings.settingsFunSnapshotCreated,
      );
    }
    return false;
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

  Future<bool> _confirm(
    BuildContext context, {
    required String title,
    required String message,
    required String confirmText,
  }) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => SettingsConfirmDialog(
        title: title,
        message: message,
        confirmText: confirmText,
      ),
    );
    return confirmed == true;
  }

  Future<void> _run(
    BuildContext context,
    Future<void> Function() action,
    String successMessage,
  ) async {
    try {
      await action();
      if (context.mounted) _showSnack(context, successMessage);
    } catch (error) {
      if (context.mounted) {
        _showSnack(context, AppStrings.settingsFunOperationFailed(error));
      }
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
        color: TurnaTheme.error.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(TurnaTheme.radiusLarge),
        border: Border.all(
          color: TurnaTheme.error.withValues(alpha: 0.2),
        ),
      ),
      child: Row(
        children: [
          const Icon(
            Icons.warning_amber_rounded,
            color: TurnaTheme.error,
            size: 22,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              AppStrings.settingsFunWarning,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: TurnaTheme.textSecondaryColor(context),
                    height: 1.4,
                  ),
            ),
          ),
        ],
      ),
    );
  }
}
