// Flutter imports:
import 'dart:async' show unawaited;

import 'package:flutter/material.dart';

// Package imports:
import 'package:provider/provider.dart';
import 'package:streaming_shared_preferences/streaming_shared_preferences.dart';

// Project imports:
import 'package:turna/application/cosmetic_provider.dart';
import 'package:turna/application/profile_prefs_facade.dart';
import 'package:turna/application/settings_provider.dart';
import 'package:turna/core/spacing.dart';
import 'package:turna/core/text_styles.dart';
import 'package:turna/core/theme.dart';
import 'package:turna/core/turna_icon_id.dart';
import 'package:turna/domain/auth/local_user.dart';
import 'package:turna/domain/cosmetics/avatar.dart';
import 'package:turna/domain/cosmetics/avatar_ring.dart';
import 'package:turna/domain/cosmetics/cosmetic_item.dart';
import 'package:turna/l10n/app_strings.dart';
import 'package:turna/views/profile/components/avatar_picker_sheet.dart';
import 'package:turna/views/widgets/avatar_with_ring.dart';
import 'package:turna/views/widgets/optional_provider.dart';
import 'package:turna/views/widgets/turna_icon.dart';
import 'package:turna/views/widgets/turna_sheet.dart';

/// Hero-style profile header: avatar, name, one-line bio, edit + share.
///
/// Theme switching lives in Settings → Appearance and language entry on the
/// Learn tab; the hero stays identity-only (profile-slimming refactor).
class AccountWidget extends StatelessWidget {
  final VoidCallback? onShare;

  const AccountWidget({super.key, this.onShare});

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final cosmetics = context.watch<CosmeticProvider>();
    final equippedRing = cosmetics.equippedRing;
    final profileTheme = cosmetics.equippedItem(CosmeticSlot.profileTheme);
    final settings = readOptionalProvider<SettingsProvider>(context);
    final pref = ProfilePrefsFacade.authUserPreference(settings: settings);

    if (pref == null) {
      return _buildHero(
        context,
        LocalUser.local,
        isDark: isDark,
        equippedRing: equippedRing,
        profileTheme: profileTheme,
        settings: settings,
      );
    }

