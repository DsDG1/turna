// Flutter imports:
import 'dart:async';

import 'package:flutter/material.dart';

// Package imports:
import 'package:auto_route/auto_route.dart';
import 'package:provider/provider.dart';

// Project imports:
import 'package:turna/application/achievements/achievement_service.dart';
import 'package:turna/application/game_provider.dart';
import 'package:turna/application/gems_provider.dart';
import 'package:turna/core/spacing.dart';
import 'package:turna/core/text_styles.dart';
import 'package:turna/core/theme.dart';
import 'package:turna/domain/achievements/achievement_catalog.dart';
import 'package:turna/l10n/app_strings.dart';
import 'package:turna/routing/routing.gr.dart';
import 'package:turna/views/profile/widgets/account_app_bar.dart';
import 'package:turna/views/profile/widgets/learning_stats.dart';
import 'package:turna/views/profile/widgets/profile_quick_actions.dart';
import 'package:turna/views/profile/widgets/share_progress_sheet.dart';
import 'package:turna/views/widgets/directory_rows.dart';
import 'package:turna/views/widgets/report_kit.dart';

/// Profile page（「湿地雾光」R15 学习档案）。
///
/// 版面自上而下：页内 pageTitle 开篇（Tab 级 [ProfileAppBar] 已退役）→
/// 身份行（头像 + 昵称 + 一句概览）→ 今日一行 → 学习积累四数（积分与
/// 宝石随顶栏状态胶囊退役回到这里安家）→ 今日待办 → 记录与成就章节行
/// （[DirectoryLinkRow] 目录行，行不是卡）。
class ProfilePage extends StatelessWidget {
  const ProfilePage({super.key});

  @override
  Widget build(BuildContext context) {
    // 本页没有页级几何主视觉位：身份行以下全是纸面行族，页级大形会从行
    // 缝里漏出来。成就环缩进身份卡内、垫在模糊层之下（见 AccountWidget），
    // 由卡自身的圆角裁掉一截——那才是"玻璃盖在几何上"。
    return CustomScrollView(
      physics: const BouncingScrollPhysics(),
      slivers: [
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.pageMargin,
              AppSpacing.sm + 4,
              AppSpacing.pageMargin,
              0,
            ),
            child: Text(
              AppStrings.profileTitle,
              style: AppTextStyles.pageTitle(context),
            ),
          ),
        ),
        const SliverToBoxAdapter(child: SizedBox(height: AppSpacing.lg)),
        // 身份行：本页唯一的玻璃对象（装饰主题卡），其余区块走纸面与行族。
        SliverToBoxAdapter(
          child: Padding(
            padding: AppSpacing.pageGutterMist,
            child: AccountWidget(
              onShare: () => showShareProgressSheet(context),
            ),
          ),
        ),
        const SliverToBoxAdapter(child: SizedBox(height: AppSpacing.xl)),
        const SliverToBoxAdapter(child: TodaySummaryCard()),
        const SliverToBoxAdapter(child: SizedBox(height: AppSpacing.lg)),
        const SliverToBoxAdapter(child: _AccumulationSection()),
        const SliverToBoxAdapter(child: SizedBox(height: AppSpacing.xl)),
        const SliverToBoxAdapter(child: ProfileQuickActions()),
        const SliverToBoxAdapter(child: SizedBox(height: AppSpacing.xl)),
        const SliverToBoxAdapter(child: _RecordEntries()),
        SliverPadding(
          padding: EdgeInsets.only(
            bottom: AppSpacing.xl + MediaQuery.paddingOf(context).bottom,
          ),
        ),
      ],
    );
  }
}

/// 学习积累四数：总经验 / 宝石 / 连续天数 / 完成课程。
///
/// 顶栏状态胶囊退役（R01）后，积分与宝石在个人页安家；四数以定义列表
/// 呈现（纸面 + 发丝线）。流订阅挂在 State 上，值变更即刷新。
class _AccumulationSection extends StatefulWidget {
  const _AccumulationSection();

