// Flutter imports:
import 'package:flutter/material.dart';

// Project imports:
import 'package:varnamala/views/theme.dart';

/// Shared icon + color mapping for course sections.
///
/// Section shells currently lack a reliable CEFR [Section.level] at runtime
/// (level lives in index.json only and is not seeded into SQLite). Mapping by
/// section id keeps the switcher and picker visually distinct without a
/// schema change.
class SectionVisuals {
  const SectionVisuals._();

  /// Thematic icon for [sectionId]. Unknown ids fall back to a book icon.
  static IconData iconFor(String sectionId) {
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
  static ({Color background, Color foreground}) colorsFor(String sectionId) {
    return switch (sectionId) {
      'section1' => (
          background: VarnamalaTheme.success.withValues(alpha: 0.18),
          foreground: VarnamalaTheme.successDark,
        ),
      'section2' => (
          background: VarnamalaTheme.peacockCyan.withValues(alpha: 0.18),
          foreground: VarnamalaTheme.peacockTeal,
        ),
      'section3' => (
          background: VarnamalaTheme.warning.withValues(alpha: 0.18),
          foreground: VarnamalaTheme.warning,
        ),
      'section4' => (
          background: VarnamalaTheme.leagueAmethyst.withValues(alpha: 0.18),
          foreground: VarnamalaTheme.leagueAmethyst,
        ),
      'section5' => (
          background: VarnamalaTheme.leagueEmerald.withValues(alpha: 0.18),
          foreground: VarnamalaTheme.leagueEmerald,
        ),
      'section6' => (
          background: VarnamalaTheme.leagueDiamond.withValues(alpha: 0.18),
          foreground: VarnamalaTheme.leagueDiamond,
        ),
      'section7' => (
          background: VarnamalaTheme.leagueRuby.withValues(alpha: 0.18),
          foreground: VarnamalaTheme.leagueRuby,
        ),
      'section8' => (
          background: VarnamalaTheme.peacockTurquoise.withValues(alpha: 0.22),
          foreground: VarnamalaTheme.peacockTeal,
        ),
      _ => (
          background: VarnamalaTheme.tintSoft,
          foreground: VarnamalaTheme.textSecondary,
        ),
    };
  }
}
