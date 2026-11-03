/// 全局弹层 ——「湿地雾光」弹层模式（P2 组件，P3 / P4 逐域接线）。
///
/// 评审确认的弹层结构：**拖手 + 标题 + 一句说明 + 可滚动正文 + 操作区
/// （次左主右，危险操作红色动词）**；dialog 同构。它统一的是容器形状——
/// `showModalBottomSheet` 的 21 处调用与退出确认 / 设置确认类 dialog 各自
/// 手写「顶圆角 + 拖手 + 标题行 + 关闭键」的历史，由本文件收口。
///
/// 正文（`body`）与操作（`actions`）由调用方给；本组件不决定内容与文案。
/// 迁移发生在 P4 各域重构时，旧 sheet 原样保留。
library;

// Flutter imports:
import 'package:flutter/material.dart';
import 'package:flutter/widget_previews.dart';

// Project imports:
import 'package:turna/core/spacing.dart';
import 'package:turna/core/text_styles.dart';
import 'package:turna/core/theme.dart';
import 'package:turna/l10n/app_strings.dart';

/// 弹层底部操作区的一档动作。
class TurnaSheetAction {
  const TurnaSheetAction({
    required this.label,
    required this.onPressed,
    this.primary = false,
    this.destructive = false,
  });

  final String label;
  final VoidCallback? onPressed;

  /// 主操作（右侧实心）；其余为次操作（左侧文字钮）。
  final bool primary;

  /// 危险操作：主操作钮染错误色，且要求调用方给明确的**动词**文案。
  final bool destructive;
}

/// 全局底部弹层。
///
/// [body] 拥有自己的滚动（长内容时调用方放 `ListView` / `SingleChildScrollView`
/// 并用 `isScrollControlled` 获得近全屏高度）；键盘由本组件用 viewInsets 让位。
Future<T?> showTurnaSheet<T>({
  required BuildContext context,
  required String title,
  String? subtitle,
  required Widget body,
  List<TurnaSheetAction>? actions,
  bool showClose = true,
  bool isScrollControlled = false,
}) {
  return showModalBottomSheet<T>(
    context: context,
    isScrollControlled: true,
    enableDrag: true,
    backgroundColor: Colors.transparent,
    // 键盘弹出时整体让位（isScrollControlled 恒为真才能吃到 viewInsets）。
    builder: (sheetContext) => Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.viewInsetsOf(sheetContext).bottom,
      ),
      child: TurnaSheetPanel(
        title: title,
        subtitle: subtitle,
        body: body,
        actions: actions,
        showClose: showClose,
        expanded: isScrollControlled,
      ),
    ),
  );
}

/// 弹层面板本体（拖手 → 标题行 → 正文 → 操作区）。
///
/// 公开是为了 widget 测试与 @Preview 能脱离 modal 直接装配；页面一律走
/// [showTurnaSheet]。
class TurnaSheetPanel extends StatelessWidget {
  const TurnaSheetPanel({
    required this.title,
    required this.body,
    this.subtitle,
    this.actions,
    this.showClose = true,
    this.expanded = false,
    super.key,
  });

  final String title;
  final String? subtitle;
  final Widget body;
  final List<TurnaSheetAction>? actions;
  final bool showClose;

  /// `true` 时正文占满可用高度（配 `isScrollControlled` 的长内容）；
  /// 缺省按内容自适应。
  final bool expanded;

  @override
  Widget build(BuildContext context) {
    final maxHeight = MediaQuery.sizeOf(context).height * 0.88;

    return Container(
      constraints: BoxConstraints(maxHeight: maxHeight),
      decoration: BoxDecoration(
        color: TurnaTheme.cardBg(context),
        borderRadius: const BorderRadius.vertical(
          top: Radius.circular(TurnaTheme.radiusXLarge),
        ),
      ),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: expanded ? MainAxisSize.max : MainAxisSize.min,
          children: [
            const _SheetHandle(),
            Padding(
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.pageMargin,
                AppSpacing.sm,
                AppSpacing.sm,
                AppSpacing.sm,
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
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
                  if (showClose)
                    IconButton(
                      icon: const Icon(Icons.close_rounded),
                      tooltip: AppStrings.commonClose,
                      onPressed: () => Navigator.of(context).maybePop(),
                    ),
                ],
              ),
            ),
            Flexible(child: body),
            if (actions != null && actions!.isNotEmpty)
              _SheetActionFooter(actions: actions!),
          ],
        ),
      ),
    );
  }
}

