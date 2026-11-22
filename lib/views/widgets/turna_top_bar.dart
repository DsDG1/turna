/// 全局二级页顶栏（ADR 0075 / 计划 §5.1）。
///
/// 透明画布（透出 L0 天光与页级几何）、4px 几何返回钮、统一标题角色
/// （[AppTextStyles.cardTitle]）与可选副标题、操作区和 4px 指示条 [bottom]。
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

class TurnaTopBar extends StatelessWidget implements PreferredSizeWidget {
  const TurnaTopBar({
    this.title,
    this.titleWidget,
    this.subtitle,
    this.leading,
    this.automaticallyImplyLeading = true,
    this.onBack,
    this.actions,
    this.bottom,
    this.centerTitle = false,
    this.showDivider = false,
    this.backgroundColor,
    super.key,
  });

  final String? title;
  final Widget? titleWidget;
  final String? subtitle;
  final Widget? leading;
  final bool automaticallyImplyLeading;
  final VoidCallback? onBack;
  final List<Widget>? actions;
  final PreferredSizeWidget? bottom;
  final bool centerTitle;
  final bool showDivider;
  final Color? backgroundColor;

  static const double barHeight = kToolbarHeight;

  @override
  Size get preferredSize =>
      Size.fromHeight(barHeight + (bottom?.preferredSize.height ?? 0.0));

  @override
  Widget build(BuildContext context) {
    final canPop = ModalRoute.of(context)?.canPop ?? false;
    final resolvedLeading =
        leading ??
        (automaticallyImplyLeading && (canPop || onBack != null)
            ? IconButton(
                tooltip: AppStrings.commonBack,
                onPressed: onBack ?? () => Navigator.of(context).maybePop(),
                icon: TurnaIcon(
                  TurnaIconId.arrowBack,
                  size: 20,
                  color: TurnaTheme.textPrimaryColor(context),
                ),
              )
            : null);

    final resolvedTitle =
        titleWidget ??
        (title != null
            ? Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: centerTitle
                    ? CrossAxisAlignment.center
                    : CrossAxisAlignment.start,
                children: [
                  Text(
                    title!,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AppTextStyles.cardTitle(context),
                  ),
                  if (subtitle != null && subtitle!.isNotEmpty)
                    Text(
                      subtitle!,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: AppTextStyles.captionSm(context),
                    ),
                ],
              )
            : null);

    return Material(
      color: backgroundColor ?? Colors.transparent,
      surfaceTintColor: Colors.transparent,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          AppBar(
            backgroundColor: Colors.transparent,
            surfaceTintColor: Colors.transparent,
            elevation: 0,
            scrolledUnderElevation: 0,
            centerTitle: centerTitle,
            automaticallyImplyLeading: false,
            leading: resolvedLeading,
            titleSpacing: resolvedLeading == null
                ? AppSpacing.pageMargin
                : AppSpacing.xs,
            title: resolvedTitle,
            actions: actions == null || actions!.isEmpty
                ? null
                : [...actions!, const SizedBox(width: AppSpacing.sm)],
            bottom: bottom,
          ),
          if (showDivider)
            Divider(
              height: 1,
              thickness: 1,
              color: TurnaTheme.dividerBg(context),
            ),
        ],
      ),
    );
  }
}

@Preview(name: 'Top bar · light', group: 'Wetland mist')
@Preview(
  name: 'Top bar · dark',
  group: 'Wetland mist',
  brightness: Brightness.dark,
)
Widget turnaTopBarPreview() => const Scaffold(
  appBar: TurnaTopBar(title: '课程管理', subtitle: '内置课程与记忆卡牌组', showDivider: true),
  body: SizedBox.expand(),
);
