import 'package:flutter/material.dart';
import 'package:turna/l10n/app_strings.dart';
import 'package:turna/views/theme.dart';

/// Top progress header and navigation bar for unified review sessions.
class ReviewProgressHeader extends StatelessWidget
    implements PreferredSizeWidget {
  final double progress;
  final int currentIndex;
  final int totalCount;
  final VoidCallback? onBack;
  final VoidCallback? onAiExplain;
  final VoidCallback? onUndo;
  final bool canUndo;
  final List<Widget> actions;
  final bool includeSafeArea;

  const ReviewProgressHeader({
    super.key,
    required this.progress,
    required this.currentIndex,
    required this.totalCount,
    this.onBack,
    this.onAiExplain,
    this.onUndo,
    this.canUndo = false,
    this.actions = const <Widget>[],
    this.includeSafeArea = true,
  });

  @override
  Size get preferredSize => const Size.fromHeight(60);

  @override
  Widget build(BuildContext context) {
    final content = Container(
      height: 60,
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Row(
        children: [
          IconButton(
            icon: const Icon(Icons.close_rounded),
            tooltip: AppStrings.commonBack,
            onPressed: onBack ?? () => Navigator.of(context).maybePop(),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: LinearProgressIndicator(
                value: progress,
                minHeight: 8,
                backgroundColor: TurnaTheme.brandTeal.withValues(alpha: 0.15),
                valueColor: const AlwaysStoppedAnimation<Color>(
                  TurnaTheme.brandTeal,
                ),
              ),
            ),
          ),
          const SizedBox(width: 12),
          Text(
            '$currentIndex / $totalCount',
            style: TextStyle(
              fontWeight: FontWeight.w700,
              fontSize: 13,
              color: TurnaTheme.textSecondaryColor(context),
            ),
          ),
          if (onAiExplain != null) ...[
            const SizedBox(width: 4),
            IconButton(
              tooltip: AppStrings.aiExplainCard,
              icon: const Icon(Icons.auto_awesome_rounded),
              onPressed: onAiExplain,
            ),
          ],
          if (onUndo != null) ...[
            const SizedBox(width: 4),
            IconButton(
              tooltip: '撤销上一张',
              icon: const Icon(Icons.undo_rounded),
              onPressed: canUndo ? onUndo : null,
            ),
          ],
          ...actions,
        ],
      ),
    );
    return includeSafeArea ? SafeArea(bottom: false, child: content) : content;
  }
}
