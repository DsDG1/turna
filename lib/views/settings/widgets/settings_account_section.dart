// Dart imports:
import 'dart:async';

// Flutter imports:
import 'package:flutter/material.dart';

// Package imports:
import 'package:auto_route/auto_route.dart';
import 'package:provider/provider.dart';
import 'package:streaming_shared_preferences/streaming_shared_preferences.dart';

// Project imports:
import 'package:turna/application/cosmetic_provider.dart';
import 'package:turna/application/settings/commands/reset_account_command.dart';
import 'package:turna/application/settings/settings_operation_result.dart';
import 'package:turna/di/injection.dart';
import 'package:turna/domain/auth/local_user.dart';
import 'package:turna/routing/routing.gr.dart';
import 'package:turna/service/locator.dart';
import 'package:turna/views/settings/widgets/settings_common.dart';
import 'package:turna/l10n/app_strings.dart';
import 'package:turna/views/theme.dart';
import 'package:turna/views/widgets/avatar_with_ring.dart';

/// Preset daily XP goal values for the slider.
const _xpGoalSteps = [50, 100, 150, 200, 250, 300, 400, 500];

/// Preset study minute goal values.
const _studyMinuteSteps = [15, 30, 45, 60, 90];

/// Preset daily lesson goal values.
const _lessonGoalSteps = [1, 2, 3, 5, 8, 10, 15, 20];

/// Root widget for the Account settings category.
///
/// Shows cosmetics, learning goals, and data management. Identity editing
/// (avatar/name/bio) lives on the profile page hero; counter stats live in
/// the Learn app bar and the review-progress page.
class SettingsAccountSection extends StatelessWidget {
  const SettingsAccountSection({
    super.key,
    this.onNavigateToData,
  });

  /// Jump to the Data category (parent [SettingsPage] owns category state).
  final VoidCallback? onNavigateToData;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const _CosmeticsEntry(),
        const SizedBox(height: 20),
        const _LearningGoalsSection(),
        const SizedBox(height: 20),
        _DataManagementSection(onNavigateToData: onNavigateToData),
        const SizedBox(height: 24),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Cosmetics entry
// ─────────────────────────────────────────────────────────────────────────────

class _CosmeticsEntry extends StatelessWidget {
  const _CosmeticsEntry();

  @override
  Widget build(BuildContext context) {
    final ring = context.watch<CosmeticProvider>().equippedRing;
    return SettingsCard(
      children: [
        SettingsTile(
          icon: Icons.account_circle_outlined,
          title: AppStrings.cosmeticsTitle,
          subtitle: AppStrings.cosmeticsRingTitle(ring.id),
          trailing: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              AvatarWithRing(
                radius: 14,
                ring: ring,
                gapColor: TurnaTheme.cardBg(context),
                backgroundColor: TurnaTheme.brandTeal.withValues(alpha: 0.12),
                child: const Icon(
                  Icons.person_rounded,
                  size: 14,
                  color: TurnaTheme.brandTeal,
                ),
              ),
              const SizedBox(width: 4),
              Icon(
                Icons.chevron_right_rounded,
                color: TurnaTheme.textHintColor(context),
              ),
            ],
          ),
          onTap: () {
            context.router.push(const AvatarRingsRoute());
          },
        ),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Learning Goals Section
// ─────────────────────────────────────────────────────────────────────────────

class _LearningGoalsSection extends StatelessWidget {
  const _LearningGoalsSection();

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SettingsSectionTitle(
          icon: Icons.flag_rounded,
          title: AppStrings.accountGoalsTitle,
        ),
        const SizedBox(height: 8),
        PreferenceBuilder<LocalUser>(
          preference: getIt<AppPrefs>().authUser,
          builder: (context, user) {
            return SettingsCard(
              children: [
                _GoalSliderTile(
                  icon: Icons.emoji_events_rounded,
                  title: AppStrings.accountDailyXpGoal,
                  value: user.dailyXpGoal ?? 100,
                  steps: _xpGoalSteps,
                  formatValue: (v) => '$v',
                  onChanged: (v) => _updateUser(user.copyWith(dailyXpGoal: v)),
                ),
                settingsTileDivider(context),
                _GoalSliderTile(
                  icon: Icons.timer_rounded,
                  title: AppStrings.accountDailyStudyGoal,
                  value: user.dailyStudyMinutesGoal ?? 30,
                  steps: _studyMinuteSteps,
                  formatValue: (v) => AppStrings.accountDailyStudyGoalValue(v),
                  onChanged: (v) =>
                      _updateUser(user.copyWith(dailyStudyMinutesGoal: v)),
                ),
                settingsTileDivider(context),
                _GoalSliderTile(
                  icon: Icons.menu_book_rounded,
                  title: AppStrings.accountDailyLessonGoal,
                  value: user.dailyLessonGoal ?? 5,
                  steps: _lessonGoalSteps,
                  formatValue: (v) =>
                      AppStrings.accountLessonsCompletedValue(v),
                  onChanged: (v) =>
                      _updateUser(user.copyWith(dailyLessonGoal: v)),
                ),
              ],
            );
          },
        ),
      ],
    );
  }

