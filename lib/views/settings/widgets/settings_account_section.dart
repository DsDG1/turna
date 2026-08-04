// Flutter imports:
import 'package:flutter/material.dart';

// Package imports:
import 'package:provider/provider.dart';
import 'package:streaming_shared_preferences/streaming_shared_preferences.dart';

// Project imports:
import 'package:turna/application/cosmetic_provider.dart';
import 'package:turna/application/game_provider.dart';
import 'package:turna/application/grammar_review_provider.dart';
import 'package:turna/application/mistake_provider.dart';
import 'package:turna/application/srs_provider.dart';
import 'package:turna/di/injection.dart';
import 'package:turna/domain/auth/local_user.dart';
import 'package:turna/service/locator.dart';
import 'package:turna/views/settings/avatar_rings_page.dart';
import 'package:turna/views/settings/widgets/settings_common.dart';
import 'package:turna/l10n/app_strings.dart';
import 'package:turna/views/theme.dart';
import 'package:turna/views/widgets/avatar_with_ring.dart';

/// Available avatar background colors indexed by [LocalUser.avatarColorIndex].
const _avatarColors = <Color>[
  TurnaTheme.brandTeal,
  TurnaTheme.brandSky,
  TurnaTheme.brandReed,
  TurnaTheme.brandReed,
  TurnaTheme.error,
  TurnaTheme.warning,
  TurnaTheme.leagueEmerald,
  TurnaTheme.leagueAmethyst,
];

/// Preset daily XP goal values for the slider.
const _xpGoalSteps = [50, 100, 150, 200, 250, 300, 400, 500];

/// Preset study minute goal values.
const _studyMinuteSteps = [15, 30, 45, 60, 90];

/// Preset daily lesson goal values.
const _lessonGoalSteps = [1, 2, 3, 5, 8, 10, 15, 20];

/// Root widget for the Account settings category.
///
/// Shows a profile card, learning goals, stats summary, and data management.
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
        const _ProfileCard(),
        const SizedBox(height: 12),
        const _CosmeticsEntry(),
        const SizedBox(height: 20),
        const _LearningGoalsSection(),
        const SizedBox(height: 20),
        const _StatsSection(),
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
            Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) => const AvatarRingsPage(),
              ),
            );
          },
        ),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Profile Card
// ─────────────────────────────────────────────────────────────────────────────

class _ProfileCard extends StatelessWidget {
  const _ProfileCard();

