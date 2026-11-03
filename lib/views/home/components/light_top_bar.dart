/// 轻顶栏 ——「湿地雾光」外壳的上半件（P2 组件，P3 外壳重构接线）。
///
/// R01 决定：顶栏只留**课程名 + 切换 + 连胜**，状态数字（积分 / 宝石 /
/// 待复习胶囊）离开顶栏，回到所属页面的概览区。背景透明（画布即顶栏），
/// 高度沿用 [TurnaTheme.tabAppBarHeight]，四个根 Tab 与旧顶栏不跳基线。
library;

// Flutter imports:
import 'package:flutter/material.dart';
import 'package:flutter/widget_previews.dart';

// Project imports:
import 'package:turna/core/spacing.dart';
import 'package:turna/core/theme.dart';

/// 轻顶栏：左侧课程切换（名字 + 展开指示），右侧连胜标记。
class LightTopBar extends StatelessWidget implements PreferredSizeWidget {
  const LightTopBar({
    required this.courseName,
    this.onSwitchCourse,
    this.streakLabel,
    this.switchTooltip,
    super.key,
  });

  final String courseName;
  final VoidCallback? onSwitchCourse;

  /// 连胜文案（「7 天」）；空则右侧不渲染——连胜为 0 的新用户顶栏更干净。
  final String? streakLabel;

  /// 切换键语义名；缺省「关闭」以外的语义交给文案表。
  final String? switchTooltip;

  @override
  Size get preferredSize => const Size.fromHeight(TurnaTheme.tabAppBarHeight);

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      bottom: false,
      child: SizedBox(
        height: TurnaTheme.tabAppBarHeight,
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.pageMargin,
          ),
          child: Row(
            children: [
              Expanded(
                child: InkWell(
                  onTap: onSwitchCourse,
                  borderRadius: BorderRadius.circular(TurnaTheme.radiusMedium),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      vertical: AppSpacing.sm + 2,
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Flexible(
                          child: Text(
                            courseName,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.w600,
                              color: TurnaTheme.textPrimaryColor(context),
                            ),
                          ),
                        ),
                        const SizedBox(width: AppSpacing.xs + 2),
                        Icon(
                          Icons.expand_more_rounded,
                          size: 20,
                          color: TurnaTheme.textSecondaryColor(context),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              if (streakLabel != null && streakLabel!.isNotEmpty) ...[
                const SizedBox(width: AppSpacing.sm),
                Icon(
                  Icons.local_fire_department_rounded,
                  size: 15,
                  color: TurnaTheme.anatolianClay,
                ),
                const SizedBox(width: AppSpacing.xs),
                Text(
                  streakLabel!,
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: TurnaTheme.anatolianClay,
                    fontFeatures: [FontFeature.tabularFigures()],
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

@Preview(name: 'Light top bar · light', group: 'Wetland mist')
@Preview(
    name: 'Light top bar · dark',
    group: 'Wetland mist',
    brightness: Brightness.dark)
Widget lightTopBarPreview() => const Scaffold(
      body: Column(
        children: [
          LightTopBar(courseName: '土耳其语 · 新版', streakLabel: '7 天'),
          Expanded(child: SizedBox()),
        ],
      ),
    );
