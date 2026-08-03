// Flutter imports:
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

// Package imports:
import 'package:auto_route/auto_route.dart';

// Project imports:
import 'package:turna/di/injection.dart';
import 'package:turna/l10n/app_strings.dart';
import 'package:turna/routing/routing.gr.dart';
import 'package:turna/service/tab_router.dart';
import 'package:turna/views/theme.dart';

/// 新手指南 - introduces the app's core features with one-tap jump links
/// (功能卡) plus a written quick-start guide (markdown).
///
/// Reached from Settings > 关于 > 新手指南. Visual style mirrors the About
/// page: course-tree gradient background, soft white/dark cards with a 1px
/// border, peacock-teal icon tiles, and short-bar section headers.
///
/// Each feature card jumps to its feature:
///   - Tab destinations (学习 / 练习 / 我的) switch the bottom nav via
///     [TabRouter] and pop this page so the user lands on the tab.
///   - Pushed routes (词典 / AI / 错题 / 弱词 / SRS) open on top of this page
///     so the user can explore and return to the guide.
class BeginnerGuidePage extends StatelessWidget {
  const BeginnerGuidePage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: TurnaTheme.scaffoldBg(context),
      appBar: AppBar(
        title: Text(
          AppStrings.beginnerGuideTitle,
          style: Theme.of(context).textTheme.titleLarge?.copyWith(
                fontWeight: FontWeight.w700,
              ),
        ),
      ),
      body: Container(
        decoration: BoxDecoration(
          gradient: TurnaTheme.courseTreeGradientFor(context),
        ),
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const _IntroHero(),
              const SizedBox(height: 20),
              const QuickStartFromAsset(
                showTitle: false,
              ),
              const SizedBox(height: 20),
              _SectionHeader(text: AppStrings.beginnerGuideSectionLearn),
              const SizedBox(height: 10),
              _FeatureCard(
                icon: Icons.menu_book_rounded,
                title: AppStrings.beginnerGuideLearnTitle,
                description: AppStrings.beginnerGuideLearnDesc,
                onTap: () => _goToTab(context, TabDestination.learn),
              ),
              _FeatureCard(
                icon: Icons.language_rounded,
                title: AppStrings.beginnerGuideCourseMgmtTitle,
                description: AppStrings.beginnerGuideCourseMgmtDesc,
                onTap: () => context.router.push(const CourseManagementRoute()),
              ),
              const SizedBox(height: 20),
              _SectionHeader(text: AppStrings.beginnerGuideSectionPractice),
              const SizedBox(height: 10),
              _FeatureCard(
                icon: Icons.extension_rounded,
                title: AppStrings.beginnerGuidePlayTitle,
                description: AppStrings.beginnerGuidePlayDesc,
                onTap: () => _goToTab(context, TabDestination.play),
              ),
              _FeatureCard(
                icon: Icons.repeat_rounded,
                title: AppStrings.beginnerGuideSrsTitle,
                description: AppStrings.beginnerGuideSrsDesc,
                onTap: () => context.router.push(const SrsReviewRoute()),
              ),
              _FeatureCard(
                icon: Icons.error_outline_rounded,
                title: AppStrings.beginnerGuideMistakesTitle,
                description: AppStrings.beginnerGuideMistakesDesc,
                onTap: () => context.router.push(const MistakeListRoute()),
              ),
              _FeatureCard(
                icon: Icons.trending_down_rounded,
                title: AppStrings.beginnerGuideWeakWordsTitle,
                description: AppStrings.beginnerGuideWeakWordsDesc,
                onTap: () => context.router.push(const WeakWordsRoute()),
              ),
              const SizedBox(height: 20),
              _SectionHeader(text: AppStrings.beginnerGuideSectionTools),
              const SizedBox(height: 10),
              _FeatureCard(
                icon: Icons.search_rounded,
                title: AppStrings.beginnerGuideDictionaryTitle,
                description: AppStrings.beginnerGuideDictionaryDesc,
                onTap: () => context.router.push(const DictionaryRoute()),
              ),
              _FeatureCard(
                icon: Icons.auto_awesome_rounded,
                title: AppStrings.beginnerGuideAiTitle,
                description: AppStrings.beginnerGuideAiDesc,
                onTap: () => context.router.push(const AiHubRoute()),
              ),
              const SizedBox(height: 20),
              _SectionHeader(text: AppStrings.beginnerGuideSectionProfile),
              const SizedBox(height: 10),
              _FeatureCard(
                icon: Icons.insights_rounded,
                title: AppStrings.beginnerGuideStatsTitle,
                description: AppStrings.beginnerGuideStatsDesc,
                onTap: () => _goToTab(context, TabDestination.profile),
              ),
              const SizedBox(height: 28),
            ],
          ),
        ),
      ),
    );
  }

  /// Switch the bottom nav to [tab] and pop this guide so the user lands on
  /// the destination tab (tabs can't overlay this page, so it must close).
  void _goToTab(BuildContext context, int tab) {
    getIt<TabRouter>().switchTo(tab);
    Navigator.of(context).pop();
  }
}

