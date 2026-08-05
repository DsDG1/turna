// Flutter imports:
import 'package:flutter/material.dart';

/// Default avatar id used when [LocalUser.avatarId] is null or unknown.
/// Always present in [AvatarCatalog.all].
const String kAvatarDefaultId = 'avatar_default';

/// One selectable avatar (preset character + brand-tinted background).
///
/// Rendered inside [AvatarWithRing] as a centered [Text] emoji over a tinted
/// disk. Background colors mirror the Turna wetland palette (see
/// `lib/views/theme.dart`) so the avatar stays on palette, but are duplicated
/// as hex constants here to keep the domain layer free of UI imports — the
/// same pattern used by [AvatarRing].
class Avatar {
  const Avatar({
    required this.id,
    required this.emoji,
    required this.name,
    required this.background,
  });

  /// Stable id stored on [LocalUser.avatarId].
  final String id;

  /// Single emoji that visually represents the character.
  ///
  /// Kept as a string (not `Icons` codepoint) so a future catalog can mix in
  /// non-emoji glyphs without an enum churn.
  final String emoji;

  /// Display name. Currently Chinese-only; future i18n can move this out.
  final String name;

  /// Disk tint drawn behind the emoji inside the avatar circle.
  final Color background;
}

/// Static, offline catalog of preset avatars. No network, no asset bundles.
///
/// Order is the user-visible order in the picker; keep it curated.
///
/// Background colors mirror the Turna wetland palette tokens
/// (`lib/views/theme.dart`). Hex duplication is intentional — keeps the
/// domain layer free of UI imports and prevents accidental theming
/// regressions when token values shift. Keep these in sync if the theme
/// changes.
class AvatarCatalog {
  AvatarCatalog._();

  // Wetland cool axis
  static const Color _navy = Color(0xFF19324A);
  static const Color _teal = Color(0xFF1F727E);
  static const Color _sky = Color(0xFF4A95A8);
  static const Color _reed = Color(0xFF78C7B8);

  // Anatolian warm accents
  static const Color _clay = Color(0xFFB85C3F);
  static const Color _sand = Color(0xFFEAD9B8);

  // League / accent
  static const Color _emerald = Color(0xFF27AE60);
  static const Color _amethyst = Color(0xFF9B59B6);
  static const Color _red = Color(0xFFE74C3C);

  static const List<Avatar> all = [
    Avatar(
      id: 'avatar_fox',
      emoji: '🦊',
      name: '小狐狸',
      background: _teal,
    ),
    Avatar(
      id: 'avatar_owl',
      emoji: '🦉',
      name: '猫头鹰',
      background: _navy,
    ),
    Avatar(
      id: 'avatar_tiger',
      emoji: '🐯',
      name: '小老虎',
      background: _clay,
    ),
    Avatar(
      id: 'avatar_panda',
      emoji: '🐼',
      name: '熊猫',
      background: _sky,
    ),
    Avatar(
      id: 'avatar_frog',
      emoji: '🐸',
      name: '青蛙',
      background: _reed,
    ),
    Avatar(
      id: 'avatar_lion',
      emoji: '🦁',
      name: '小狮子',
      background: _sand,
    ),
    Avatar(
      id: 'avatar_rabbit',
      emoji: '🐰',
      name: '兔子',
      background: _amethyst,
    ),
    Avatar(
      id: 'avatar_unicorn',
      emoji: '🦄',
      name: '独角兽',
      background: _sky,
    ),
    Avatar(
      id: 'avatar_cat',
      emoji: '🐱',
      name: '小猫',
      background: _red,
    ),
    Avatar(
      id: 'avatar_wolf',
      emoji: '🐺',
      name: '小狼',
      background: _navy,
    ),
    Avatar(
      id: 'avatar_dragon',
      emoji: '🐲',
      name: '小龙',
      background: _emerald,
    ),
    Avatar(
      id: kAvatarDefaultId,
      emoji: '👤',
      name: '默认',
      background: _teal,
    ),
  ];

  /// Look up by id. Returns null if [id] is unknown.
  static Avatar? byId(String? id) {
    if (id == null) return null;
    for (final a in all) {
      if (a.id == id) return a;
    }
    return null;
  }

  /// Resolves any id (including null / unknown) to a valid catalog entry.
  /// Always returns the default avatar as a last resort.
  static Avatar resolve(String? id) => byId(id) ?? defaultAvatar;

  static Avatar get defaultAvatar {
    // The catalog always contains kAvatarDefaultId; assert keeps the contract
    // honest if a future edit accidentally drops it.
    assert(all.any((a) => a.id == kAvatarDefaultId),
        'AvatarCatalog must always contain $kAvatarDefaultId');
    return all.firstWhere((a) => a.id == kAvatarDefaultId);
  }
}
