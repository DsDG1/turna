// Flutter imports:
import 'package:flutter/material.dart';

// Project imports:
import 'package:turna/core/text_styles.dart';
import 'package:turna/core/theme.dart';
import 'package:turna/core/turna_icon_id.dart';

/// Shared icon + color mapping for course sections.
///
/// Icons and colors stay keyed by section id (`section1`–`section8`, and the
/// `anki-` prefix). A non-empty CEFR level is a text chip via
/// [SectionLevelLabel]; it does not change the icon.
class SectionVisuals {
  const SectionVisuals._();

  /// Thematic icon for [sectionId]. Unknown ids fall back to a book icon;
  /// imported memory-card decks (id prefix 'anki-') get a dedicated cards icon.
  static TurnaIconId iconFor(String sectionId) {
    if (sectionId.startsWith('anki-')) return TurnaIconId.cards;
    return switch (sectionId) {
      'section1' => TurnaIconId.sunrise,
      'section2' => TurnaIconId.leaf,
      'section3' => TurnaIconId.sun,
      'section4' => TurnaIconId.chat,
      'section5' => TurnaIconId.translate,
      'section6' => TurnaIconId.speakVoice,
      'section7' => TurnaIconId.brain,
      'section8' => TurnaIconId.explore,
      _ => TurnaIconId.book,
    };
  }

  /// Soft background + icon tint for [sectionId], cycling the app palette.
  /// Imported memory-card decks (id prefix 'anki-') share one fixed pairing.
  static ({Color background, Color foreground}) colorsFor(String sectionId) {
    if (sectionId.startsWith('anki-')) {
      return (
        background: TurnaTheme.achievementAmethyst.withValues(alpha: 0.18),
        foreground: TurnaTheme.achievementAmethyst,
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
        background: TurnaTheme.achievementAmethyst.withValues(alpha: 0.18),
        foreground: TurnaTheme.achievementAmethyst,
      ),
      'section5' => (
        background: TurnaTheme.achievementEmerald.withValues(alpha: 0.18),
        foreground: TurnaTheme.achievementEmerald,
      ),
      'section6' => (
        background: TurnaTheme.brandSky.withValues(alpha: 0.18),
        foreground: TurnaTheme.brandSky,
      ),
      'section7' => (
        background: TurnaTheme.anatolianClay.withValues(alpha: 0.18),
        foreground: TurnaTheme.anatolianClay,
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
        borderRadius: TurnaTheme.borderRadius,
      ),
      child: Text(
        text,
        style: AppTextStyles.caption(context).copyWith(
          letterSpacing: 0,
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
