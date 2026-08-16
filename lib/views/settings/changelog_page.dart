// Flutter imports:
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

// Project imports:
import 'package:turna/l10n/app_strings.dart';
import 'package:turna/views/theme.dart';

/// Offline changelog of major milestones and feature batches.
///
/// Navigated via [Navigator.push] from About / Settings — no auto_route needed.
///
/// Renders [ChangelogFromAsset] (read from `assets/changelog.md`) and
/// falls back to a hard-coded list of milestones when the asset cannot be
/// loaded (e.g. test environment without asset bundle).
class ChangelogPage extends StatelessWidget {
  const ChangelogPage({super.key});

  /// 顶部"更新历程"卡的内容,放到顶层便于复制按钮复用。
  static const List<JourneyStep> journeySteps = [
    JourneyStep(
      label: '0.x',
      title: '原型与上游',
      subtitle: '2024 卡纳达 / 西班牙语原型 → 2026-03 fork',
    ),
    JourneyStep(
      label: '0.3.0',
      title: '离线优先重写',
      subtitle: 'Firebase 下线,SQLite + SRS + 13 种交互题型',
    ),
    JourneyStep(
      label: '0.4.0',
      title: 'future4 框架',
      subtitle: 'DI 整合、音频解耦、复习 / 字典 / 弱词合入',
    ),
    JourneyStep(
      label: '1.0.0',
      title: '土耳其语转向',
      subtitle: '语言由斯瓦希里语改为土耳其语,AI 助手上线',
    ),
    JourneyStep(
      label: '1.1.0',
      title: 'FSRS / AI / Anki',
      subtitle: '连续记忆模型、AI 引擎重构、Anki 智能化',
    ),
    JourneyStep(
      label: '1.2.0',
      title: 'AI 伴学与内容扩充',
      subtitle: '自由问答 / 诊断 / 收藏；土耳其语八章真实内容',
    ),
    JourneyStep(
      label: '1.3.0',
      title: 'Anki 原生渲染与吉祥物',
      subtitle: '原生展开卡面、练习解耦、全新湿地鹤视觉系统',
    ),
  ];