/// 读取 `assets/quick_start.md` 并按 `## ` 切分章节,渲染为简单卡片列表。
///
/// 用作 About 页"使用指南"Tab 的内容来源,以及 [BeginnerGuidePage] 顶部
/// 的文字详情。
class QuickStartFromAsset extends StatelessWidget {
  final String assetPath;

  /// 是否在顶部显示一个"使用指南"小标题(仅在独立展示时使用)。
  final bool showTitle;

  const QuickStartFromAsset({
    super.key,
    this.assetPath = 'assets/quick_start.md',
    this.showTitle = true,
  });

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<String>(
      future: rootBundle.loadString(assetPath),
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return Padding(
            padding: const EdgeInsets.all(16),
            child: Center(
              child: SizedBox(
                width: 24,
                height: 24,
                child: CircularProgressIndicator(
                  strokeWidth: 2.5,
                  color: TurnaTheme.peacockTeal,
                ),
              ),
            ),
          );
        }
        if (snapshot.hasError || !snapshot.hasData) {
          return Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: TurnaTheme.cardBg(context),
              borderRadius: BorderRadius.circular(TurnaTheme.radiusLarge),
              border: Border.all(color: TurnaTheme.statCardBorder(context)),
            ),
            child: Text(
              AppStrings.quickStartLoadFallback,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: TurnaTheme.textSecondaryColor(context),
                  ),
            ),
          );
        }
        final sections = parseQuickStartMarkdown(snapshot.data!);
        if (sections.isEmpty) {
          return Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: TurnaTheme.cardBg(context),
              borderRadius: BorderRadius.circular(TurnaTheme.radiusLarge),
              border: Border.all(color: TurnaTheme.statCardBorder(context)),
            ),
            child: Text(
              AppStrings.quickStartLoadFallback,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: TurnaTheme.textSecondaryColor(context),
                  ),
            ),
          );
        }
        return Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (showTitle) ...[
              _SectionHeader(text: AppStrings.aboutTabQuickStart),
              const SizedBox(height: 10),
            ],
            for (var i = 0; i < sections.length; i++) ...[
              _QuickStartSection(section: sections[i]),
              if (i < sections.length - 1) const SizedBox(height: 12),
            ],
          ],
        );
      },
    );
  }
}

/// 单节 quick start 内容。
class QuickStartSection {
  final String number;
  final String title;
  final List<String> paragraphs;

  const QuickStartSection({
    required this.number,
    required this.title,
    required this.paragraphs,
  });
}

/// 把 `assets/quick_start.md` 文本解析为 [QuickStartSection] 列表。
///
/// 解析规则:
/// - `#` / `##` 跳过(标题与分隔符)。
/// - `## N. TITLE` 视为新节;`N` 为编号,`TITLE` 为标题。
/// - 空行 / `---` 跳过。
/// - 段落:连续非空行组成一段,段内若有 `- ` 前缀则改为 bullet 列表。
/// - `>` 引用块:前缀剥离,作为段落。
List<QuickStartSection> parseQuickStartMarkdown(String markdown) {
  final sections = <QuickStartSection>[];
  String? currentNumber;
  String? currentTitle;
  final paragraphs = <String>[];
  final currentLines = <String>[];

  void flush() {
    if (currentNumber != null) {
      if (currentLines.isNotEmpty) {
        paragraphs.add(currentLines.join('\n'));
        currentLines.clear();
      }
      sections.add(
        QuickStartSection(
          number: currentNumber!,
          title: currentTitle ?? '',
          paragraphs: List.unmodifiable(paragraphs),
        ),
      );
    }
    currentNumber = null;
    currentTitle = null;
    paragraphs.clear();
  }

  for (final rawLine in markdown.split('\n')) {
    final line = rawLine.trimRight();
    if (line.isEmpty) {
      if (currentLines.isNotEmpty) {
        paragraphs.add(currentLines.join('\n'));
        currentLines.clear();
      }
      continue;
    }
    if (line.startsWith('---')) continue;
    if (line.startsWith('# ')) continue;
    if (line.startsWith('## ')) {
      flush();
      final header = line.substring(3).trim();
      final spaceIdx = header.indexOf(' ');
      if (spaceIdx >= 0) {
        currentNumber = header.substring(0, spaceIdx).trim();
        currentTitle = header.substring(spaceIdx + 1).trim();
      } else {
        currentNumber = header;
        currentTitle = '';
      }
      continue;
    }
    if (currentNumber == null) continue;
    final cleaned = line.startsWith('> ') ? line.substring(2) : line;
    currentLines.add(cleaned);
  }
  flush();
  return sections;
}

