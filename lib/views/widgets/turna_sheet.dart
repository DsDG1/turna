/// 全局弹层与对话框 ——「湿地雾光」统一 4px 弹层容器（ADR 0075 / 计划 §5.1）。
///
/// 弹层结构：**4px 矩形拖手 + 标题 + 一句说明 + 可滚动正文 + 操作区
/// （次左主右，危险操作红色动词）**；对话框（[TurnaDialogPanel]）与底部弹层
/// 同构，统一 4px 矩形边界与 1px 细描边，不再使用 Material 默认大圆角
/// `AlertDialog`。
library;

// Flutter imports:
import 'package:flutter/material.dart';
import 'package:flutter/widget_previews.dart';

// Project imports:
import 'package:turna/core/spacing.dart';
import 'package:turna/core/text_styles.dart';
import 'package:turna/core/theme.dart';
import 'package:turna/core/turna_icon_id.dart';
import 'package:turna/l10n/app_strings.dart';
import 'package:turna/views/widgets/turna_icon.dart';

/// 弹层 / 对话框底部操作区的一档动作。
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

/// 全局底部弹层（顶边两角 4px，底边贴屏 0px）。
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
  final bool expanded;

  @override
  Widget build(BuildContext context) {
    final maxHeight = MediaQuery.sizeOf(context).height * 0.88;

    return Container(
      constraints: BoxConstraints(maxHeight: maxHeight),
      decoration: BoxDecoration(
        color: TurnaTheme.cardBg(context),
        borderRadius: TurnaTheme.sheetTopBorderRadius,
        border: Border(
          top: BorderSide(color: TurnaTheme.dividerBg(context)),
          left: BorderSide(color: TurnaTheme.dividerBg(context)),
          right: BorderSide(color: TurnaTheme.dividerBg(context)),
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
                          Text(
                            subtitle!,
                            style: AppTextStyles.captionSm(context),
                          ),
                        ],
                      ],
                    ),
                  ),
                  if (showClose)
                    IconButton(
                      icon: const TurnaIcon(TurnaIconId.close, size: 20),
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
        width: 36,
        height: 4,
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: TurnaTheme.textHintColor(context).withValues(alpha: 0.45),
            borderRadius: TurnaTheme.borderRadius,
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
    final secondary = actions.where((a) => !a.primary).toList(growable: false);

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
          FilledButton(
            onPressed: primary.onPressed,
            style: FilledButton.styleFrom(
              backgroundColor: primary.destructive
                  ? TurnaTheme.error
                  : TurnaTheme.brandTeal,
              foregroundColor: TurnaTheme.textOnPrimary,
            ),
            child: Text(primary.label),
          ),
        ],
      ),
    );
  }
}

/// 统一 4px 对话框面板（与 [TurnaSheetPanel] 同构，替代原生 `AlertDialog`）。
class TurnaDialogPanel extends StatelessWidget {
  const TurnaDialogPanel({
    required this.title,
    required this.body,
    required this.actions,
    this.subtitle,
    this.maxWidth = 440,
    super.key,
  });

  final String title;
  final String? subtitle;
  final Widget body;
  final List<TurnaSheetAction> actions;
  final double maxWidth;

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.transparent,
      surfaceTintColor: Colors.transparent,
      elevation: 0,
      insetPadding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.xl,
        vertical: AppSpacing.xl,
      ),
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: maxWidth),
        child: Container(
          decoration: TurnaTheme.flatPaperDecoration(context)
              .copyWith(color: TurnaTheme.cardBg(context)),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(
                  AppSpacing.xl,
                  AppSpacing.xl,
                  AppSpacing.xl,
                  AppSpacing.sm,
                ),
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
              Flexible(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.xl,
                    vertical: AppSpacing.sm,
                  ),
                  child: body,
                ),
              ),
              if (actions.isNotEmpty) _SheetActionFooter(actions: actions),
            ],
          ),
        ),
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
    builder: (dialogContext) => TurnaDialogPanel(
      title: title,
      body: Text(
        message,
        style: AppTextStyles.bodyText(dialogContext)
            .copyWith(color: TurnaTheme.textSecondaryColor(dialogContext)),
      ),
      actions: [
        TurnaSheetAction(
          label: cancelLabel ?? AppStrings.commonCancel,
          onPressed: () => Navigator.of(dialogContext).pop(false),
        ),
        TurnaSheetAction(
          label: confirmLabel,
          primary: true,
          destructive: destructive,
          onPressed: () => Navigator.of(dialogContext).pop(true),
        ),
      ],
    ),
  );
}

/// 全局非破坏性信息弹层。
Future<void> showTurnaInfoDialog({
  required BuildContext context,
  required String title,
  required String message,
  String? doneLabel,
  bool selectable = false,
}) {
  return showDialog<void>(
    context: context,
    builder: (dialogContext) {
      final style = AppTextStyles.bodyText(dialogContext)
          .copyWith(color: TurnaTheme.textSecondaryColor(dialogContext));
      return TurnaDialogPanel(
        title: title,
        body: selectable
            ? SelectableText(message, style: style)
            : Text(message, style: style),
        actions: [
          TurnaSheetAction(
            label: doneLabel ?? AppStrings.commonDone,
            primary: true,
            onPressed: () => Navigator.of(dialogContext).pop(),
          ),
        ],
      );
    },
  );
}

/// 全局表单 / 自定义正文弹层。
Future<T?> showTurnaFormDialog<T>({
  required BuildContext context,
  required String title,
  String? subtitle,
  required Widget body,
  required List<TurnaSheetAction> actions,
  double maxWidth = 460,
  bool barrierDismissible = true,
}) {
  return showDialog<T>(
    context: context,
    barrierDismissible: barrierDismissible,
    builder: (_) => TurnaDialogPanel(
      title: title,
      subtitle: subtitle,
      body: body,
      actions: actions,
      maxWidth: maxWidth,
    ),
  );
}

@Preview(name: 'Sheet panel · light', group: 'Wetland mist')
@Preview(
  name: 'Sheet panel · dark',
  group: 'Wetland mist',
  brightness: Brightness.dark,
)
Widget turnaSheetPreview() => TurnaSheetPanel(
  title: '删除学习记录',
  subtitle: '只删除这一课的完成记录，不影响其他进度',
  body: const Padding(
    padding: EdgeInsets.all(AppSpacing.pageMargin),
    child: Text('正文区：说明、列表或表单。'),
  ),
  actions: const [
    TurnaSheetAction(label: '取消', onPressed: _noop),
    TurnaSheetAction(
      label: '删除',
      primary: true,
      destructive: true,
      onPressed: _noop,
    ),
  ],
);

void _noop() {}
