// Flutter imports:
import 'package:flutter/material.dart';

// Package imports:
import 'package:auto_route/auto_route.dart';

// Project imports:
import 'package:varnamala/di/injection.dart';
import 'package:varnamala/l10n/app_strings.dart';
import 'package:varnamala/routing/routing.gr.dart';
import 'package:varnamala/service/tab_router.dart';
import 'package:varnamala/views/theme.dart';

/// 新手指南 - introduces the app's core features with one-tap jump links.
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
      backgroundColor: VarnamalaTheme.scaffoldBg(context),
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
          gradient: VarnamalaTheme.courseTreeGradientFor(context),
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
        gradient: VarnamalaTheme.peacockGradient,
        borderRadius: BorderRadius.circular(VarnamalaTheme.radiusLarge),
        boxShadow: VarnamalaTheme.softShadow,
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
                  borderRadius:
                      BorderRadius.circular(VarnamalaTheme.radiusMedium),
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
              color: VarnamalaTheme.peacockTeal.withValues(alpha: 0.5),
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(width: 10),
          Text(
            text,
            style: Theme.of(context).textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.w700,
                  fontSize: 15,
                  color: VarnamalaTheme.textSecondaryColor(context),
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
          color: VarnamalaTheme.cardBg(context),
          borderRadius: BorderRadius.circular(VarnamalaTheme.radiusLarge),
          border: Border.all(color: VarnamalaTheme.statCardBorder(context)),
          boxShadow: VarnamalaTheme.softShadow,
        ),
        child: Material(
          color: Colors.transparent,
          borderRadius: BorderRadius.circular(VarnamalaTheme.radiusLarge),
          child: InkWell(
            borderRadius: BorderRadius.circular(VarnamalaTheme.radiusLarge),
            onTap: onTap,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              child: Row(
                children: [
                  Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                      color: VarnamalaTheme.peacockTeal.withValues(alpha: 0.1),
                      borderRadius:
                          BorderRadius.circular(VarnamalaTheme.radiusMedium),
                    ),
                    child: Icon(
                      icon,
                      color: VarnamalaTheme.peacockTeal,
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
                          style: Theme.of(context)
                              .textTheme
                              .bodySmall
                              ?.copyWith(
                                color: VarnamalaTheme.textHintColor(context),
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
                      color: VarnamalaTheme.peacockTeal.withValues(alpha: 0.1),
                      borderRadius:
                          BorderRadius.circular(VarnamalaTheme.radiusRound),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          AppStrings.beginnerGuideTryNow,
                          style:
                              Theme.of(context).textTheme.labelSmall?.copyWith(
                                    color: VarnamalaTheme.peacockTeal,
                                    fontWeight: FontWeight.w700,
                                  ),
                        ),
                        const SizedBox(width: 2),
                        const Icon(
                          Icons.arrow_forward_rounded,
                          size: 14,
                          color: VarnamalaTheme.peacockTeal,
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