  @override
  Widget build(BuildContext context) {
    return PreferenceBuilder<LocalUser>(
      preference: getIt<AppPrefs>().authUser,
      builder: (context, user) {
        final displayName =
            user.displayName ?? AppStrings.settingsAccountLearnerFallback;
        final email = user.email ?? '';
        final bio = user.bio;
        final avatarColorIndex = user.avatarColorIndex ?? 0;
        final avatarColor =
            _avatarColors[avatarColorIndex.clamp(0, _avatarColors.length - 1)];
        final initials = _initials(displayName);
        final equippedRing = context.watch<CosmeticProvider>().equippedRing;

        return SettingsCard(
          children: [
            Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                children: [
                  // Avatar + Name + Edit button
                  Row(
                    children: [
                      // Avatar — tap to change color
                      GestureDetector(
                        onTap: () => _showAvatarColorPicker(context, user),
                        child: AvatarWithRing(
                          radius: 32,
                          ring: equippedRing,
                          gapColor: TurnaTheme.cardBg(context),
                          backgroundColor: avatarColor.withValues(alpha: 0.15),
                          child: Text(
                            initials,
                            style: TextStyle(
                              fontSize: 22,
                              fontWeight: FontWeight.w700,
                              color: avatarColor,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 14),
                      // Name + Bio
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              displayName,
                              style: Theme.of(context)
                                  .textTheme
                                  .titleMedium
                                  ?.copyWith(fontWeight: FontWeight.w700),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              bio?.isNotEmpty == true
                                  ? bio!
                                  : AppStrings.accountBioHint,
                              style: Theme.of(context)
                                  .textTheme
                                  .bodySmall
                                  ?.copyWith(
                                    color: bio?.isNotEmpty == true
                                        ? TurnaTheme.textSecondaryColor(context)
                                        : TurnaTheme.textHintColor(context),
                                    fontStyle: bio?.isNotEmpty == true
                                        ? FontStyle.italic
                                        : FontStyle.normal,
                                  ),
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                            ),
                            if (email.isNotEmpty) ...[
                              const SizedBox(height: 4),
                              Text(
                                email,
                                style: Theme.of(context)
                                    .textTheme
                                    .bodySmall
                                    ?.copyWith(
                                      color: TurnaTheme.textHintColor(context),
                                    ),
                              ),
                            ],
                          ],
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.edit_rounded, size: 20),
                        tooltip: AppStrings.accountEditName,
                        color: TurnaTheme.brandTeal,
                        onPressed: () => _showEditNameDialog(context, user),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        );
      },
    );
  }

  String _initials(String name) {
    final parts = name.trim().split(RegExp(r'\s+'));
    if (parts.length >= 2) {
      return '${parts.first[0]}${parts.last[0]}'.toUpperCase();
    }
    return name.isNotEmpty ? name[0].toUpperCase() : '?';
  }

  Future<void> _showEditNameDialog(BuildContext context, LocalUser user) async {
    // Use a modal bottom sheet instead of AlertDialog. AlertDialog wraps its
    // content in an AnimatedPadding driven by MediaQuery.viewInsets (keyboard
    // height) with a 100ms duration, so dismissing it while the keyboard is
    // open leaves that animation mid-flight during route teardown. On Flutter
    // 3.35's rewritten Overlay that trips `_overlayChildRenderBox == null`
    // ("already occupied") and `InheritedElement._dependents.isEmpty`. The
    // bottom-sheet route has no viewInsets-driven animation (the keyboard is
    // absorbed by a static Padding in _EditNameSheet), so it dismisses
    // cleanly. The TextEditingController is owned
    // by _EditNameSheet's State and disposed with the sheet (after the exit
    // animation), not from a finally here, which would run while the sheet is
    // still mounted and rebuild the TextField against a disposed controller.
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: TurnaTheme.cardBg(context),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => _EditNameSheet(
        initialName: user.displayName ?? '',
        onSave: (name) {
          if (name.isEmpty) return;
          getIt<AppPrefs>().setLocalUser(user.copyWith(displayName: name));
        },
      ),
    );
  }

  Future<void> _showAvatarColorPicker(
      BuildContext context, LocalUser user) async {
    final selectedIndex = await showDialog<int>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(TurnaTheme.radiusLarge),
        ),
        title: Text(AppStrings.accountAvatarTitle),
        content: SizedBox(
          width: 280,
          child: Wrap(
            spacing: 12,
            runSpacing: 12,
            alignment: WrapAlignment.center,
            children: List.generate(_avatarColors.length, (i) {
              final color = _avatarColors[i];
              final isSelected = i == (user.avatarColorIndex ?? 0);
              return GestureDetector(
                onTap: () => Navigator.of(ctx).pop(i),
                child: Container(
                  width: 48,
                  height: 48,
                  decoration: BoxDecoration(
                    color: color.withValues(alpha: 0.15),
                    shape: BoxShape.circle,
                    border:
                        isSelected ? Border.all(color: color, width: 3) : null,
                  ),
                  child: Center(
                    child: Icon(
                      isSelected
                          ? Icons.check_circle_rounded
                          : Icons.person_rounded,
                      color: color,
                      size: 24,
                    ),
                  ),
                ),
              );
            }),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: Text(AppStrings.commonCancel),
          ),
        ],
      ),
    );
    if (selectedIndex == null || !context.mounted) return;
    final updated = user.copyWith(avatarColorIndex: selectedIndex);
    await getIt<AppPrefs>().setLocalUser(updated);
  }
}

/// Bottom-sheet editor for the profile display name. Owns its
/// [TextEditingController] so the controller is disposed with the sheet (after
/// the exit animation) rather than from the caller's `finally`, which would
/// run while the sheet is still mounted and rebuild the field against a
/// disposed controller. See [_ProfileCard._showEditNameDialog].
class _EditNameSheet extends StatefulWidget {
  const _EditNameSheet({required this.initialName, required this.onSave});

  final String initialName;

  /// Called with the trimmed value when the user saves (empty values are
  /// ignored by the caller). Invoked after the sheet is popped.
  final ValueChanged<String> onSave;

  @override
  State<_EditNameSheet> createState() => _EditNameSheetState();
}

class _EditNameSheetState extends State<_EditNameSheet> {
  late final TextEditingController _controller;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.initialName);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _submit() {
    final value = _controller.text.trim();
    Navigator.of(context).pop();
    widget.onSave(value);
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
        left: 16,
        right: 16,
        top: 16,
        bottom: MediaQuery.of(context).viewInsets.bottom + 16,
      ),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              AppStrings.accountEditNameTitle,
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                  ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: _controller,
              autofocus: true,
              textInputAction: TextInputAction.done,
              decoration: InputDecoration(
                hintText: AppStrings.accountEditNameHint,
                border: const OutlineInputBorder(),
                isDense: true,
              ),
              onSubmitted: (_) => _submit(),
            ),
            const SizedBox(height: 12),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: Text(AppStrings.commonCancel),
                ),
                const SizedBox(width: 8),
                FilledButton(
                  onPressed: _submit,
                  child: Text(AppStrings.accountEditNameSave),
                ),
              ],
            ),
          ],
        ),
      ),
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
// Stats Summary Section
// ─────────────────────────────────────────────────────────────────────────────

