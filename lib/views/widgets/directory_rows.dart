/// 目录行族 ——「湿地雾光」阅读目录 / 偏好目录 / 任务台的公共行（ADR 0075）。
///
/// 评审确认的版面语言：**行不是卡**。目录用排版 + 发丝线（[Divider] 高 1
/// 的 [TurnaTheme.dividerBg]）组织，不逐行包卡片；状态用轮廓与形状表达
/// （实心 = 完成、环 = 当前、浅灰 = 未达 / 锁定），高对比下不靠颜色。
library;

// Flutter imports:
import 'package:flutter/material.dart';
import 'package:flutter/widget_previews.dart';

// Project imports:
import 'package:turna/core/spacing.dart';
import 'package:turna/core/text_styles.dart';
import 'package:turna/core/theme.dart';
import 'package:turna/core/turna_icon_id.dart';
import 'package:turna/views/widgets/turna_icon.dart';

/// 目录节点的旅程状态。形状语义：实心 = 完成，环 = 当前，淡 = 未达 / 锁定。
enum DirectoryNodeStatus { todo, current, done, locked }

/// 课时行：课程目录的主体行。
class DirectoryLessonRow extends StatelessWidget {
  const DirectoryLessonRow({
    required this.status,
    required this.title,
    this.indexLabel,
    this.meta,
    this.metaEmphasized = false,
    this.onTap,
    this.showDivider = true,
    super.key,
  });

  final DirectoryNodeStatus status;
  final int? indexLabel;
  final String title;
  final String? meta;
  final bool metaEmphasized;
  final VoidCallback? onTap;
  final bool showDivider;

