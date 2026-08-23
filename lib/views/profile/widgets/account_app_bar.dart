// Flutter imports:
import 'package:flutter/material.dart';

// Package imports:
import 'package:provider/provider.dart';
import 'package:streaming_shared_preferences/streaming_shared_preferences.dart';

// Project imports:
import 'package:turna/application/cosmetic_provider.dart';
import 'package:turna/di/injection.dart';
import 'package:turna/domain/auth/local_user.dart';
import 'package:turna/domain/cosmetics/avatar.dart';
import 'package:turna/domain/cosmetics/cosmetic_item.dart';
import 'package:turna/l10n/app_strings.dart';
import 'package:turna/service/locator.dart';
import 'package:turna/views/profile/widgets/avatar_picker_sheet.dart';
import 'package:turna/views/theme.dart';
import 'package:turna/views/widgets/avatar_with_ring.dart';

/// Hero-style profile header: avatar, name, one-line bio, edit + share.
///
/// Theme switching lives in Settings → Appearance and language entry on the
/// Learn tab; the hero stays identity-only (profile-slimming refactor).
class AccountWidget extends StatelessWidget {
  final VoidCallback? onShare;

  const AccountWidget({Key? key, this.onShare}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final cosmetics = context.watch<CosmeticProvider>();
    final equippedRing = cosmetics.equippedRing;
    final profileTheme = cosmetics.equippedItem(CosmeticSlot.profileTheme);

    return PreferenceBuilder<LocalUser>(
      preference: getIt<AppPrefs>().authUser,
      builder: (BuildContext context, LocalUser user) {
        final displayName =
            user.displayName ?? AppStrings.profileLearnerFallback;
        final bio = user.bio?.trim() ?? '';
        final avatar = AvatarCatalog.resolve(user.avatarId);

        // Clip + column so the clay→sand brand strip sits under rounded corners.
        return Container(
          key: const Key('profile-cosmetic-theme'),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(TurnaTheme.radiusXLarge),
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: profileTheme != null
                  ? [
                      profileTheme.accentColor!.withValues(
                        alpha: isDark ? 0.42 : 0.18,
                      ),
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
            ),
            border: Border.all(
              color: TurnaTheme.brandTeal.withValues(alpha: 0.18),
            ),
            boxShadow: [
              BoxShadow(
                color: TurnaTheme.brandTeal.withValues(alpha: 0.08),
                blurRadius: 16,
                offset: const Offset(0, 6),
              ),
            ],
          ),
          clipBehavior: Clip.antiAlias,
          child: Column(
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
                          backgroundColor:
                              avatar.background.withValues(alpha: 0.15),
                          child: Text(
                            avatar.emoji,
                            style: const TextStyle(fontSize: 30),
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
                            style: Theme.of(context)
                                .textTheme
                                .titleLarge
                                ?.copyWith(
                                  fontWeight: FontWeight.w800,
                                ),
                          ),
                          if (bio.isNotEmpty) ...[
                            const SizedBox(height: 4),
                            Text(
                              bio,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: Theme.of(context)
                                  .textTheme
                                  .bodySmall
                                  ?.copyWith(
                                    color:
                                        TurnaTheme.textSecondaryColor(context),
                                  ),
                            ),
                          ],
                        ],
                      ),
                    ),
                    Column(
                      children: [
                        _HeroIconButton(
                          icon: Icons.edit_rounded,
                          tooltip: AppStrings.accountEditName,
                          onTap: () => _showEditNameDialog(context, user),
                        ),
                        if (onShare != null) ...[
                          const SizedBox(height: 8),
                          _HeroIconButton(
                            icon: Icons.share_rounded,
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
          ),
        );
      },
    );
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
}

class _HeroIconButton extends StatelessWidget {
  final IconData icon;
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
        borderRadius: BorderRadius.circular(TurnaTheme.radiusRound),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(TurnaTheme.radiusRound),
          child: Padding(
            padding: const EdgeInsets.all(8),
            child: Icon(icon, size: 20, color: TurnaTheme.brandTeal),
          ),
        ),
      ),
    );
  }
}

/// Bottom-sheet editor for the profile display name. Owns its
/// [TextEditingController] so the controller is disposed with the sheet (after
/// the exit animation) rather than from the caller's `finally`, which would
/// run while the sheet is still mounted and rebuild the field against a
/// disposed controller. See [AccountWidget._showEditNameDialog].
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