class _StatsSection extends StatelessWidget {
  const _StatsSection();

  @override
  Widget build(BuildContext context) {
    // Synchronous snapshot via select: rebuild only when the 5 displayed
    // counters change. Avoids FutureBuilder re-firing on every GameProvider
    // notify (and getUserGameStateOnce is already a sync prefs read).
    final stats = context.select<GameProvider, _AccountStatsSnapshot>(
      (g) {
        final s = g.currentUserGameState;
        return _AccountStatsSnapshot(
          streak: s.streak,
          score: s.score,
          gems: s.gems,
          lessonsCompleted: s.lessonsCompleted,
          perfectLessons: s.perfectLessons,
        );
      },
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SettingsSectionTitle(
          icon: Icons.bar_chart_rounded,
          title: AppStrings.accountStatsTitle,
        ),
        const SizedBox(height: 8),
        SettingsCard(
          children: [
            _StatRow(
              icon: Icons.local_fire_department_rounded,
              iconColor: TurnaTheme.warning,
              label: AppStrings.accountStreak,
              value: AppStrings.accountStreakValue(stats.streak),
            ),
            settingsTileDivider(context),
            _StatRow(
              icon: Icons.star_rounded,
              iconColor: TurnaTheme.brandTeal,
              label: AppStrings.profileTotalXp,
              value: _formatNumber(stats.score),
            ),
            settingsTileDivider(context),
            _StatRow(
              icon: Icons.diamond_rounded,
              iconColor: TurnaTheme.brandReed,
              label: AppStrings.profileGems,
              value: _formatNumber(stats.gems),
            ),
            settingsTileDivider(context),
            _StatRow(
              icon: Icons.check_circle_rounded,
              iconColor: TurnaTheme.leagueEmerald,
              label: AppStrings.accountLessonsCompleted,
              value: AppStrings.accountLessonsCompletedValue(
                  stats.lessonsCompleted),
            ),
            settingsTileDivider(context),
            _StatRow(
              icon: Icons.emoji_events_rounded,
              iconColor: TurnaTheme.leagueAmethyst,
              label: AppStrings.accountPerfectLessons,
              value:
                  AppStrings.accountPerfectLessonsValue(stats.perfectLessons),
            ),
          ],
        ),
      ],
    );
  }

  String _formatNumber(int n) {
    if (n >= 1000) {
      return '${(n / 1000).toStringAsFixed(1)}k';
    }
    return n.toString();
  }
}

class _AccountStatsSnapshot {
  const _AccountStatsSnapshot({
    required this.streak,
    required this.score,
    required this.gems,
    required this.lessonsCompleted,
    required this.perfectLessons,
  });

  final int streak;
  final int score;
  final int gems;
  final int lessonsCompleted;
  final int perfectLessons;

  @override
  bool operator ==(Object other) =>
      other is _AccountStatsSnapshot &&
      other.streak == streak &&
      other.score == score &&
      other.gems == gems &&
      other.lessonsCompleted == lessonsCompleted &&
      other.perfectLessons == perfectLessons;

  @override
  int get hashCode =>
      Object.hash(streak, score, gems, lessonsCompleted, perfectLessons);
}

class _StatRow extends StatelessWidget {
  final IconData icon;
  final Color iconColor;
  final String label;
  final String value;

  const _StatRow({
    required this.icon,
    required this.iconColor,
    required this.label,
    required this.value,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: iconColor.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(TurnaTheme.radiusMedium),
            ),
            child: Icon(icon, color: iconColor, size: 20),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              label,
              style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
            ),
          ),
          Text(
            value,
            style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                  fontWeight: FontWeight.w700,
                  color: TurnaTheme.brandTeal,
                ),
          ),
        ],
      ),
    );
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

    // Ordered reset: clear secondary stores first, then one atomic game-state
    // pass (avoids parallel prefs races with an intermediate notify).
    final gameProvider = context.read<GameProvider>();
    final mistakeProvider = context.read<MistakeProvider>();
    final srsProvider = getIt<SrsProvider>();
    final grammarProvider = getIt<GrammarReviewProvider>();
    final cosmetics = context.read<CosmeticProvider>();
    final appPrefs = getIt<AppPrefs>();

    await mistakeProvider.clear();
    await srsProvider.clear();
    await grammarProvider.clear();
    await gameProvider.resetAccountGameState();
    await cosmetics.resetCosmetics();
    await appPrefs.setLocalUser(LocalUser.local);

    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(AppStrings.accountResetDone)),
      );
    }
  }
}
