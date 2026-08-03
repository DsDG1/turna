// Flutter imports:
import 'package:flutter/material.dart';

// Project imports:
import 'package:turna/views/theme.dart';

/// Shared icon + color mapping for course sections.
///
/// Section shells currently lack a reliable CEFR [Section.level] at runtime
/// (level lives in index.json only and is not seeded into SQLite). Mapping by
/// section id keeps the switcher and picker visually distinct without a
/// schema change.
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
          background: TurnaTheme.peacockCyan.withValues(alpha: 0.18),
          foreground: TurnaTheme.peacockTeal,
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
          background: TurnaTheme.peacockTurquoise.withValues(alpha: 0.22),
          foreground: TurnaTheme.peacockTeal,
        ),
      _ => (
          background: TurnaTheme.tintSoft,
          foreground: TurnaTheme.textSecondary,
        ),
    };
  }
}
