/// Learn Tab 顶栏 ——「湿地雾光」外壳接线件（R01）。
///
/// [LightTopBar] 的数据装配：课程上下文来自 [CourseProvider]（当前章节
/// 名，回落语言显示名），连胜来自 [GameProvider] 的 streak 流。原
/// `StatAppBar` 的积分 / 宝石 / 待复习胶囊在此退役——状态数字回到各自
/// 所属页面（待复习数在练习台，积分与宝石在个人页），顶栏不再堆叠。
library;

// Flutter imports:
import 'package:flutter/material.dart';

// Package imports:
import 'package:auto_route/auto_route.dart';
import 'package:provider/provider.dart';

// Project imports:
import 'package:turna/application/course_provider.dart';
import 'package:turna/application/game_provider.dart';
import 'package:turna/application/language_registry.dart';
import 'package:turna/core/theme.dart';
import 'package:turna/domain/course/language_codes.dart';
import 'package:turna/l10n/app_strings.dart';
import 'package:turna/routing/routing.gr.dart';
import 'package:turna/views/home/components/light_top_bar.dart';

class LearnTopBar extends StatelessWidget implements PreferredSizeWidget {
  const LearnTopBar({super.key});

  @override
  Size get preferredSize => const Size.fromHeight(TurnaTheme.tabAppBarHeight);

  @override
  Widget build(BuildContext context) {
    final sectionName = context
        .select((CourseProvider p) => p.currentSection?.name);
    final courseLabel = (sectionName != null && sectionName.isNotEmpty)
        ? sectionName
        // 未装载或空目录时回落到语言显示名，避免顶栏闪空串。
        : LanguageRegistry.instance.displayName(LanguageCodes.turkish);

    return StreamBuilder<int>(
      stream: context.read<GameProvider>().getUserStreakStream(),
      builder: (context, snapshot) {
        final streak = snapshot.data ?? 0;
        return LightTopBar(
          courseName: courseLabel,
          onSwitchCourse: () => context.router.push(CourseManagementRoute()),
          switchTooltip: AppStrings.courseManagementTitle,
          streakLabel: streak > 0 ? AppStrings.accountStreakValue(streak) : null,
        );
      },
    );
  }
}
