// Flutter imports:
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

// Package imports:
import 'package:auto_route/auto_route.dart';

// Project imports:
import 'package:turna/application/guide_return_controller.dart';
import 'package:turna/di/injection.dart';
import 'package:turna/l10n/app_strings.dart';
import 'package:turna/routing/routing.gr.dart';
import 'package:turna/service/tab_router.dart';
import 'package:turna/views/theme.dart';

/// 新手指南 — compact feature list with one-tap 「去体验」 jumps.
///
/// Reached from Settings > 关于 > 新手指南. Long-form help lives on About's
/// 「使用指南」 tab ([QuickStartFromAsset]); this page is intentionally short.
///
/// Each feature card jumps to its feature and arms a root-level return bubble
/// ([GuideReturnController]) so the user can come back or dismiss the hint:
///   - Tab destinations (学习 / 练习 / 我的) switch the bottom nav via
///     [TabRouter] and pop this page so the user lands on the tab.
///   - Pushed routes (词典 / AI / 错题 / 弱词 / SRS) open on top of this page
///     so the user can explore and return to the guide.
class BeginnerGuidePage extends StatefulWidget {
  const BeginnerGuidePage({super.key});

  @override
  State<BeginnerGuidePage> createState() => _BeginnerGuidePageState();
}

class _BeginnerGuidePageState extends State<BeginnerGuidePage> {
  @override
  void initState() {
    super.initState();
    // Already on the guide — hide any leftover bubble from a prior session.
    getIt<GuideReturnController>().clear();
  }

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
              _SectionHeader(text: AppStrings.beginnerGuideSectionLearn),
              const SizedBox(height: 10),
              _FeatureCard(
                icon: Icons.menu_book_rounded,
                title: AppStrings.beginnerGuideLearnTitle,
                onTap: () => _goToTab(context, TabDestination.learn),
              ),
              _FeatureCard(
                icon: Icons.language_rounded,
                title: AppStrings.beginnerGuideCourseMgmtTitle,
                onTap: () => _pushExperience(
                  context,
                  () => context.router.push(const CourseManagementRoute()),
                ),
              ),
              const SizedBox(height: 20),
              _SectionHeader(text: AppStrings.beginnerGuideSectionPractice),
              const SizedBox(height: 10),
              _FeatureCard(
                icon: Icons.extension_rounded,
                title: AppStrings.beginnerGuidePlayTitle,
                onTap: () => _goToTab(context, TabDestination.play),
              ),
              _FeatureCard(
                icon: Icons.repeat_rounded,
                title: AppStrings.beginnerGuideSrsTitle,
                onTap: () => _pushExperience(
                  context,
                  () => context.router.push(const SrsReviewRoute()),
                ),
              ),
              _FeatureCard(
                icon: Icons.error_outline_rounded,
                title: AppStrings.beginnerGuideMistakesTitle,
                onTap: () => _pushExperience(
                  context,
                  () => context.router.push(const MistakeListRoute()),
                ),
              ),
              _FeatureCard(
                icon: Icons.trending_down_rounded,
                title: AppStrings.beginnerGuideWeakWordsTitle,
                onTap: () => _pushExperience(
                  context,
                  () => context.router.push(const WeakWordsRoute()),
                ),
              ),
              const SizedBox(height: 20),
              _SectionHeader(text: AppStrings.beginnerGuideSectionTools),
              const SizedBox(height: 10),
              _FeatureCard(
                icon: Icons.search_rounded,
                title: AppStrings.beginnerGuideDictionaryTitle,
                onTap: () => _pushExperience(
                  context,
                  () => context.router.push(const DictionaryRoute()),
                ),
              ),
              _FeatureCard(
                icon: Icons.auto_awesome_rounded,
                title: AppStrings.beginnerGuideAiTitle,
                onTap: () => _pushExperience(
                  context,
                  () => context.router.push(const AiHubRoute()),
                ),
              ),
              const SizedBox(height: 20),
              _SectionHeader(text: AppStrings.beginnerGuideSectionProfile),
              const SizedBox(height: 10),
              _FeatureCard(
                icon: Icons.insights_rounded,
                title: AppStrings.beginnerGuideStatsTitle,
                onTap: () => _goToTab(context, TabDestination.profile),
              ),
              const SizedBox(height: 28),
            ],
          ),
        ),
      ),
    );
  }

  /// Push a feature route while keeping the guide under the stack.
  void _pushExperience(BuildContext context, VoidCallback navigate) {
    getIt<GuideReturnController>().arm(guidePopped: false);
    navigate();
  }

  /// Switch the bottom nav to [tab] and pop this guide so the user lands on
  /// the destination tab (tabs can't overlay this page, so it must close).
  void _goToTab(BuildContext context, int tab) {
    getIt<GuideReturnController>().arm(guidePopped: true);
    getIt<TabRouter>().switchTo(tab);
    Navigator.of(context).pop();
  }
}

/// 读取 `assets/quick_start.md` 并按 `## ` 切分章节,渲染为简单卡片列表。
///
/// 用作 About 页"使用指南"Tab 的内容来源。
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
                  color: TurnaTheme.brandTeal,
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
                  color: TurnaTheme.brandTeal.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(TurnaTheme.radiusMedium),
                ),
                child: Text(
                  section.number,
                  style: const TextStyle(
                    fontWeight: FontWeight.w700,
                    color: TurnaTheme.brandTeal,
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

/// Compact hero: welcome icon + title + one-line affordance.
class _IntroHero extends StatelessWidget {
  const _IntroHero();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(
        gradient: TurnaTheme.brandGradient,
        borderRadius: BorderRadius.circular(TurnaTheme.radiusLarge),
        boxShadow: TurnaTheme.softShadow,
      ),
      child: Row(
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.18),
              borderRadius: BorderRadius.circular(TurnaTheme.radiusMedium),
            ),
            child: const Icon(
              Icons.waving_hand_rounded,
              color: Colors.white,
              size: 22,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  AppStrings.beginnerGuideTitle,
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        color: Colors.white,
                        fontWeight: FontWeight.w700,
                      ),
                ),
                const SizedBox(height: 2),
                Text(
                  AppStrings.beginnerGuideIntro,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: Colors.white.withValues(alpha: 0.92),
                        height: 1.35,
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
              color: TurnaTheme.brandTeal.withValues(alpha: 0.5),
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

/// A tappable feature row: tinted icon tile, title only, and a 「去体验 ›」 pill.
class _FeatureCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final VoidCallback onTap;

  const _FeatureCard({
    required this.icon,
    required this.title,
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
                      color: TurnaTheme.brandTeal.withValues(alpha: 0.1),
                      borderRadius:
                          BorderRadius.circular(TurnaTheme.radiusMedium),
                    ),
                    child: Icon(
                      icon,
                      color: TurnaTheme.brandTeal,
                      size: 22,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      title,
                      style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                            fontWeight: FontWeight.w700,
                          ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    decoration: BoxDecoration(
                      color: TurnaTheme.brandTeal.withValues(alpha: 0.1),
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
                                    color: TurnaTheme.brandTeal,
                                    fontWeight: FontWeight.w700,
                                  ),
                        ),
                        const SizedBox(width: 2),
                        const Icon(
                          Icons.arrow_forward_rounded,
                          size: 14,
                          color: TurnaTheme.brandTeal,
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