  @override
  State<_AccumulationSection> createState() => _AccumulationSectionState();
}

class _AccumulationSectionState extends State<_AccumulationSection> {
  StreamSubscription<int>? _scoreSub;
  StreamSubscription<int>? _gemsSub;
  StreamSubscription<int>? _streakSub;
  int _score = 0;
  int _gems = 0;
  int _streak = 0;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final game = context.read<GameProvider>();
    final gems = context.read<GemsProvider>();
    // read（非 watch）：Provider 重建不该重建订阅；流自身带初值。
    _scoreSub ??= game.getUserScoreStream().listen(
          (v) => setState(() => _score = v),
        );
    _gemsSub ??= gems.getGemsStream().listen(
          (v) => setState(() => _gems = v),
        );
    _streakSub ??= game.getUserStreakStream().listen(
          (v) => setState(() => _streak = v),
        );
  }

  @override
  void dispose() {
    _scoreSub?.cancel();
    _gemsSub?.cancel();
    _streakSub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final lessonsCompleted =
        context.read<GameProvider>().currentUserGameState.lessonsCompleted;

    return Padding(
      padding: AppSpacing.pageGutterMist,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(bottom: AppSpacing.md),
            child: Text(
              AppStrings.profileAccumulationTitle,
              style: AppTextStyles.sectionTitle(context),
            ),
          ),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.lg,
              vertical: AppSpacing.sm,
            ),
            decoration: TurnaTheme.flatPaperDecoration(context),
            child: ReportDefinitionList(
              rows: [
                ReportDefinitionRow(
                  label: AppStrings.profileTotalXp,
                  value: '$_score',
                  valueColor: TurnaTheme.textPrimaryColor(context),
                ),
                ReportDefinitionRow(
                  label: AppStrings.profileGems,
                  value: '$_gems',
                  valueColor: TurnaTheme.textPrimaryColor(context),
                ),
                ReportDefinitionRow(
                  label: AppStrings.profileDayStreak,
                  value: AppStrings.accountStreakValue(_streak),
                  valueColor: TurnaTheme.textPrimaryColor(context),
                ),
                ReportDefinitionRow(
                  label: AppStrings.profileLessonsDone,
                  value: '$lessonsCompleted',
                  valueColor: TurnaTheme.textPrimaryColor(context),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// 记录与成就章节行：目录行族（图标井 + 一句说明），发丝线分隔。
class _RecordEntries extends StatelessWidget {
  const _RecordEntries();

  @override
  Widget build(BuildContext context) {
    final achievements = context.watch<AchievementService>();
    final total = AchievementCatalog.totalBadgeCount;
    final unlocked = achievements.unlockedBadgeCount;
    final nearComplete = achievements
        .progressViews()
        .where((v) =>
            !v.isSeriesComplete && v.nextTier != null && v.currentProgress > 0)
        .length;

    final badgeSummary = nearComplete > 0
        ? '${AppStrings.profileAchievementsBadgeCount(unlocked, total)} · '
            '${AppStrings.profileAchievementsNearComplete(nearComplete)}'
        : AppStrings.profileAchievementsBadgeCount(unlocked, total);

    return Padding(
      padding: AppSpacing.pageGutterMist,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          DirectoryLinkRow(
            icon: Icons.insights_rounded,
            iconTone: TurnaTheme.brandTeal,
            title: AppStrings.profileLearningStatsTitle,
            description: AppStrings.profileStatsEntrySubtitle,
            onTap: () => context.router.push(const ReviewProgressRoute()),
          ),
          DirectoryLinkRow(
            // Achievement section uses secondary brand clay (ADR 0033).
            icon: Icons.military_tech_rounded,
            iconTone: TurnaTheme.anatolianClay,
            title: AppStrings.profileAchievementsTitle,
            description: badgeSummary,
            showDivider: false,
            onTap: () => context.router.push(const AchievementsRoute()),
          ),
        ],
      ),
    );
  }
}