    return PreferenceBuilder<LocalUser>(
      preference: pref,
      builder: (BuildContext context, LocalUser user) => _buildHero(
        context,
        user,
        isDark: isDark,
        equippedRing: equippedRing,
        profileTheme: profileTheme,
        settings: settings,
      ),
    );
  }

  Widget _buildHero(
    BuildContext context,
    LocalUser user, {
    required bool isDark,
    required AvatarRing equippedRing,
    required CosmeticItem? profileTheme,
    required SettingsProvider? settings,
  }) {
    final displayName = user.displayName ?? AppStrings.profileLearnerFallback;
    final bio = user.bio?.trim() ?? '';
    final avatar = AvatarCatalog.resolve(user.avatarId);

    // 滚动头卡使用静态淡彩玻璃，不做实时背景采样，避免合成层在滚动时闪烁。
    final fill = LinearGradient(
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
      colors: profileTheme != null
          ? [
              profileTheme.accentColor!.withValues(alpha: isDark ? 0.42 : 0.18),
              (profileTheme.secondaryColor ?? profileTheme.accentColor!)
                  .withValues(alpha: isDark ? 0.3 : 0.22),
            ]
          : isDark
          ? [
              TurnaTheme.brandTeal.withValues(alpha: 0.35),
              TurnaTheme.brandNavy.withValues(alpha: 0.45),
            ]
          : [
              TurnaTheme.brandTeal.withValues(alpha: 0.12),
              TurnaTheme.brandSky.withValues(alpha: 0.18),
            ],
    );
    // Clip + column so the clay→sand brand strip sits under 4px corners.
    final body = Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // Always-on secondary brand strip (wetland clay visibility polish).
        Container(
          height: 3,
          width: double.infinity,
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [
                TurnaTheme.anatolianClay,
                TurnaTheme.warmSand.withValues(alpha: 0.85),
              ],
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(18, 15, 14, 18),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Semantics(
                button: true,
                label: AppStrings.accountAvatarChangeTooltip,
                child: GestureDetector(
                  onTap: () => showAvatarPickerSheet(context, user: user),
                  child: AvatarWithRing(
                    radius: 32,
                    ring: equippedRing,
                    gapColor: TurnaTheme.cardBg(context),
                    backgroundColor: avatar.background.withValues(alpha: 0.15),
                    child: Text(
                      avatar.emoji,
                      style: AppTextStyles.pageTitle(context),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      displayName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.titleLarge
                          ?.copyWith(fontWeight: FontWeight.w800),
                    ),
                    if (bio.isNotEmpty) ...[
                      const SizedBox(height: AppSpacing.xs),
                      Text(
                        bio,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: TurnaTheme.textSecondaryColor(context),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              Column(
                children: [
                  _HeroIconButton(
                    icon: TurnaIconId.edit,
                    tooltip: AppStrings.accountEditName,
                    onTap: () => _showEditNameDialog(context, user, settings),
                  ),
                  if (onShare != null) ...[
                    const SizedBox(height: AppSpacing.sm),
                    _HeroIconButton(
                      icon: TurnaIconId.share,
                      tooltip: AppStrings.profileShare,
                      onTap: onShare!,
                    ),
                  ],
                ],
              ),
            ],
          ),
        ),
      ],
    );

    final fillDecoration = BoxDecoration(
      borderRadius: TurnaTheme.borderRadius,
      gradient: fill,
      border: Border.all(color: TurnaTheme.brandTeal.withValues(alpha: 0.18)),
    );
    // 阴影沿用 `l2Frost` 档位的近/远两层参数；静态化只移除实时模糊，
    // 不改变卡片的色相、描边与投影层级。
    final shadows = TurnaTheme.glassEnabled(context)
        ? TurnaTheme.glassShadow(
            context,
            profileTheme?.accentColor ?? TurnaTheme.brandTeal,
            level: GlassLevel.l2Frost,
          )
        : const <BoxShadow>[];

    return RepaintBoundary(
      child: Container(
        key: const Key('profile-cosmetic-theme'),
        decoration: fillDecoration.copyWith(boxShadow: shadows),
        clipBehavior: Clip.antiAlias,
        child: body,
      ),
    );
  }

  Future<void> _showEditNameDialog(
    BuildContext context,
    LocalUser user,
    SettingsProvider? settings,
  ) async {
    // Bottom-sheet editor via showTurnaSheet: controller is owned by
    // _EditNameSheet's State so it disposes cleanly after the exit animation.
    await showTurnaSheet<void>(
      context: context,
      title: AppStrings.accountEditNameTitle,
      body: _EditNameSheet(
        initialName: user.displayName ?? '',
        onSave: (name) {
          if (name.isEmpty) return;
          unawaited(
            ProfilePrefsFacade.saveUser(
              user.copyWith(displayName: name),
              settings: settings,
            ),
          );
        },
      ),
    );
  }
}

class _HeroIconButton extends StatelessWidget {
  final TurnaIconId icon;
  final String tooltip;
  final VoidCallback onTap;

  const _HeroIconButton({
    required this.icon,
    required this.tooltip,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: Material(
        color: TurnaTheme.cardBg(context).withValues(alpha: 0.7),
        borderRadius: TurnaTheme.borderRadius,
        child: InkWell(
          onTap: onTap,
          borderRadius: TurnaTheme.borderRadius,
          child: Padding(
            padding: const EdgeInsets.all(AppSpacing.sm),
            child: TurnaIcon(icon, size: 20, color: TurnaTheme.brandTeal),
          ),
        ),
      ),
    );
  }
}

/// Bottom-sheet editor for the profile display name. Owns its
/// [TextEditingController] so the controller is disposed with the sheet (after
/// the exit animation) rather than from the caller's `finally`.
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
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.pageMargin,
        AppSpacing.sm,
        AppSpacing.pageMargin,
        AppSpacing.lg,
      ),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TextField(
              controller: _controller,
              autofocus: true,
              textInputAction: TextInputAction.done,
              decoration: InputDecoration(
                hintText: AppStrings.accountEditNameHint,
                border: const OutlineInputBorder(
                  borderRadius: TurnaTheme.borderRadius,
                ),
                isDense: true,
              ),
              onSubmitted: (_) => _submit(),
            ),
            const SizedBox(height: AppSpacing.md),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: Text(AppStrings.commonCancel),
                ),
                const SizedBox(width: AppSpacing.sm),
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
