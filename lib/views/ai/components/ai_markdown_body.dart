// Flutter imports:
import 'package:flutter/material.dart';

// Project imports:
import 'package:turna/core/simple_markdown.dart';
import 'package:turna/core/theme.dart';

/// Renders the chat Markdown subset as selectable text. User bubbles stay
/// plain [SelectableText]; this is for assistant replies.
class AiMarkdownBody extends StatelessWidget {
  const AiMarkdownBody({
    super.key,
    required this.source,
    required this.color,
  });

  final String source;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final blocks = parseSimpleMarkdown(source);
    if (blocks.isEmpty) {
      return SelectableText(source, style: TextStyle(color: color));
    }
    final base = Theme.of(context).textTheme.bodyMedium ?? const TextStyle();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (var i = 0; i < blocks.length; i++) ...[
          if (i > 0) const SizedBox(height: 6),
          _block(context, blocks[i], base),
        ],
      ],
    );
  }

  Widget _block(BuildContext context, MarkdownBlock block, TextStyle base) {
    switch (block.kind) {
      case MarkdownBlockKind.code:
        return Container(
          width: double.infinity,
          padding: const EdgeInsets.all(8),
          decoration: BoxDecoration(
            color: TurnaTheme.scaffoldBg(context),
            borderRadius: BorderRadius.circular(TurnaTheme.radiusSmall),
          ),
          child: SelectableText(
            block.code,
            style: base.copyWith(
              color: color,
              fontFamily: 'monospace',
              fontSize: 13,
            ),
          ),
        );
      case MarkdownBlockKind.heading:
        return SelectableText.rich(TextSpan(
          children: _spans(
            context,
            block.spans,
            base.copyWith(
              color: color,
              fontWeight: FontWeight.w700,
              fontSize: block.level == 1 ? 18 : 16,
            ),
          ),
        ));
      case MarkdownBlockKind.bullet:
      case MarkdownBlockKind.numbered:
        final marker =
            block.kind == MarkdownBlockKind.bullet ? '• ' : '${block.level}. ';
        return SelectableText.rich(TextSpan(
          style: base.copyWith(color: color),
          children: [
            TextSpan(text: marker),
            ..._spans(context, block.spans, base.copyWith(color: color)),
          ],
        ));
      case MarkdownBlockKind.paragraph:
        return SelectableText.rich(TextSpan(
          style: base.copyWith(color: color),
          children: _spans(context, block.spans, base.copyWith(color: color)),
        ));
    }
  }

  List<InlineSpan> _spans(
    BuildContext context,
    List<MarkdownSpan> spans,
    TextStyle style,
  ) {
    return [
      for (final span in spans)
        TextSpan(
          text: span.text,
          style: style.copyWith(
            fontWeight: span.bold ? FontWeight.w700 : style.fontWeight,
            fontStyle: span.italic ? FontStyle.italic : FontStyle.normal,
            fontFamily: span.code ? 'monospace' : style.fontFamily,
            backgroundColor: span.code ? TurnaTheme.scaffoldBg(context) : null,
          ),
        ),
    ];
  }
}
