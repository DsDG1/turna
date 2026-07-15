// Flutter imports:
import 'package:flutter/material.dart';

// Project imports:
import 'package:varnamala/views/theme.dart';

/// A single chat message bubble, shared by the AI hint chat and the AI wish
/// chat. `role == 'user'` is the right-aligned primary-tinted sender bubble;
/// anything else is the left-aligned assistant bubble. Both are theme-aware
/// via [VarnamalaTheme] so light/dark stay consistent without per-page
/// `isDark` plumbing.
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
    final bg = isUser
        ? VarnamalaTheme.primaryLight
        : VarnamalaTheme.cardBg(context);
    final textColor = isUser
        ? VarnamalaTheme.textOnPrimary
        : VarnamalaTheme.textPrimaryColor(context);
    return Align(
      alignment: isUser ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 4),
        padding: const EdgeInsets.all(10),
        constraints: BoxConstraints(
          maxWidth: MediaQuery.sizeOf(context).width * 0.8,
        ),
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(VarnamalaTheme.radiusMedium),
        ),
        child: Text(content, style: TextStyle(color: textColor)),
      ),
    );
  }
}