class _QuickStartSection extends StatelessWidget {
  final QuickStartSection section;

  const _QuickStartSection({required this.section});

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
                width: 32,
                height: 32,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: TurnaTheme.peacockTeal.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(TurnaTheme.radiusMedium),
                ),
                child: Text(
                  section.number,
                  style: const TextStyle(
                    fontWeight: FontWeight.w700,
                    color: TurnaTheme.peacockTeal,
                    fontSize: 13,
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  section.title,
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.w700,
                        color: TurnaTheme.textPrimaryColor(context),
                      ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          for (final p in section.paragraphs)
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Text(
                p,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      height: 1.5,
                      color: TurnaTheme.textSecondaryColor(context),
                    ),
              ),
            ),
        ],
      ),
    );
  }
}

/// Peacock-gradient hero with a welcome icon, the page title, and a short
/// intro explaining the "tap a card to jump" affordance.
class _IntroHero extends StatelessWidget {
  const _IntroHero();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        gradient: TurnaTheme.peacockGradient,
        borderRadius: BorderRadius.circular(TurnaTheme.radiusLarge),
        boxShadow: TurnaTheme.softShadow,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.18),
                  borderRadius: BorderRadius.circular(TurnaTheme.radiusMedium),
                ),
                child: const Icon(
                  Icons.waving_hand_rounded,
                  color: Colors.white,
                  size: 24,
                ),
              ),
              const SizedBox(width: 12),
              Text(
                AppStrings.beginnerGuideTitle,
                style: Theme.of(context).textTheme.titleLarge?.copyWith(
                      color: Colors.white,
                      fontWeight: FontWeight.w700,
                    ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Text(
            AppStrings.beginnerGuideIntro,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: Colors.white.withValues(alpha: 0.92),
                  height: 1.5,
                ),
          ),
        ],
      ),
    );
  }
}

/// Short bar + title, matching the About page's `_SectionHeader` rhythm.
class _SectionHeader extends StatelessWidget {
  final String text;

  const _SectionHeader({required this.text});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(left: 4),
      child: Row(
        children: [
          Container(
            width: 3,
            height: 18,
            decoration: BoxDecoration(
              color: TurnaTheme.peacockTeal.withValues(alpha: 0.5),
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(width: 10),
          Text(
            text,
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w700,
                  fontSize: 15,
                  color: TurnaTheme.textSecondaryColor(context),
                ),
          ),
        ],
      ),
    );
  }
}

/// A tappable feature row: tinted icon tile, title + description, and a
/// "去体验 ›" pill that signals the jump affordance.
class _FeatureCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final String description;
  final VoidCallback onTap;

  const _FeatureCard({
    required this.icon,
    required this.title,
    required this.description,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: TurnaTheme.cardBg(context),
          borderRadius: BorderRadius.circular(TurnaTheme.radiusLarge),
          border: Border.all(color: TurnaTheme.statCardBorder(context)),
          boxShadow: TurnaTheme.softShadow,
        ),
        child: Material(
          color: Colors.transparent,
          borderRadius: BorderRadius.circular(TurnaTheme.radiusLarge),
          child: InkWell(
            borderRadius: BorderRadius.circular(TurnaTheme.radiusLarge),
            onTap: onTap,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              child: Row(
                children: [
                  Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                      color: TurnaTheme.peacockTeal.withValues(alpha: 0.1),
                      borderRadius:
                          BorderRadius.circular(TurnaTheme.radiusMedium),
                    ),
                    child: Icon(
                      icon,
                      color: TurnaTheme.peacockTeal,
                      size: 22,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          title,
                          style:
                              Theme.of(context).textTheme.bodyLarge?.copyWith(
                                    fontWeight: FontWeight.w700,
                                  ),
                        ),
                        const SizedBox(height: 2),
                        Text(
                          description,
                          maxLines: 3,
                          overflow: TextOverflow.ellipsis,
                          style:
                              Theme.of(context).textTheme.bodySmall?.copyWith(
                                    color: TurnaTheme.textHintColor(context),
                                    height: 1.4,
                                  ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    decoration: BoxDecoration(
                      color: TurnaTheme.peacockTeal.withValues(alpha: 0.1),
                      borderRadius:
                          BorderRadius.circular(TurnaTheme.radiusRound),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          AppStrings.beginnerGuideTryNow,
                          style:
                              Theme.of(context).textTheme.labelSmall?.copyWith(
                                    color: TurnaTheme.peacockTeal,
                                    fontWeight: FontWeight.w700,
                                  ),
                        ),
                        const SizedBox(width: 2),
                        const Icon(
                          Icons.arrow_forward_rounded,
                          size: 14,
                          color: TurnaTheme.peacockTeal,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
