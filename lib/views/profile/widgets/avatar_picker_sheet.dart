// Flutter imports:
import 'package:flutter/material.dart';

// Project imports:
import 'package:turna/di/injection.dart';
import 'package:turna/domain/auth/local_user.dart';
import 'package:turna/domain/cosmetics/avatar.dart';
import 'package:turna/l10n/app_strings.dart';
import 'package:turna/service/locator.dart';
import 'package:turna/core/theme.dart';
import 'package:turna/views/widgets/turna_sheet.dart';
import 'package:turna/views/widgets/avatar_with_ring.dart';
import 'package:turna/views/widgets/turna_snack_bar.dart';

/// Sentinel popped by [_AvatarPickerSheet] when the user taps the
/// "reset to default" action. Differs from `null`, which means "sheet was
/// dismissed without a choice" and should NOT touch prefs.
const String _kResetSentinel = '__avatar_reset__';

/// Opens the global bottom sheet letting the user pick a preset avatar from
/// [AvatarCatalog] and persists the choice onto [LocalUser.avatarId].
///
/// 湿地雾光 R15：容器迁至 [showTurnaSheet]（拖手 + 标题 + 一句说明），
/// 「重置默认」是弹层操作区的主操作。
///
/// Safe to call from any context that has access to the navigator + app
/// prefs. Returns the newly selected [Avatar] id, `null` if the user picked
/// the default avatar (or already had it), or dismissed the sheet without
/// changing anything.
///
/// Both the Profile page and the Settings page use this same entry point so
/// the UI stays consistent. The current selection is read from
/// [LocalUser.avatarId] (null = default).
Future<String?> showAvatarPickerSheet(
  BuildContext context, {
  required LocalUser user,
}) async {
  final selected = await showTurnaSheet<String>(
    context: context,
    title: AppStrings.accountAvatarChangeTitle,
    subtitle: AppStrings.accountAvatarChangeHint,
    isScrollControlled: true,
    body: _AvatarPickerSheet(currentId: user.avatarId),
    actions: [
      TurnaSheetAction(
        label: AppStrings.accountAvatarReset,
        primary: true,
        onPressed: () => Navigator.of(context).pop(_kResetSentinel),
      ),
    ],
  );
  if (selected == null) return null;

  if (!context.mounted) return null;
  final messenger = ScaffoldMessenger.of(context);

  if (selected == _kResetSentinel) {
    // Reset to default: explicitly null out the field so the user can tell
    // "I have no pick" apart from "I picked the default tile".
    final updated = user.copyWith(clearAvatarId: true);
    if (getIt.isRegistered<AppPrefs>()) {
      await getIt<AppPrefs>().setLocalUser(updated);
    }
    if (!context.mounted) return null;
    TurnaSnackBar.showVia(
      messenger,
      context,
      AppStrings.accountAvatarResetDone,
    );
    return null;
  }

  // Normal pick. Equality is by id; passing the same id again is a no-op for
  // observers but still goes through the prefs pipeline.
  final updated = user.copyWith(avatarId: selected);
  if (getIt.isRegistered<AppPrefs>()) {
    await getIt<AppPrefs>().setLocalUser(updated);
  }
  if (!context.mounted) return null;
  final name = AvatarCatalog.resolve(selected).name;
  TurnaSnackBar.showVia(
    messenger,
    context,
    AppStrings.accountAvatarChangedDone(name),
  );
  return selected;
}

class _AvatarPickerSheet extends StatelessWidget {
  const _AvatarPickerSheet({required this.currentId});

  /// Currently equipped avatar id (may be null = default).
  final String? currentId;

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return ConstrainedBox(
      // Cap the sheet height so the grid scrolls when the catalog grows
      // past ~20 entries.
      constraints: BoxConstraints(
        maxHeight: MediaQuery.of(context).size.height * 0.6,
      ),
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 20),
        child: _AvatarGrid(
          currentId: currentId,
          isDark: isDark,
          onPick: (id) => Navigator.of(context).pop(id),
        ),
      ),
    );
  }
}

class _AvatarGrid extends StatelessWidget {
  const _AvatarGrid({
    required this.currentId,
    required this.isDark,
    required this.onPick,
  });

  final String? currentId;
  final bool isDark;
  final ValueChanged<String> onPick;

  static const int _columns = 4;

  @override
  Widget build(BuildContext context) {
    const avatars = AvatarCatalog.all;
    return GridView.builder(
      padding: EdgeInsets.zero,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: _columns,
        mainAxisSpacing: 10,
        crossAxisSpacing: 10,
        // 0.72 (not 0.78) leaves ~6-8px of slack inside each tile so the
        // selected border (width: 2) + bodySmall line-height variance don't
        // trip a sub-pixel overflow on narrow screens. 0.78 was empirically
        // ~0.5px short on 360dp Android.
        childAspectRatio: 0.72,
      ),
      itemCount: avatars.length,
      itemBuilder: (context, i) {
        final a = avatars[i];
        final selected = a.id == currentId;
        return _AvatarTile(
          avatar: a,
          selected: selected,
          isDark: isDark,
          onTap: () => onPick(a.id),
        );
      },
    );
  }
}

class _AvatarTile extends StatelessWidget {
  const _AvatarTile({
    required this.avatar,
    required this.selected,
    required this.isDark,
    required this.onTap,
  });

  final Avatar avatar;
  final bool selected;
  final bool isDark;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      selected: selected,
      label: avatar.name,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(TurnaTheme.radiusLarge),
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(TurnaTheme.radiusLarge),
            color: selected
                ? TurnaTheme.brandTeal.withValues(alpha: isDark ? 0.18 : 0.10)
                : Colors.transparent,
            border: Border.all(
              color: selected
                  ? TurnaTheme.brandTeal
                  : TurnaTheme.dividerBg(context),
              width: selected ? 2 : 1,
            ),
          ),
          padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 6),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Stack(
                alignment: Alignment.center,
                children: [
                  AvatarWithRing(
                    radius: 22,
                    gapColor: TurnaTheme.cardBg(context),
                    backgroundColor: avatar.background.withValues(alpha: 0.18),
                    child: Text(
                      avatar.emoji,
                      style: const TextStyle(fontSize: 22),
                    ),
                  ),
                  if (selected)
                    Positioned(
                      right: 0,
                      bottom: 0,
                      child: Container(
                        decoration: BoxDecoration(
                          color: TurnaTheme.brandTeal,
                          shape: BoxShape.circle,
                          border: Border.all(
                            color: TurnaTheme.cardBg(context),
                            width: 2,
                          ),
                        ),
                        padding: const EdgeInsets.all(2),
                        child: const Icon(
                          Icons.check_rounded,
                          size: 12,
                          color: Colors.white,
                        ),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 6),
              Text(
                AppStrings.accountAvatarName(avatar.name),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                      fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                      color: selected
                          ? TurnaTheme.brandTeal
                          : TurnaTheme.textSecondaryColor(context),
                    ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
