// Flutter imports:
import 'package:flutter/material.dart';

// Project imports:
import 'package:turna/core/theme.dart';

/// Shared icon + color mapping for course sections.
///
/// Icons and colors stay keyed by section id (`section1`–`section8`, and the
/// `anki-` prefix). A non-empty CEFR level is a text chip via
/// [SectionLevelLabel]; it does not change the icon.
class SectionVisuals {
  const SectionVisuals._();

  /// Thematic icon for [sectionId]. Unknown ids fall back to a book icon;
  /// imported Anki decks (id prefix 'anki-') get a dedicated card-stack icon.
  static IconData iconFor(String sectionId) {
    if (sectionId.startsWith('anki-')) return Icons.style_rounded;
    return switch (sectionId) {
      'section1' => Icons.waving_hand_rounded,
      'section2' => Icons.pets_rounded,
      'section3' => Icons.mood_rounded,
      'section4' => Icons.chat_bubble_rounded,
      'section5' => Icons.forum_rounded,
      'section6' => Icons.record_voice_over_rounded,
      'section7' => Icons.psychology_rounded,
      'section8' => Icons.flight_takeoff_rounded,
      _ => Icons.menu_book_rounded,
    };
  }

  /// Soft background + icon tint for [sectionId], cycling the app palette.
  /// Imported Anki decks (id prefix 'anki-') share one fixed pairing.
  static ({Color background, Color foreground}) colorsFor(String sectionId) {
    if (sectionId.startsWith('anki-')) {
      return (
        background: TurnaTheme.leagueAmethyst.withValues(alpha: 0.18),
        foreground: TurnaTheme.leagueAmethyst,
      );
    }
    return switch (sectionId) {
      'section1' => (
          background: TurnaTheme.success.withValues(alpha: 0.18),
          foreground: TurnaTheme.successDark,
        ),
      'section2' => (
          background: TurnaTheme.brandSky.withValues(alpha: 0.18),
          foreground: TurnaTheme.brandTeal,
        ),
      'section3' => (
          background: TurnaTheme.warning.withValues(alpha: 0.18),
          foreground: TurnaTheme.warning,
        ),
      'section4' => (
          background: TurnaTheme.leagueAmethyst.withValues(alpha: 0.18),
          foreground: TurnaTheme.leagueAmethyst,
        ),
      'section5' => (
          background: TurnaTheme.leagueEmerald.withValues(alpha: 0.18),
          foreground: TurnaTheme.leagueEmerald,
        ),
      'section6' => (
          background: TurnaTheme.leagueDiamond.withValues(alpha: 0.18),
          foreground: TurnaTheme.leagueDiamond,
        ),
      'section7' => (
          background: TurnaTheme.leagueRuby.withValues(alpha: 0.18),
          foreground: TurnaTheme.leagueRuby,
        ),
      'section8' => (
          background: TurnaTheme.brandReed.withValues(alpha: 0.22),
          foreground: TurnaTheme.brandTeal,
        ),
      _ => (
          background: TurnaTheme.tintSoft,
          foreground: TurnaTheme.textSecondary,
        ),
    };
  }
}

/// Small CEFR tag. An empty level takes no space.
class SectionLevelLabel extends StatelessWidget {
  const SectionLevelLabel(this.level, {super.key});

  final String? level;

  @override
  Widget build(BuildContext context) {
    final text = level?.trim() ?? '';
    if (text.isEmpty) return const SizedBox.shrink();
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: TurnaTheme.tintSoft,
        borderRadius: BorderRadius.circular(TurnaTheme.radiusSmall),
      ),
      child: Text(
        text,
        style: TextStyle(
          fontSize: 11,
          fontWeight: FontWeight.w700,
          color: TurnaTheme.textSecondaryColor(context),
        ),
      ),
    );
  }
}

/// Section title. An empty [level] returns the name alone, so rows without a
/// tag keep the previous layout.
Widget sectionNameWithLevel({
  required String name,
  required String? level,
  required TextStyle style,
  int? maxLines,
}) {
  final tag = level?.trim() ?? '';
  final text = Text(
    name,
    maxLines: tag.isEmpty ? maxLines : (maxLines ?? 1),
    overflow: tag.isEmpty
        ? (maxLines == null ? null : TextOverflow.ellipsis)
        : TextOverflow.ellipsis,
    style: style,
  );
  if (tag.isEmpty) return text;
  return Row(
    children: [
      Flexible(child: text),
      const SizedBox(width: 8),
      SectionLevelLabel(tag),
    ],
  );
}
