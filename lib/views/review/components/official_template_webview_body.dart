import 'package:flutter/material.dart';
import 'package:turna/application/accessibility_capabilities.dart';
import 'package:turna/domain/review/review_item.dart';
import 'package:turna/views/anki/anki_card_shell.dart';
import 'package:turna/views/anki/anki_html_card_view.dart';

/// WebView-based card body renderer for official Anki template cards.
///
/// Invariant: WebView is only the card body within the unified review scaffold,
/// not an entire duplicate review screen. The card fills the remaining review
/// area (no content-height shrinking) and shares the app-wide card shell.
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
    final textZoom = cardTextScaleOf(context);

    return GestureDetector(
      onTap: isRevealed ? null : onReveal,
      child: AnkiWebViewCardShell(
        child: AnkiHtmlCardView(
          html: html,
          allowJs: true,
          dark: isDark,
          allowedMediaBasePath: content.mediaBasePath ?? '',
          isBack: isRevealed,
          textZoom: textZoom,
        ),
      ),
    );
  }
}