  /// 硬编码后援:asset 加载失败时使用。
  static const List<ChangelogRelease> fallbackReleases = [
    ChangelogRelease(
      version: '1.3.0',
      title: 'Anki 原生渲染与吉祥物升级',
      items: [
        'Anki 渲染重构：原生 HTML 展开式问答卡面，告别卡顿与 300px 翻转',
        '复习与练习双轨解耦：复习专注原卡四档评分，练习独立支持多题型交互',
        'Anki 导入体系优化：差异对比与映射编辑器，导入操作事务日志与恢复',
        '全新 Turna 湿地鹤吉祥物形象系统与全套学习场景插画',
        '系统健康诊断中心与全链路兼容性检测',
        'AI 伴学证据链沉淀、知识检索与上下文预算控制',
      ],
    ),
    ChangelogRelease(
      version: '1.2.0',
      title: 'AI 伴学与土耳其语内容扩充',
      items: [
        'AI 伴学全面升级：自由问答、学习诊断、讲解收藏、词典 AI 扩展、Anki 卡片讲解',
        '课内提示支持流式回复，并注入学习者上下文（水平、错题、讲解偏好）',
        'AI Hub 重组为伴学优先：自由问答 / 诊断 / 收藏讲解与创作类入口分区更清晰',
        '统一讲解偏好（回复语言、深度、是否允许给答案）与友好错误提示',
        '土耳其语内置课程大幅扩充：约 148 词、18 表达、8 语法点、54 课（A1→B2 八章）',
        '进度导出不再包含 API Key；移除小艺（Xiaoyi）桥接，统一走本地 AI 引擎',
      ],
    ),
    ChangelogRelease(
      version: '1.1.0',
      title: '间隔重复与 AI 引擎升级',
      items: [
        'FSRS 连续记忆模型与本地参数优化，复习曲线更贴合个人记忆',
        'Anki 智能牌组归类与牌型渲染重构，支持复杂 .apkg / .colpkg',
        'AI 引擎刷新：内存与磁盘缓存、可取消令牌、统一 HTTP 客户端',
        '课程管理页、AI 中心、应用图标、文案与本地化整体重写',
        '记忆曲线、复习进度与 SRS 学习导师等新面板',
      ],
    ),
    ChangelogRelease(
      version: '1.0.0',
      title: '土耳其语转向',
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
    ChangelogRelease(
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
    ChangelogRelease(
      version: '0.4.0',
      title: 'future4 框架',
      items: [
        '整洁架构收尾：DI 整合、音频与内容解耦、路由守卫',
        'SRS 队列基类、GameProvider 拆分与外观模式',
        '集成测试、Golden 基线与一键发布流水线',
        '学习统计、词典、弱词与提醒等能力合入主线',
      ],
    ),
    ChangelogRelease(
      version: 'ADR 0020',
      title: '土耳其语转向',
      items: [
        '目标语言由斯瓦希里语迁移为土耳其语（TTS：tr）',
        '移除 Piper 离线模型，改用系统 / Google TTS',
        '第 1 章问候语真实内容（词汇 + 表达），2–8 章占位待填充',
        '8 个 CEFR 分区（A1→B2）与区间前置依赖',
      ],
    ),
    ChangelogRelease(
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

  /// 拼接"页面可见文本"为 markdown,供一键复制使用。
  ///
  /// 顺序与画面一致:历程 → 各版本卡 → 页脚。完整工程说明见 `CHANGELOG.md`。
  static String buildClipboardText({
    List<ChangelogRelease> releases = fallbackReleases,
  }) {
    final buf = StringBuffer()
      ..writeln('# ${AppStrings.changelogTitle}')
      ..writeln()
      ..writeln(AppStrings.changelogIntro)
      ..writeln()
      ..writeln('## 更新历程')
      ..writeln();
    for (final step in journeySteps) {
      buf.writeln('- **${step.label}** ${step.title} — ${step.subtitle}');
    }
    buf.writeln();
    buf.writeln('## 版本详情');
    buf.writeln();
    for (final r in releases) {
      buf.writeln('### ${r.version} — ${r.title}');
      for (final item in r.items) {
        buf.writeln('- $item');
      }
      buf.writeln();
    }
    buf.writeln('---');
    buf.writeln();
    buf.writeln(AppStrings.changelogFooterNote);
    return buf.toString();
  }

  Future<void> _copyToClipboard(BuildContext context, String text) async {
    await Clipboard.setData(ClipboardData(text: text));
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(AppStrings.changelogCopied),
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 2),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: TurnaTheme.scaffoldBg(context),
      appBar: AppBar(
        title: Text(
          AppStrings.changelogTitle,
          style: Theme.of(context).textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.w700,
              ),
        ),
        actions: [
          IconButton(
            tooltip: AppStrings.changelogCopyTooltip,
            icon: const Icon(Icons.content_copy_rounded),
            onPressed: () => _copyToClipboard(
              context,
              buildClipboardText(),
            ),
          ),
        ],
      ),
      body: ChangelogFromAsset(
        showFallbackBanner: true,
        fallbackReleases: fallbackReleases,
        onCopyText: (text) => _copyToClipboard(context, text),
      ),
    );
  }
}

/// 顶部"更新历程"概览卡:把 0.x → 1.1.0 的关键阶段压缩成 6 步,
/// 引导用户顺读后续的版本卡片。完整工程说明见 `CHANGELOG.md`。
class JourneyOverviewCard extends StatelessWidget {
  const JourneyOverviewCard({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: TurnaTheme.cardBg(context),
        borderRadius: BorderRadius.circular(TurnaTheme.radiusLarge),
        border: Border.all(color: TurnaTheme.statCardBorder(context)),
        boxShadow: TurnaTheme.softShadow,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: TurnaTheme.brandTeal.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(TurnaTheme.radiusMedium),
                ),
                child: const Icon(
                  Icons.timeline_rounded,
                  color: TurnaTheme.brandTeal,
                  size: 20,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  '更新历程',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                      ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            'Varnamala Plus 从原型到 1.1.0 的 6 个阶段',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: TurnaTheme.textHintColor(context),
                ),
          ),
          const SizedBox(height: 12),
          for (var i = 0; i < ChangelogPage.journeySteps.length; i++)
            JourneyStepRow(
              step: ChangelogPage.journeySteps[i],
              isFirst: i == 0,
              isLast: i == ChangelogPage.journeySteps.length - 1,
            ),
        ],
      ),
    );
  }
}

/// 单条 release 数据。可公开复用。
class ChangelogRelease {
  final String version;
  final String title;
  final List<String> items;

  const ChangelogRelease({
    required this.version,
    required this.title,
    required this.items,
  });
}

/// 历程步骤数据。
class JourneyStep {
  final String label;
  final String title;
  final String subtitle;

  const JourneyStep({
    required this.label,
    required this.title,
    required this.subtitle,
  });
}

/// 默认的 asset 路径,可通过 [ChangelogFromAsset.assetPath] 覆盖。
const String kDefaultChangelogAssetPath = 'assets/changelog.md';