  @override
  Widget build(BuildContext context) {
    final dimmed = status == DirectoryNodeStatus.locked;
    return _RowShell(
      onTap: status == DirectoryNodeStatus.locked ? null : onTap,
      showDivider: showDivider,
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 46),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
          child: Row(
            children: [
              _LessonSymbol(
                status: status,
                indexLabel: indexLabel,
                dimmed: dimmed,
              ),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppTextStyles.bodyText(context).copyWith(
                    fontWeight: status == DirectoryNodeStatus.current
                        ? FontWeight.w600
                        : FontWeight.w400,
                    color: dimmed
                        ? TurnaTheme.textHintColor(context)
                        : status == DirectoryNodeStatus.done
                        ? TurnaTheme.textSecondaryColor(context)
                        : TurnaTheme.textPrimaryColor(context),
                  ),
                ),
              ),
              if (meta != null && meta!.isNotEmpty) ...[
                const SizedBox(width: AppSpacing.sm),
                Text(
                  meta!,
                  style: AppTextStyles.captionSm(context).copyWith(
                    fontWeight: FontWeight.w600,
                    color: metaEmphasized
                        ? TurnaTheme.brandTeal
                        : dimmed
                        ? TurnaTheme.textHintColor(context)
                        : TurnaTheme.textSecondaryColor(context),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _LessonSymbol extends StatelessWidget {
  const _LessonSymbol({
    required this.status,
    required this.indexLabel,
    required this.dimmed,
  });

  final DirectoryNodeStatus status;
  final int? indexLabel;
  final bool dimmed;

  @override
  Widget build(BuildContext context) {
    final border = dimmed
        ? TurnaTheme.textHintColor(context)
        : TurnaTheme.dividerBg(context);
    return Container(
      width: 20,
      height: 20,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: status == DirectoryNodeStatus.done
            ? TurnaTheme.brandTeal
            : Colors.transparent,
        border: status == DirectoryNodeStatus.done
            ? null
            : Border.all(
                color: status == DirectoryNodeStatus.current
                    ? TurnaTheme.brandTeal
                    : border,
                width: status == DirectoryNodeStatus.current ? 2.5 : 1.5,
              ),
      ),
      child: switch (status) {
        DirectoryNodeStatus.done => const TurnaIcon(
          TurnaIconId.check,
          size: 12,
          color: TurnaTheme.textOnPrimary,
        ),
        DirectoryNodeStatus.current => null,
        _ =>
          indexLabel != null
              ? Text(
                  '$indexLabel',
                  style: AppTextStyles.caption(context).copyWith(
                    letterSpacing: 0,
                    color: dimmed
                        ? TurnaTheme.textHintColor(context)
                        : TurnaTheme.textSecondaryColor(context),
                  ),
                )
              : null,
      },
    );
  }
}

/// 子课行：比课时行矮一号，状态点 16。
class DirectorySubLessonRow extends StatelessWidget {
  const DirectorySubLessonRow({
    required this.status,
    required this.title,
    this.meta,
    this.onTap,
    this.showDivider = true,
    super.key,
  });

  final DirectoryNodeStatus status;
  final String title;
  final String? meta;
  final VoidCallback? onTap;
  final bool showDivider;

  @override
  Widget build(BuildContext context) {
    final isCurrent = status == DirectoryNodeStatus.current;
    final dimmed = status == DirectoryNodeStatus.locked;
    return _RowShell(
      onTap: dimmed ? null : onTap,
      showDivider: showDivider,
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 40),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm - 2),
          child: Row(
            children: [
              Container(
                width: 16,
                height: 16,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: status == DirectoryNodeStatus.done
                      ? TurnaTheme.brandTeal.withValues(alpha: 0.14)
                      : Colors.transparent,
                  border: status == DirectoryNodeStatus.done
                      ? null
                      : Border.all(
                          color: isCurrent
                              ? TurnaTheme.brandTeal
                              : TurnaTheme.dividerBg(context),
                          width: isCurrent ? 2.5 : 1.5,
                        ),
                ),
                child: status == DirectoryNodeStatus.done
                    ? const TurnaIcon(
                        TurnaIconId.check,
                        size: 10,
                        color: TurnaTheme.brandTeal,
                      )
                    : null,
              ),
              const SizedBox(width: AppSpacing.sm + 2),
              Expanded(
                child: Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppTextStyles.captionSm(context).copyWith(
                    color: dimmed
                        ? TurnaTheme.textHintColor(context)
                        : isCurrent
                        ? TurnaTheme.textPrimaryColor(context)
                        : TurnaTheme.textSecondaryColor(context),
                    fontWeight: isCurrent ? FontWeight.w600 : FontWeight.w400,
                  ),
                ),
              ),
              if (meta != null && meta!.isNotEmpty) ...[
                const SizedBox(width: AppSpacing.sm),
                Text(
                  meta!,
                  style: AppTextStyles.caption(context).copyWith(
                    letterSpacing: 0,
                    fontWeight: FontWeight.w500,
                    color: TurnaTheme.textHintColor(context),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// 单元 / 分组头：4px 序号块 + 名 + 计数 + 展开指示。
class DirectoryGroupHeader extends StatelessWidget {
  const DirectoryGroupHeader({
    required this.indexLabel,
    required this.title,
    this.meta,
    this.expanded = false,
    this.onTap,
    super.key,
  });

  final String indexLabel;
  final String title;
  final String? meta;
  final bool expanded;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 44),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: AppSpacing.md - 1),
          child: Row(
            children: [
              Container(
                width: 22,
                height: 22,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: TurnaTheme.brandTeal.withValues(alpha: 0.10),
                  borderRadius: TurnaTheme.borderRadius,
                ),
                child: Text(
                  indexLabel,
                  style: AppTextStyles.caption(context).copyWith(
                    letterSpacing: 0,
                    fontWeight: FontWeight.w700,
                    color: TurnaTheme.brandTeal,
                  ),
                ),
              ),
              const SizedBox(width: AppSpacing.sm + 2),
              Expanded(
                child: Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppTextStyles.cardTitle(context),
                ),
              ),
              if (meta != null && meta!.isNotEmpty) ...[
                const SizedBox(width: AppSpacing.sm),
                Text(
                  meta!,
                  style: AppTextStyles.captionSm(context).copyWith(
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
              ],
              const SizedBox(width: AppSpacing.xs + 2),
              TurnaIcon(
                expanded ? TurnaIconId.chevronUp : TurnaIconId.chevronDown,
                size: 16,
                color: TurnaTheme.textSecondaryColor(context),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// 任务行：任务台里有顺序的队列行（顺序即优先级，色条标来源）。
class DirectoryTaskRow extends StatelessWidget {
  const DirectoryTaskRow({
    required this.icon,
    required this.accent,
    required this.title,
    this.countLabel,
    this.emphasized = false,
    this.onTap,
    this.showDivider = true,
    super.key,
  });

  final TurnaIconId icon;
  final Color accent;
  final String title;
  final String? countLabel;
  final bool emphasized;
  final VoidCallback? onTap;
  final bool showDivider;

  @override
  Widget build(BuildContext context) {
    return _RowShell(
      onTap: onTap,
      showDivider: showDivider,
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 54),
        child: Padding(
          padding: const EdgeInsets.only(
            left: AppSpacing.sm + 2,
            top: AppSpacing.md + 2,
            bottom: AppSpacing.md + 2,
          ),
          child: Row(
            children: [
              Container(
                width: 4,
                height: 26,
                decoration: BoxDecoration(
                  color: accent,
                  borderRadius: TurnaTheme.borderRadius,
                ),
              ),
              const SizedBox(width: AppSpacing.md),
              TurnaIcon(
                icon,
                size: 16,
                color: emphasized
                    ? accent
                    : TurnaTheme.textSecondaryColor(context),
              ),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppTextStyles.bodyText(context).copyWith(
                    fontWeight: emphasized ? FontWeight.w600 : FontWeight.w500,
                  ),
                ),
              ),
              if (countLabel != null && countLabel!.isNotEmpty) ...[
                const SizedBox(width: AppSpacing.sm),
                Text(
                  countLabel!,
                  style: AppTextStyles.cardTitle(context).copyWith(
                    fontWeight: FontWeight.w700,
                    color: TurnaTheme.brandTealDark,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
              ],
              const SizedBox(width: AppSpacing.xs + 2),
              TurnaIcon(
                TurnaIconId.chevronRight,
                size: 16,
                color: TurnaTheme.textSecondaryColor(context),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// 阅读目录行：词典词条、收藏讲解、更新日志等「排版目录」的条目。
class DirectoryEntryRow extends StatelessWidget {
  const DirectoryEntryRow({
    required this.title,
    this.subtitle,
    this.meta,
    this.trailing,
    this.onTap,
    this.showDivider = true,
    super.key,
  });

  final String title;
  final String? subtitle;
  final String? meta;
  final Widget? trailing;
  final VoidCallback? onTap;
  final bool showDivider;

  @override
  Widget build(BuildContext context) {
    return _RowShell(
      onTap: onTap,
      showDivider: showDivider,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: AppSpacing.md + 1),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppTextStyles.cardTitle(context),
                  ),
                  if (subtitle != null && subtitle!.isNotEmpty) ...[
                    const SizedBox(height: AppSpacing.xs - 1),
                    Text(
                      subtitle!,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: AppTextStyles.captionSm(context),
                    ),
                  ],
                  if (meta != null && meta!.isNotEmpty) ...[
                    const SizedBox(height: AppSpacing.xs + 1),
                    Text(
                      meta!,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppTextStyles.caption(
                        context,
                      ).copyWith(letterSpacing: 0, fontWeight: FontWeight.w500),
                    ),
                  ],
                ],
              ),
            ),
            if (trailing != null) ...[
              const SizedBox(width: AppSpacing.md),
              trailing!,
            ],
          ],
        ),
      ),
    );
  }
}

/// 链接行：偏好目录的分类入口（4px 图标井 + 标题 + 一句说明）。
class DirectoryLinkRow extends StatelessWidget {
  const DirectoryLinkRow({
    required this.icon,
    required this.iconTone,
    required this.title,
    this.description,
    this.onTap,
    this.showDivider = true,
    super.key,
  });

  final TurnaIconId icon;
  final Color iconTone;
  final String title;
  final String? description;
  final VoidCallback? onTap;
  final bool showDivider;

  @override
  Widget build(BuildContext context) {
    return _RowShell(
      onTap: onTap,
      showDivider: showDivider,
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 64),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: AppSpacing.md + 1),
          child: Row(
            children: [
              Container(
                width: 38,
                height: 38,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: TurnaTheme.softTint(context, iconTone, alpha: 0.12),
                  borderRadius: TurnaTheme.borderRadius,
                ),
                child: TurnaIcon(
                  icon,
                  size: 18,
                  color: TurnaTheme.accentOnCard(context, iconTone),
                ),
              ),
              const SizedBox(width: AppSpacing.md + 2),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppTextStyles.cardTitle(context),
                    ),
                    if (description != null && description!.isNotEmpty) ...[
                      const SizedBox(height: AppSpacing.xs - 1),
                      Text(
                        description!,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: AppTextStyles.captionSm(context),
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: AppSpacing.xs + 2),
              TurnaIcon(
                TurnaIconId.chevronRight,
                size: 16,
                color: TurnaTheme.textSecondaryColor(context),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// 表单值行：偏好目录深页的「标签左、值右」行。
class DirectoryValueRow extends StatelessWidget {
  const DirectoryValueRow({
    required this.label,
    this.value,
    this.control,
    this.onTap,
    this.showDivider = true,
    super.key,
  });

  final String label;
  final String? value;
  final Widget? control;
  final VoidCallback? onTap;
  final bool showDivider;

  @override
  Widget build(BuildContext context) {
    final interactive = control == null && onTap != null;
    return _RowShell(
      onTap: interactive ? onTap : null,
      showDivider: showDivider,
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 52),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm + 2),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  label,
                  style: AppTextStyles.bodyText(context)
                      .copyWith(fontWeight: FontWeight.w500),
                ),
              ),
              if (control != null) ...[
                const SizedBox(width: AppSpacing.md),
                control!,
              ] else ...[
                if (value != null && value!.isNotEmpty) ...[
                  const SizedBox(width: AppSpacing.md),
                  Text(
                    value!,
                    style: AppTextStyles.bodyText(context).copyWith(
                      fontWeight: FontWeight.w600,
                      color: TurnaTheme.brandTeal,
                    ),
                  ),
                ],
                if (interactive) ...[
                  const SizedBox(width: AppSpacing.xs + 2),
                  TurnaIcon(
                    TurnaIconId.chevronRight,
                    size: 16,
                    color: TurnaTheme.textSecondaryColor(context),
                  ),
                ],
              ],
            ],
          ),
        ),
      ),
    );
  }
}

class _RowShell extends StatelessWidget {
  const _RowShell({required this.child, this.onTap, this.showDivider = true});

  final Widget child;
  final VoidCallback? onTap;
  final bool showDivider;

  @override
  Widget build(BuildContext context) {
    final row = InkWell(onTap: onTap, child: child);
    if (!showDivider) return row;
    return Container(
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(color: TurnaTheme.dividerBg(context)),
        ),
      ),
      child: row,
    );
  }
}

@Preview(name: 'Directory rows · light', group: 'Wetland mist')
@Preview(
  name: 'Directory rows · dark',
  group: 'Wetland mist',
  brightness: Brightness.dark,
)
Widget directoryRowsPreview() => const _DirectoryRowsPreview();

class _DirectoryRowsPreview extends StatelessWidget {
  const _DirectoryRowsPreview();

