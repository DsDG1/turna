/// 长文阅读共享原语（计划 R18 / P0 问题 B9 收口）。
///
/// 供关于、隐私详情、透明日志、更新日志与 AI 功能指南共用，消除各页各自
/// 复制 `_AboutCard` / `_SectionHeader` 的历史。统一采用纸面材质 + 4px
/// 圆角 + [AppTextStyles] 文字角色 + [AppSpacing] 节奏。
library;

// Flutter imports:
import 'package:flutter/material.dart';

// Project imports:
import 'package:turna/core/spacing.dart';
import 'package:turna/core/text_styles.dart';
import 'package:turna/core/theme.dart';
import 'package:turna/core/turna_icon_id.dart';
import 'package:turna/views/widgets/turna_icon.dart';

/// 长文页面内的章节标题行（可选序号或几何色标）。
class TurnaReadingSectionHeader extends StatelessWidget {
  const TurnaReadingSectionHeader({
    required this.title,
    this.indexLabel,
    this.subtitle,
    this.trailing,
    super.key,
  });

  final String title;
  final String? indexLabel;
  final String? subtitle;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.md),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (indexLabel != null && indexLabel!.isNotEmpty) ...[
            Container(
              padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.sm,
                vertical: AppSpacing.xs,
              ),
              decoration: BoxDecoration(
                color: TurnaTheme.brandTeal.withValues(alpha: 0.12),
                borderRadius: TurnaTheme.borderRadius,
              ),
              child: Text(
                indexLabel!,
                style: AppTextStyles.caption(context).copyWith(
                  color: TurnaTheme.brandTeal,
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
            ),
            const SizedBox(width: AppSpacing.sm),
          ],
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: AppTextStyles.sectionTitle(context)),
                if (subtitle != null && subtitle!.isNotEmpty) ...[
                  const SizedBox(height: AppSpacing.xs),
                  Text(subtitle!, style: AppTextStyles.captionSm(context)),
                ],
              ],
            ),
          ),
          if (trailing != null) trailing!,
        ],
      ),
    );
  }
}

/// 长文纸面正文卡（4px + 1px 发丝边）。
class TurnaReadingCard extends StatelessWidget {
  const TurnaReadingCard({required this.child, this.padding, super.key});

  final Widget child;
  final EdgeInsetsGeometry? padding;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: padding ?? const EdgeInsets.all(AppSpacing.lg),
      decoration: TurnaTheme.flatPaperDecoration(context),
      child: child,
    );
  }
}

/// 长文内的 4px 语义标签（替代旧胶囊 pill）。
class TurnaReadingBadge extends StatelessWidget {
  const TurnaReadingBadge({
    required this.label,
    this.color,
    this.icon,
    super.key,
  });

  final String label;
  final Color? color;
  final TurnaIconId? icon;

  @override
  Widget build(BuildContext context) {
    final accent = color ?? TurnaTheme.brandTeal;
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.sm,
        vertical: AppSpacing.xs,
      ),
      decoration: BoxDecoration(
        color: accent.withValues(alpha: 0.12),
        borderRadius: TurnaTheme.borderRadius,
        border: Border.all(color: accent.withValues(alpha: 0.28)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            TurnaIcon(icon!, size: 14, color: accent),
            const SizedBox(width: AppSpacing.xs),
          ],
          Text(
            label,
            style: AppTextStyles.captionSm(context)
                .copyWith(color: accent, fontWeight: FontWeight.w600),
          ),
        ],
      ),
    );
  }
}
