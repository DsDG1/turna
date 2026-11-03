// Flutter imports:
import 'package:flutter/material.dart';

// Project imports:
import 'package:turna/core/theme.dart';
import 'package:turna/views/ai/components/ai_markdown_body.dart';

/// A single chat message bubble, shared by the AI hint chat and the AI wish
/// chat. `role == 'user'` is the right-aligned primary-tinted sender bubble;
/// anything else is the left-aligned assistant bubble. Both are theme-aware
/// via [TurnaTheme] so light/dark stay consistent without per-page
/// `isDark` plumbing.
///
/// R14 纸面化：气泡不再是无边框的浮色块，统一走纸面（实色 + 发丝细边，
/// [TurnaTheme.flatPaperDecoration] 同族规格）——连续会话流里气泡靠对齐与
/// 细边区分，不靠投影。
class ChatBubble extends StatelessWidget {
  final String role;
  final String content;

  const ChatBubble({
    super.key,
    required this.role,
    required this.content,
  });

  @override
  Widget build(BuildContext context) {
    final isUser = role == 'user';
    final textColor = isUser
        ? TurnaTheme.textOnPrimary
        : TurnaTheme.textPrimaryColor(context);
    return Align(
      alignment: isUser ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 4),
        padding: const EdgeInsets.all(12),
        constraints: BoxConstraints(
          maxWidth: MediaQuery.sizeOf(context).width * 0.8,
        ),
        decoration: BoxDecoration(
          color: isUser ? TurnaTheme.primaryLight : TurnaTheme.cardBg(context),
          borderRadius: BorderRadius.circular(TurnaTheme.radiusMedium),
          border: Border.all(
            color: isUser
                ? TurnaTheme.brandTeal.withValues(alpha: 0.30)
                : TurnaTheme.dividerBg(context),
            width: 1,
          ),
        ),
        child: isUser
            ? SelectableText(content, style: TextStyle(color: textColor))
            : AiMarkdownBody(source: content, color: textColor),
      ),
    );
  }
}