  Future<void> _updateUser(LocalUser updated) async {
    await getIt<AppPrefs>().setLocalUser(updated);
  }
}

class _GoalSliderTile extends StatefulWidget {
  final IconData icon;
  final String title;
  final int value;
  final List<int> steps;
  final String Function(int) formatValue;
  final ValueChanged<int> onChanged;

  const _GoalSliderTile({
    required this.icon,
    required this.title,
    required this.value,
    required this.steps,
    required this.formatValue,
    required this.onChanged,
  });

  @override
  State<_GoalSliderTile> createState() => _GoalSliderTileState();
}

class _GoalSliderTileState extends State<_GoalSliderTile> {
  late int _value;

  @override
  void initState() {
    super.initState();
    _value = widget.value;
  }

  @override
  void didUpdateWidget(_GoalSliderTile oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.value != widget.value) {
      _value = widget.value;
    }
  }

  @override
  Widget build(BuildContext context) {
    final divisions = widget.steps.length - 1;
    // Find the nearest step index for the slider.
    final sliderValue = _nearestStepIndex(_value).toDouble();

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: TurnaTheme.brandTeal.withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(TurnaTheme.radiusMedium),
                ),
                child: Icon(
                  widget.icon,
                  color: TurnaTheme.brandTeal,
                  size: 20,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  widget.title,
                  style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                        fontWeight: FontWeight.w600,
                      ),
                ),
              ),
              Text(
                widget.formatValue(_value),
                style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                      color: TurnaTheme.brandTeal,
                      fontWeight: FontWeight.w700,
                    ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Padding(
            padding: const EdgeInsets.only(left: 52),
            child: Slider.adaptive(
              value: sliderValue,
              min: 0,
              max: divisions.toDouble(),
              divisions: divisions,
              activeColor: TurnaTheme.brandTeal,
              inactiveColor: TurnaTheme.dividerBg(context),
              onChanged: (index) {
                final stepIndex = index.round().clamp(0, divisions);
                final newValue = widget.steps[stepIndex];
                setState(() => _value = newValue);
              },
              onChangeEnd: (index) {
                final stepIndex = index.round().clamp(0, divisions);
                final newValue = widget.steps[stepIndex];
                widget.onChanged(newValue);
              },
            ),
          ),
        ],
      ),
    );
  }

  int _nearestStepIndex(int value) {
    var best = 0;
    var bestDiff = (value - widget.steps[0]).abs();
    for (int i = 1; i < widget.steps.length; i++) {
      final diff = (value - widget.steps[i]).abs();
      if (diff < bestDiff) {
        bestDiff = diff;
        best = i;
      }
    }
    return best;
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Data Management Section
// ─────────────────────────────────────────────────────────────────────────────

class _DataManagementSection extends StatelessWidget {
  const _DataManagementSection({this.onNavigateToData});

  final VoidCallback? onNavigateToData;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SettingsSectionTitle(
          icon: Icons.storage_rounded,
          title: AppStrings.accountDataManagement,
        ),
        const SizedBox(height: 8),
        SettingsCard(
          children: [
            SettingsActionTile(
              icon: Icons.folder_rounded,
              title: AppStrings.accountDataManagement,
              subtitle: AppStrings.accountDataManagementSubtitle,
              onTap: (_) => onNavigateToData?.call(),
            ),
            settingsTileDivider(context),
            SettingsActionTile(
              icon: Icons.delete_forever_rounded,
              title: AppStrings.accountResetTitle,
              subtitle: AppStrings.accountResetSubtitle,
              onTap: (context) => _confirmReset(context),
            ),
          ],
        ),
      ],
    );
  }

  Future<void> _confirmReset(BuildContext context) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => SettingsConfirmDialog(
        title: AppStrings.accountResetDialogTitle,
        message: AppStrings.accountResetDialogMessage,
        confirmText: AppStrings.accountResetConfirm,
      ),
    );
    if (confirmed != true || !context.mounted) return;

    // Modal, un-dismissable progress barrier: blocks back / repeated taps /
    // conflicting operations while the destructive sweep runs.
    unawaited(showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => PopScope(
        canPop: false,
        child: const Center(
          child: CircularProgressIndicator(),
        ),
      ),
    ));

    final command = getIt<ResetAccountCommand>();
    final result = await command.execute();
    if (!context.mounted) {
      return;
    }
    Navigator.of(context, rootNavigator: true).pop(); // progress barrier
    switch (result) {
      case SettingsOperationSuccess():
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(AppStrings.accountResetDone)),
        );
      case SettingsOperationFailure(:final userMessage):
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(userMessage)),
        );
    }
  }
}
