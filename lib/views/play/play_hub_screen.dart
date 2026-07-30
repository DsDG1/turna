// Flutter imports:
import 'package:flutter/material.dart';

// Package imports:
import 'package:auto_route/auto_route.dart';
import 'package:provider/provider.dart';

// Project imports:
import 'package:varnamala/application/ai/engine/ai_engine_config_holder.dart';
import 'package:varnamala/application/anki/anki_review_assembler.dart';
import 'package:varnamala/application/grammar_review_provider.dart';
import 'package:varnamala/application/mistake_provider.dart';
import 'package:varnamala/application/srs_provider.dart';
import 'package:varnamala/application/weak_word_quiz_assembler.dart';
import 'package:varnamala/routing/routing.gr.dart';
import 'package:varnamala/l10n/app_strings.dart';
import 'package:varnamala/views/play/components/play_tiles.dart';
import 'package:varnamala/views/theme.dart';

class PlayHubScreen extends StatefulWidget {
  const PlayHubScreen({super.key});

  @override
  State<PlayHubScreen> createState() => _PlayHubScreenState();
}

class _PlayHubScreenState extends State<PlayHubScreen> {
  @override
  Widget build(BuildContext context) {
    final mistakes = context.select((MistakeProvider p) => p.entries);
    final mistakesCount = mistakes.length;
    final weakCount =
        WeakWordQuizAssembler.aggregateWeakWords(mistakes).length;
    final srsDue = context.select((SrsProvider p) => p.dueCount);
    final grammarDue = context.select((GrammarReviewProvider p) => p.dueCount);
    final ankiDue = context.select(
      (SrsProvider p) => p
          .getDueWords()
          .where((w) => w.wordId.startsWith(AnkiReviewAssembler.ankiPrefix))
          .length,
    );

    return RepaintBoundary(
      child: CustomScrollView(
        physics: const BouncingScrollPhysics(),
        slivers: [
          const SliverToBoxAdapter(child: SizedBox(height: 16)),

          // ── 顶部 Hero：快速练习 ────────────────────────────────
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: QuickPlayHero(
                title: AppStrings.playQuickPlayTitle,
                subtitle: AppStrings.playQuickPlaySubtitle,
                onTap: () => context.router.push(const MatchWordsRoute()),
              ),
            ),
          ),
          const SliverToBoxAdapter(child: SizedBox(height: 24)),

          // ── 今日重点（2 列等宽，不再用 PageView 横向滑动） ────
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: SectionTitle(title: AppStrings.playTodayFocusTitle),
            ),
          ),
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: SizedBox(
                height: 190,
                child: Row(
                  children: [
                    Expanded(
                      child: FocusTile(
                        title: AppStrings.playMistakeReviewTitle,
                        countText: mistakesCount > 0
                            ? AppStrings.playMistakeFocusCount(mistakesCount)
                            : AppStrings.playMistakeFocusEmpty,
                        icon: Icons.priority_high_rounded,
                        accentColor: VarnamalaTheme.errorLight,
                        badge: mistakesCount > 0 ? '$mistakesCount' : null,
                        onTap: () =>
                            context.router.push(const MistakeReviewRoute()),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: FocusTile(
                        title: AppStrings.playReviewTitle,
                        countText: srsDue > 0
                            ? AppStrings.playReviewFocusCount(srsDue)
                            : AppStrings.playReviewFocusEmpty,
                        icon: Icons.repeat_rounded,
                        accentColor: VarnamalaTheme.success,
                        badge: srsDue > 0 ? '$srsDue' : null,
                        onTap: () =>
                            context.router.push(const SrsReviewRoute()),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          const SliverToBoxAdapter(child: SizedBox(height: 24)),

          // ── 复习中心（2x2 网格） ──────────────────────────────
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: SectionTitle(title: AppStrings.playReviewCenterTitle),
            ),
          ),
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: GridView.count(
                crossAxisCount: 2,
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                mainAxisSpacing: 12,
                crossAxisSpacing: 12,
                childAspectRatio: 1.6,
                children: [
                  ReviewTile(
                    title: AppStrings.playWeakWordsTitle,
                    icon: Icons.fitness_center_rounded,
                    accentColor: VarnamalaTheme.warning,
                    badge: weakCount > 0 ? '$weakCount' : null,
                    onTap: () =>
                        context.router.push(const WeakWordsRoute()),
                  ),
                  ReviewTile(
                    title: AppStrings.playGrammarReviewTitle,
                    icon: Icons.menu_book_rounded,
                    accentColor: VarnamalaTheme.peacockTeal,
                    badge: grammarDue > 0 ? '$grammarDue' : null,
                    onTap: () =>
                        context.router.push(const GrammarReviewRoute()),
                  ),
                  ReviewTile(
                    title: AppStrings.playAnkiReviewTitle,
                    icon: Icons.style_rounded,
                    accentColor: VarnamalaTheme.peacockCyan,
                    badge: ankiDue > 0 ? '$ankiDue' : null,
                    onTap: () =>
                        context.router.push(const AnkiReviewRoute()),
                  ),
                  ReviewTile(
                    title: AppStrings.playReviewTitle,
                    icon: Icons.repeat_rounded,
                    accentColor: VarnamalaTheme.success,
                    badge: srsDue > 0 ? '$srsDue' : null,
                    onTap: () =>
                        context.router.push(const SrsReviewRoute()),
                  ),
                ],
              ),
            ),
          ),
          const SliverToBoxAdapter(child: SizedBox(height: 24)),

          // ── AI 助手（快捷入口 + 引擎状态 → 全部 AI 功能） ─────
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: SectionTitle(title: AppStrings.playAiAssistantTitle),
            ),
          ),
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: SizedBox(
                height: 100,
                child: Row(
                  children: [
                    Expanded(
                      child: ReviewTile(
                        title: AppStrings.aiHubStartWish,
                        icon: Icons.auto_awesome_rounded,
                        accentColor: VarnamalaTheme.amethystLeague,
                        onTap: () =>
                            context.router.push(const AiWishChatRoute()),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: ReviewTile(
                        title: AppStrings.aiHubStartTextbook,
                        icon: Icons.menu_book_rounded,
                        accentColor: VarnamalaTheme.peacockCyan,
                        onTap: () => context.router.push(
                          const TextbookImportRoute(),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          const SliverToBoxAdapter(child: SizedBox(height: 12)),
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: _AiStatusBar(
                onTap: () => context.router.push(const AiHubRoute()),
              ),
            ),
          ),
          const SliverToBoxAdapter(child: SizedBox(height: 24)),

          // ── 工具 ──────────────────────────────────────────────
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: SectionTitle(title: AppStrings.playToolsTitle),
            ),
          ),
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: ToolsTile(
                title: AppStrings.playReviewProgressTitle,
                subtitle: AppStrings.playReviewProgressSubtitle,
                icon: Icons.show_chart_rounded,
                accentColor: VarnamalaTheme.peacockTeal,
                onTap: () =>
                    context.router.push(const ReviewProgressRoute()),
              ),
            ),
          ),
          const SliverToBoxAdapter(child: SizedBox(height: 12)),
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: ToolsTile(
                title: AppStrings.playDictionaryTitle,
                subtitle: AppStrings.playDictionarySubtitle,
                icon: Icons.menu_book_outlined,
                accentColor: VarnamalaTheme.peacockCyan,
                onTap: () =>
                    context.router.push(const DictionaryRoute()),
              ),
            ),
          ),
          const SliverToBoxAdapter(child: SizedBox(height: 32)),
        ],
      ),
    );
  }
}