class _SheetHandle extends StatelessWidget {
  const _SheetHandle();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: AppSpacing.sm),
      child: SizedBox(
        width: 38,
        height: 4,
        child: DecoratedBox(
          decoration: ShapeDecoration(
            color: TurnaTheme.textHintColor(context).withValues(alpha: 0.40),
            shape: const StadiumBorder(),
          ),
        ),
      ),
    );
  }
}

class _SheetActionFooter extends StatelessWidget {
  const _SheetActionFooter({required this.actions});

  final List<TurnaSheetAction> actions;

  @override
  Widget build(BuildContext context) {
    final primary = actions.lastWhere(
      (a) => a.primary,
      orElse: () => actions.first,
    );
    final secondary =
        actions.where((a) => !a.primary).toList(growable: false);

    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.pageMargin,
        AppSpacing.md,
        AppSpacing.pageMargin,
        AppSpacing.lg,
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          // 次操作：次左，文字钮，可多档。
          Row(
            children: [
              for (var i = 0; i < secondary.length; i++) ...[
                if (i > 0) const SizedBox(width: AppSpacing.sm),
                TextButton(
                  onPressed: secondary[i].onPressed,
                  style: TextButton.styleFrom(
                    foregroundColor: secondary[i].destructive
                        ? TurnaTheme.error
                        : TurnaTheme.textSecondaryColor(context),
                  ),
                  child: Text(secondary[i].label),
                ),
              ],
            ],
          ),
          // 主操作：主右，实心；危险操作染错误色。
          FilledButton(
            onPressed: primary.onPressed,
            style: FilledButton.styleFrom(
              backgroundColor:
                  primary.destructive ? TurnaTheme.error : TurnaTheme.brandTeal,
              foregroundColor: TurnaTheme.textOnPrimary,
            ),
            child: Text(primary.label),
          ),
        ],
      ),
    );
  }
}

/// 全局确认弹层（危险操作走 [destructive]；确认文案必须是动词）。
///
/// 返回 `true` 表示确认；取消 / 关闭一律 `false`（或 `null` 视调用方判空）。
Future<bool?> showTurnaConfirmDialog({
  required BuildContext context,
  required String title,
  required String message,
  required String confirmLabel,
  String? cancelLabel,
  bool destructive = false,
}) {
  return showDialog<bool>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      backgroundColor: TurnaTheme.cardBg(dialogContext),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(TurnaTheme.radiusXLarge),
      ),
      title: Text(title, style: AppTextStyles.sectionTitle(dialogContext)),
      content: Text(
        message,
        style: AppTextStyles.bodyText(dialogContext).copyWith(
              fontSize: 14,
              height: 1.5,
              color: TurnaTheme.textSecondaryColor(dialogContext),
            ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(dialogContext).pop(false),
          child: Text(cancelLabel ?? AppStrings.commonCancel),
        ),
        FilledButton(
          onPressed: () => Navigator.of(dialogContext).pop(true),
          style: FilledButton.styleFrom(
            backgroundColor:
                destructive ? TurnaTheme.error : TurnaTheme.brandTeal,
            foregroundColor: TurnaTheme.textOnPrimary,
          ),
          child: Text(confirmLabel),
        ),
      ],
    ),
  );
}

@Preview(name: 'Sheet panel · light', group: 'Wetland mist')
@Preview(
    name: 'Sheet panel · dark',
    group: 'Wetland mist',
    brightness: Brightness.dark)
Widget turnaSheetPreview() => TurnaSheetPanel(
      title: '删除学习记录',
      subtitle: '只删除这一课的完成记录，不影响其他进度',
      body: const Padding(
        padding: EdgeInsets.all(AppSpacing.pageMargin),
        child: Text('正文区：说明、列表或表单。'),
      ),
      actions: [
        const TurnaSheetAction(label: '取消', onPressed: _noop),
        const TurnaSheetAction(
          label: '删除',
          primary: true,
          destructive: true,
          onPressed: _noop,
        ),
      ],
    );

void _noop() {}
