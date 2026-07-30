// Flutter imports:
import 'package:flutter/material.dart';

// Project imports:
import 'package:varnamala/l10n/app_strings.dart';
import 'package:varnamala/views/theme.dart';

/// Offline changelog of major milestones and feature batches.
///
/// Navigated via [Navigator.push] from About / Settings — no auto_route needed.
class ChangelogPage extends StatelessWidget {
  const ChangelogPage({super.key});

  /// Hard-coded so the page works fully offline.
  static const List<_ChangelogRelease> _releases = [
    _ChangelogRelease(
      version: '1.0.0',
      title: '当前版本',
      items: [
        '界面文案全面中文化，设置与关于页统一体验',
        'Anki 牌组导入（.apkg / .colpkg）与 Anki 复习入口',
        '课内 AI 提示助手，支持 DeepSeek 等兼容接口',
        'AI 课程设计器、教材导入与进度导出/导入',
        '独立设置页：主题、提醒、音效、无障碍与账户数据',
        '词典搜索、弱词复习、每日挑战与学习统计仪表盘',
        '暗色 / 亮色 / 跟随系统主题',
      ],
    ),
    _ChangelogRelease(
      version: '0.4.x',
      title: '体验与可访问性',
      items: [
        '无障碍：字号、减弱动效、高对比度、阅读障碍友好字体',
        '感官减弱与专注模式等神经多样性友好选项',
        '本地每日学习提醒（无 streak 修复付费逻辑）',
        '课程树完成 / 薄弱 / 待复习状态角标',
        '课程内容版本变更提示与进度重置选项',
      ],
    ),
    _ChangelogRelease(
      version: '0.4.0',
      title: 'future4 框架',
      items: [
        '整洁架构收尾：DI 整合、音频与内容解耦、路由守卫',
        'SRS 队列基类、GameProvider 拆分与外观模式',
        '集成测试、Golden 基线与一键发布流水线',
        '学习统计、词典、弱词与提醒等能力合入主线',
      ],
    ),
    _ChangelogRelease(
      version: 'ADR 0020',
      title: '土耳其语转向',
      items: [
        '目标语言由斯瓦希里语迁移为土耳其语（TTS：tr）',
        '移除 Piper 离线模型，改用系统 / Google TTS',
        '第 1 章问候语真实内容（词汇 + 表达），2–8 章占位待填充',
        '8 个 CEFR 分区（A1→B2）与区间前置依赖',
      ],
    ),
    _ChangelogRelease(
      version: '核心能力',
      title: '课程与复习引擎',
      items: [
        'Section → Unit → Lesson 层级与 13 种交互题型',
        '6 种课型模板：intro / practice / listening / reading / review / mastery',
        'SM-2 间隔重复（词汇 + 语法）与错题本 FIFO',
        'Match Madness 配对小游戏、纯本地 SQLite，无云端账号',
      ],
    ),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: VarnamalaTheme.scaffoldBg(context),
      appBar: AppBar(
        title: Text(
          AppStrings.changelogTitle,
          style: Theme.of(context).textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.w700,
              ),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
        children: [
          Text(
            AppStrings.changelogIntro,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  height: 1.5,
                  color: VarnamalaTheme.textSecondaryColor(context),
                ),
          ),
          const SizedBox(height: 20),
          for (var i = 0; i < _releases.length; i++) ...[
            _ReleaseCard(release: _releases[i], isLatest: i == 0),
            if (i < _releases.length - 1) const SizedBox(height: 14),
          ],
          const SizedBox(height: 24),
          Text(
            AppStrings.changelogFooterNote,
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: VarnamalaTheme.textHintColor(context),
                ),
          ),
        ],
      ),
    );
  }
}

class _ChangelogRelease {
  final String version;
  final String title;
  final List<String> items;

  const _ChangelogRelease({
    required this.version,
    required this.title,
    required this.items,
  });
}

class _ReleaseCard extends StatelessWidget {
  final _ChangelogRelease release;
  final bool isLatest;

  const _ReleaseCard({
    required this.release,
    required this.isLatest,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: VarnamalaTheme.cardBg(context),
        borderRadius: BorderRadius.circular(VarnamalaTheme.radiusLarge),
        border: Border.all(
          color: isLatest
              ? VarnamalaTheme.peacockTeal.withValues(alpha: 0.45)
              : VarnamalaTheme.statCardBorder(context),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: isLatest
                      ? VarnamalaTheme.peacockTeal
                      : VarnamalaTheme.peacockTeal.withValues(alpha: 0.12),
                  borderRadius:
                      BorderRadius.circular(VarnamalaTheme.radiusRound),
                ),
                child: Text(
                  release.version,
                  style: TextStyle(
                    color: isLatest
                        ? VarnamalaTheme.textOnPrimary
                        : VarnamalaTheme.peacockTeal,
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  release.title,
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          for (final item in release.items)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: Container(
                      width: 6,
                      height: 6,
                      decoration: BoxDecoration(
                        color: VarnamalaTheme.peacockTeal.withValues(alpha: 0.7),
                        shape: BoxShape.circle,
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      item,
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                            height: 1.45,
                            color: VarnamalaTheme.textSecondaryColor(context),
                          ),
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}
