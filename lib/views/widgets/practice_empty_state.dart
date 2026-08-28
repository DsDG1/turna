// Flutter imports:
import 'package:flutter/material.dart';

// Project imports:
import 'package:turna/views/theme.dart';

/// 练习/复习场景统一空状态：图标 + 主文案 + 可选副文案 + 可选动作按钮。
///
/// 纯内容组件：不包 Scaffold/AppBar，页面自行保留导航栏；作为 body 直接
/// 放置时整体居中。视觉骨架（图标 64 + 标题 + 副文案 + 单一动作按钮）由
/// 本组件统一，图标配色与文案由各入口按场景传入。
class PracticeEmptyState extends StatelessWidget {
  final IconData icon;
  final Color? accentColor;

  /// 主文案：一句话说明当前为空（如「暂无待复习项」）。
  final String title;

  /// 可选副文案：解释原因或下一步（如「新导入的卡片需先学习…」）。
  final String? message;

  /// 可选动作（刷新 / 返回 / 完成 / 导入…），统一为 tonal 按钮。
  final String? actionLabel;
  final VoidCallback? onAction;

  const PracticeEmptyState({
    super.key,
    this.icon = Icons.check_circle_rounded,
    this.accentColor,
    required this.title,
    this.message,
    this.actionLabel,
    this.onAction,
  });

  @override
  Widget build(BuildContext context) {
    final accent = accentColor ?? TurnaTheme.success;

    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 64, color: accent),
            const SizedBox(height: 16),
            Text(
              title,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.w800,
                  ),
            ),
            if (message != null && message!.isNotEmpty) ...[
              const SizedBox(height: 8),
              Text(
                message!,
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: TurnaTheme.textSecondaryColor(context),
                    ),
              ),
            ],
            if (actionLabel != null && onAction != null) ...[
              const SizedBox(height: 24),
              FilledButton.tonal(
                onPressed: onAction,
                child: Text(actionLabel!),
              ),
            ],
          ],
        ),
      ),
    );
  }
}