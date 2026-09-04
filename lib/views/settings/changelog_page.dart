// Flutter imports:
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

// Package imports:
import 'package:auto_route/auto_route.dart';

// Project imports:
import 'package:turna/application/settings/release_manifest.dart';
import 'package:turna/l10n/app_strings.dart';
import 'package:turna/views/theme.dart';

/// Offline changelog of major milestones and feature batches.
///
/// Renders [ChangelogFromAsset] (read from `assets/changelog.md`) and
/// falls back to a hard-coded list of milestones when the asset cannot be
/// loaded (e.g. test environment without asset bundle).
@RoutePage()
class ChangelogPage extends StatelessWidget {
  const ChangelogPage({super.key});

  /// 顶部"更新历程"卡内容 —— 唯一事实来源在 [ReleaseManifest.journeySteps]
  /// （Plan 2 §4.8：changelog 后备列表不再手写第二份编号）。
  static const List<JourneyStep> journeySteps = ReleaseManifest.journeySteps;

  /// 硬编码后援：asset 加载失败时使用。
  /// 唯一事实来源在 [ReleaseManifest.fallbackReleases]，与发布检查共用。
  static const List<ChangelogRelease> fallbackReleases =
      ReleaseManifest.fallbackReleases;

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

  /// 复制文本到剪贴板并弹出确认提示；正文「一键复制」按钮与独立页
  /// 共用。复制的内容始终是当前实际展示的版本（asset 原文优先，加载
  /// 失败时为内置后援拼接）。
  static Future<void> copyTextToClipboard(
    BuildContext context,
    String text,
  ) async {
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
      ),
      body: const ChangelogFromAsset(showFallbackBanner: true),
    );
  }
}

/// 顶部"更新历程"概览卡:把 0.x → 0.7 的关键阶段压缩成 7 步,
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
            'Varnamala Plus 从原型到 0.8 的 8 个阶段',
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
/// 测试。两种入口的「一键复制」按钮都在 [_ReleaseList] 正文里,复制的
/// 始终是当前实际展示的内容。
class ChangelogFromAsset extends StatelessWidget {
  /// 加载的资源路径,默认 `assets/changelog.md`。
  final String assetPath;

  /// 加载失败时使用的硬编码 release 列表。
  final List<ChangelogRelease> fallbackReleases;

  /// 是否在 fallback 路径上方显示一行提示。
  final bool showFallbackBanner;

  const ChangelogFromAsset({
    super.key,
    this.assetPath = kDefaultChangelogAssetPath,
    this.fallbackReleases = ChangelogPage.fallbackReleases,
    this.showFallbackBanner = false,
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
          );
        }
        final releases = parseChangelogMarkdown(snapshot.data!);
        if (releases.isEmpty) {
          return _ReleaseList(
            releases: fallbackReleases,
            banner: showFallbackBanner ? AppStrings.changeloadFallback : null,
            sourceText: null,
          );
        }
        return _ReleaseList(
          releases: releases,
          banner: null,
          sourceText: snapshot.data,
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

  const _ReleaseList({
    required this.releases,
    required this.banner,
    required this.sourceText,
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
        const SizedBox(height: 20),
        SizedBox(
          width: double.infinity,
          child: FilledButton.tonalIcon(
            onPressed: () => ChangelogPage.copyTextToClipboard(
              context,
              sourceText ??
                  ChangelogPage.buildClipboardText(releases: releases),
            ),
            icon: const Icon(Icons.content_copy_rounded, size: 18),
            label: Text(AppStrings.changelogCopyButton),
          ),
        ),
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