// ────────────────────────────────────────────────────────────────────
// Play-hub-local widgets
// ────────────────────────────────────────────────────────────────────

/// AI 助手分区底部的引擎状态行：左侧引擎就绪/未配置指示，右侧「全部 AI
/// 功能 ›」。整卡点击进入重新设计的 AI 页（配置入口在 AI 页 Hero 内）。
class _AiStatusBar extends StatelessWidget {
  final VoidCallback onTap;

  const _AiStatusBar({required this.onTap});

  @override
  Widget build(BuildContext context) {
    final complete = context.select(
      (AiEngineConfigHolder h) => h.config.isComplete,
    );
    final statusColor =
        complete ? VarnamalaTheme.success : VarnamalaTheme.warning;
    final actionColor =
        VarnamalaTheme.accentOnCard(context, VarnamalaTheme.peacockTeal);

    return SoftCard(
      accentColor: VarnamalaTheme.peacockTeal,
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        child: Row(
          children: [
            Icon(
              complete
                  ? Icons.check_circle_rounded
                  : Icons.tune_rounded,
              color: statusColor,
              size: 22,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                complete
                    ? AppStrings.playAiEngineReady
                    : AppStrings.playAiEngineNotConfigured,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      fontWeight: FontWeight.w700,
                      color: complete
                          ? VarnamalaTheme.textPrimaryColor(context)
                          : statusColor,
                    ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            Text(
              AppStrings.playAiViewAll,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.w700,
                    color: actionColor,
                  ),
            ),
            const SizedBox(width: 4),
            Icon(
              Icons.arrow_forward_ios_rounded,
              color: actionColor,
              size: 14,
            ),
          ],
        ),
      ),
    );
  }
}