/// 从 `assets/changelog.md` 读取并渲染 changelog;失败时使用 fallback。
///
/// 切换到 About 页"更新日志"Tab 时,由 [AboutTurnaPage] 直接嵌入,
/// 不再走独立路由;`ChangelogPage` 独立路由仍保留,以兼容设置页入口与
/// 测试。
class ChangelogFromAsset extends StatelessWidget {
  /// 加载的资源路径,默认 `assets/changelog.md`。
  final String assetPath;

  /// 加载失败时使用的硬编码 release 列表。
  final List<ChangelogRelease> fallbackReleases;

  /// 是否在 fallback 路径上方显示一行提示。
  final bool showFallbackBanner;

  /// 当前已加载的 markdown 文本(用于复制按钮等需要 markdown 字符串的
  /// 场景);fallback 路径下传 null 则使用 [buildClipboardText] 硬编码版。
  final void Function(String text)? onCopyText;

  const ChangelogFromAsset({
    super.key,
    this.assetPath = kDefaultChangelogAssetPath,
    this.fallbackReleases = ChangelogPage.fallbackReleases,
    this.showFallbackBanner = false,
    this.onCopyText,
  });

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<String>(
      future: rootBundle.loadString(assetPath),
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return _LoadingState();
        }
        if (snapshot.hasError || !snapshot.hasData) {
          return _ReleaseList(
            releases: fallbackReleases,
            banner: showFallbackBanner ? AppStrings.changeloadFallback : null,
            sourceText: null,
            onCopyText: onCopyText,
          );
        }
        final releases = parseChangelogMarkdown(snapshot.data!);
        if (releases.isEmpty) {
          return _ReleaseList(
            releases: fallbackReleases,
            banner: showFallbackBanner ? AppStrings.changeloadFallback : null,
            sourceText: null,
            onCopyText: onCopyText,
          );
        }
        return _ReleaseList(
          releases: releases,
          banner: null,
          sourceText: snapshot.data,
          onCopyText: onCopyText,
        );
      },
    );
  }
}

/// 内部:聚焦中状态。
class _LoadingState extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(
              width: 28,
              height: 28,
              child: CircularProgressIndicator(
                strokeWidth: 2.5,
                color: TurnaTheme.brandTeal,
              ),
            ),
            const SizedBox(height: 12),
            Text(
              AppStrings.changelogIntro,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: TurnaTheme.textHintColor(context),
                  ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 内部:统一的 release 列表渲染。
class _ReleaseList extends StatelessWidget {
  final List<ChangelogRelease> releases;
  final String? banner;
  final String? sourceText;
  final void Function(String text)? onCopyText;

  const _ReleaseList({
    required this.releases,
    required this.banner,
    required this.sourceText,
    required this.onCopyText,
  });

  @override
  Widget build(BuildContext context) {
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
      children: [
        Text(
          AppStrings.changelogIntro,
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                height: 1.5,
                color: TurnaTheme.textSecondaryColor(context),
              ),
        ),
        const SizedBox(height: 16),
        const JourneyOverviewCard(),
        if (banner != null) ...[
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: TurnaTheme.warning.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(TurnaTheme.radiusMedium),
              border: Border.all(
                color: TurnaTheme.warning.withValues(alpha: 0.4),
              ),
            ),
            child: Row(
              children: [
                Icon(
                  Icons.warning_amber_rounded,
                  size: 18,
                  color: TurnaTheme.warning,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    banner!,
                    style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: TurnaTheme.textSecondaryColor(context),
                        ),
                  ),
                ),
              ],
            ),
          ),
        ],
        const SizedBox(height: 20),
        for (var i = 0; i < releases.length; i++) ...[
          ChangelogReleaseCard(
            release: releases[i],
            isLatest: i == 0,
          ),
          if (i < releases.length - 1) const SizedBox(height: 14),
        ],
        const SizedBox(height: 24),
        Text(
          AppStrings.changelogFooterNote,
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: TurnaTheme.textHintColor(context),
              ),
        ),
      ],
    );
  }
}