  @override
  Widget build(BuildContext context) {
    return const SingleChildScrollView(
      child: Padding(
        padding: EdgeInsets.symmetric(horizontal: AppSpacing.pageMargin),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            DirectoryGroupHeader(indexLabel: '5', title: '咖啡与茶', meta: '0 / 4'),
            DirectoryLessonRow(
              status: DirectoryNodeStatus.done,
              title: 'Merhaba!',
            ),
            DirectoryLessonRow(
              status: DirectoryNodeStatus.current,
              title: 'Merhaba，练熟它',
              meta: '下一个',
              metaEmphasized: true,
            ),
            DirectoryLessonRow(
              status: DirectoryNodeStatus.todo,
              indexLabel: 3,
              title: 'nasılsın？',
            ),
            DirectorySubLessonRow(
              status: DirectoryNodeStatus.current,
              title: '欢迎来到土耳其语的世界',
            ),
            SizedBox(height: AppSpacing.xl),
            DirectoryTaskRow(
              icon: TurnaIconId.book,
              accent: TurnaTheme.anatolianClay,
              title: '错题重练',
              countLabel: '6',
              emphasized: true,
            ),
            DirectoryTaskRow(
              icon: TurnaIconId.book,
              accent: TurnaTheme.brandTeal,
              title: '单词 · SRS',
              countLabel: '12',
            ),
            SizedBox(height: AppSpacing.xl),
            DirectoryEntryRow(
              title: 'merhaba',
              subtitle: '感叹词 · 你好',
              meta: 'Türkçe 1k · 已学',
            ),
            DirectoryLinkRow(
              icon: TurnaIconId.book,
              iconTone: TurnaTheme.brandTeal,
              title: '学习',
              description: '语言、课程更新、朗读与复习节奏',
            ),
            DirectoryValueRow(label: '主题', value: '跟随系统'),
          ],
        ),
      ),
    );
  }
}
