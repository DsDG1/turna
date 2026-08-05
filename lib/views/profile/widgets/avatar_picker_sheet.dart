// Flutter imports:
import 'package:flutter/material.dart';

// Project imports:
import 'package:turna/di/injection.dart';
import 'package:turna/domain/auth/local_user.dart';
import 'package:turna/domain/cosmetics/avatar.dart';
import 'package:turna/l10n/app_strings.dart';
import 'package:turna/service/locator.dart';
import 'package:turna/views/theme.dart';
import 'package:turna/views/widgets/avatar_with_ring.dart';

/// Sentinel popped by [_AvatarPickerSheet] when the user taps the
/// "reset to default" action. Differs from `null`, which means "sheet was
/// dismissed without a choice" and should NOT touch prefs.
const String _kResetSentinel = '__avatar_reset__';

/// Opens a modal bottom sheet letting the user pick a preset avatar from
/// [AvatarCatalog] and persists the choice onto [LocalUser.avatarId].
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
  final selected = await showModalBottomSheet<String>(
    context: context,
    isScrollControlled: true,
    backgroundColor: TurnaTheme.cardBg(context),
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    builder: (_) => _AvatarPickerSheet(currentId: user.avatarId),
  );
  if (selected == null) return null;

  if (!context.mounted) return null;
  final messenger = ScaffoldMessenger.of(context);

  if (selected == _kResetSentinel) {
    // Reset to default: explicitly null out the field so the user can tell
    // "I have no pick" apart from "I picked the default tile".
    final updated = user.copyWith(clearAvatarId: true);
    await getIt<AppPrefs>().setLocalUser(updated);
    messenger.showSnackBar(
      SnackBar(content: Text(AppStrings.accountAvatarResetDone)),
    );
    return null;
  }

  // Normal pick. Equality is by id; passing the same id again is a no-op for
  // observers but still goes through the prefs pipeline.
  final updated = user.copyWith(avatarId: selected);
  await getIt<AppPrefs>().setLocalUser(updated);
  final name = AvatarCatalog.resolve(selected).name;
  messenger.showSnackBar(
    SnackBar(content: Text(AppStrings.accountAvatarChangedDone(name))),
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
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;

    return SafeArea(
      top: false,
      child: Padding(
        padding: EdgeInsets.only(bottom: bottomInset),
        child: ConstrainedBox(
          // Cap the sheet height so the grid scrolls when the catalog grows
          // past ~20 entries. The 0.72 headroom leaves room for subpixel
          // rounding (Header + padding + 4-col grid totals) so the last row
          // doesn't trip a 0.xpx overflow.
          constraints: BoxConstraints(
            maxHeight: MediaQuery.of(context).size.height * 0.72,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _Header(
                title: AppStrings.accountAvatarChangeTitle,
                hint: AppStrings.accountAvatarChangeHint,
                onReset: () => Navigator.of(context).pop(_kResetSentinel),
                onClose: () => Navigator.of(context).pop(),
              ),
              const SizedBox(height: 4),
              Flexible(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 20),
                  child: _AvatarGrid(
                    currentId: currentId,
                    isDark: isDark,
                    onPick: (id) => Navigator.of(context).pop(id),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({
    required this.title,
    required this.hint,
    required this.onReset,
    required this.onClose,
  });

  final String title;
  final String hint;
  final VoidCallback onReset;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 14, 4, 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w800,
                      ),
                ),
                const SizedBox(height: 2),
                Text(
                  hint,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: TurnaTheme.textHintColor(context),
                      ),
                ),
              ],
            ),
          ),
          IconButton(
            icon: const Icon(Icons.restart_alt_rounded),
            tooltip: AppStrings.accountAvatarResetTooltip,
            color: TurnaTheme.textHintColor(context),
            onPressed: onReset,
          ),
          IconButton(
            icon: const Icon(Icons.close_rounded),
            tooltip: AppStrings.commonClose,
            color: TurnaTheme.textHintColor(context),
            onPressed: onClose,
          ),
        ],
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
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: _columns,
        mainAxisSpacing: 10,
        crossAxisSpacing: 10,
        childAspectRatio: 0.78,
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
                    backgroundColor:
                        avatar.background.withValues(alpha: 0.18),
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
                      fontWeight:
                          selected ? FontWeight.w700 : FontWeight.w500,
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