/// 把 `assets/changelog.md` 文本解析为 [ChangelogRelease] 列表。
///
/// 解析规则:
/// - `#` 标题跳过(整篇文档标题)。
/// - `## ` 视为新版本;剩余 `- item` 视为要点。
/// - 若 `##` 标题里包含 ` — ` / ` - `,则只保留后部分作为标题。
/// - 空行 / `---` 跳过。
/// - 无法识别的行视为段落,加入当前 version 的第一个 item 内。
List<ChangelogRelease> parseChangelogMarkdown(String markdown) {
  final releases = <ChangelogRelease>[];
  String? currentVersion;
  String? currentTitle;
  final currentItems = <String>[];

  void flush() {
    if (currentVersion != null) {
      releases.add(
        ChangelogRelease(
          version: currentVersion!,
          title: currentTitle ?? '',
          items: List.unmodifiable(currentItems),
        ),
      );
    }
    currentVersion = null;
    currentTitle = null;
    currentItems.clear();
  }

  /// 找 ` — ` 或 ` - ` 的位置;返回 -1 表示没找到。
  int findSeparator(String s) {
    final emIdx = s.indexOf(' — ');
    if (emIdx >= 0) return emIdx;
    return s.indexOf(' - ');
  }

  for (final rawLine in markdown.split('\n')) {
    final line = rawLine.trimRight();
    if (line.isEmpty) continue;
    if (line.startsWith('---')) continue;
    if (line.startsWith('# ')) continue;
    if (line.startsWith('## ')) {
      flush();
      final header = line.substring(3).trim();
      final sepIdx = findSeparator(header);
      if (sepIdx >= 0) {
        currentVersion = header.substring(0, sepIdx).trim();
        currentTitle = header.substring(sepIdx + 3).trim();
      } else {
        final spaceIdx = header.indexOf(' ');
        if (spaceIdx >= 0) {
          currentVersion = header.substring(0, spaceIdx).trim();
          currentTitle = header.substring(spaceIdx + 1).trim();
        } else {
          currentVersion = header;
          currentTitle = '';
        }
      }
      continue;
    }
    if (line.startsWith('- ')) {
      currentItems.add(line.substring(2).trim());
      continue;
    }
    // 其他行:归入当前 version 的"附加说明"段,作为单条目展示。
    if (currentVersion != null) {
      currentItems.add(line);
    }
  }
  flush();
  return releases;
}

class JourneyStepRow extends StatelessWidget {
  final JourneyStep step;
  final bool isFirst;
  final bool isLast;

  const JourneyStepRow({
    super.key,
    required this.step,
    required this.isFirst,
    required this.isLast,
  });

  @override
  Widget build(BuildContext context) {
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // 圆形节点 + 上下连接线
          SizedBox(
            width: 18,
            child: Column(
              children: [
                Expanded(
                  flex: 0,
                  child: Container(
                    width: 2,
                    height: isFirst ? 12 : 6,
                    color: isFirst
                        ? Colors.transparent
                        : TurnaTheme.brandTeal.withValues(alpha: 0.3),
                  ),
                ),
                Container(
                  width: 10,
                  height: 10,
                  decoration: BoxDecoration(
                    color: TurnaTheme.brandTeal,
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: TurnaTheme.cardBg(context),
                      width: 2,
                    ),
                  ),
                ),
                Expanded(
                  child: Container(
                    width: 2,
                    color: isLast
                        ? Colors.transparent
                        : TurnaTheme.brandTeal.withValues(alpha: 0.3),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 2,
                    ),
                    decoration: BoxDecoration(
                      color: TurnaTheme.brandTeal.withValues(alpha: 0.1),
                      borderRadius:
                          BorderRadius.circular(TurnaTheme.radiusSmall),
                    ),
                    child: Text(
                      step.label,
                      style: const TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        color: TurnaTheme.brandTeal,
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          step.title,
                          style:
                              Theme.of(context).textTheme.bodyMedium?.copyWith(
                                    fontWeight: FontWeight.w700,
                                    color: TurnaTheme.textPrimaryColor(context),
                                  ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          step.subtitle,
                          style:
                              Theme.of(context).textTheme.bodySmall?.copyWith(
                                    color: TurnaTheme.textHintColor(context),
                                  ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// release 卡片。最新的版本以品牌色描边 + 实心徽章样式做视觉强调。
class ChangelogReleaseCard extends StatelessWidget {
  final ChangelogRelease release;
  final bool isLatest;

  const ChangelogReleaseCard({
    super.key,
    required this.release,
    required this.isLatest,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: TurnaTheme.cardBg(context),
        borderRadius: BorderRadius.circular(TurnaTheme.radiusLarge),
        border: Border.all(
          color: isLatest
              ? TurnaTheme.brandTeal.withValues(alpha: 0.45)
              : TurnaTheme.statCardBorder(context),
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
                      ? TurnaTheme.brandTeal
                      : TurnaTheme.brandTeal.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(TurnaTheme.radiusRound),
                ),
                child: Text(
                  release.version,
                  style: TextStyle(
                    color: isLatest
                        ? TurnaTheme.textOnPrimary
                        : TurnaTheme.brandTeal,
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
                        color: TurnaTheme.brandTeal.withValues(alpha: 0.7),
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
                            color: TurnaTheme.textSecondaryColor(context),
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
