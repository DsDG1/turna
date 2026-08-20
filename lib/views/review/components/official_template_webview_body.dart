import 'package:flutter/material.dart';
import 'package:turna/domain/review/review_item.dart';
import 'package:turna/views/anki/anki_html_card_view.dart';
import 'package:turna/views/theme.dart';

/// WebView-based card body renderer for official Anki template cards.
///
/// Invariant: WebView is only the card body within the unified review scaffold,
/// not an entire duplicate review screen.
class OfficialTemplateWebViewBody extends StatelessWidget {
  final OfficialTemplateContent content;
  final bool isRevealed;
  final VoidCallback onReveal;

  const OfficialTemplateWebViewBody({
    super.key,
    required this.content,
    required this.isRevealed,
    required this.onReveal,
  });

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final html = isRevealed ? content.backHtml : content.frontHtml;

    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: TurnaTheme.cardBg(context),
        borderRadius: BorderRadius.circular(TurnaTheme.radiusLarge),
        border: Border.all(
          color: TurnaTheme.statCardBorder(context),
        ),
        boxShadow: [
          BoxShadow(
            color: TurnaTheme.brandTeal.withValues(alpha: 0.06),
            blurRadius: 20,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(TurnaTheme.radiusLarge),
        child: AnkiHtmlCardView(
          html: html,
          allowJs: true,
          dark: isDark,
          allowedMediaBasePath: content.mediaBasePath ?? '',
          isBack: isRevealed,
        ),
      ),
    );
  }
}
