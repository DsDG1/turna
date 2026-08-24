// Dart imports:
import 'dart:async';

// Flutter imports:
import 'package:flutter/material.dart';

// Package imports:
import 'package:auto_route/auto_route.dart';
import 'package:provider/provider.dart';

// Project imports:
import 'package:turna/application/ai/engine/ai_engine_config_holder.dart';
import 'package:turna/application/anki/formal_review_launcher.dart';
import 'package:turna/application/anki_official/engine/official_anki_home_due.dart';
import 'package:turna/application/anki_official/engine/official_anki_home_due_sync.dart';
import 'package:turna/application/anki_official/official_anki_feature_flags.dart';
import 'package:turna/application/course_provider.dart';
import 'package:turna/application/grammar_review_provider.dart';
import 'package:turna/application/mistake_provider.dart';
import 'package:turna/application/playground/language_playground_eligibility.dart';
import 'package:turna/application/srs_provider.dart';
import 'package:turna/application/weak_word_quiz_assembler.dart';
import 'package:turna/routing/routing.gr.dart';
import 'package:turna/l10n/app_strings.dart';
import 'package:turna/views/play/components/play_tiles.dart';
import 'package:turna/views/theme.dart';

class PlayHubScreen extends StatefulWidget {
  const PlayHubScreen({super.key});

  @override
  State<PlayHubScreen> createState() => _PlayHubScreenState();
}

class _PlayHubScreenState extends State<PlayHubScreen> {
  /// Official due refresh TTL (Plan 3 §23.2): the Play tab now mounts lazily
  /// (first visit), and a re-mount within this window does not re-refresh.
  static const _dueRefreshTtl = Duration(minutes: 5);
  static DateTime? _lastDueRefreshAt;

  @override
  void initState() {
    super.initState();
    final last = _lastDueRefreshAt;
    final fresh = last != null &&
        DateTime.now().difference(last) < _dueRefreshTtl;
    if (!fresh) {
      _lastDueRefreshAt = DateTime.now();
      unawaited(_refreshOfficialDue());
    }
  }

  Future<void> _refreshOfficialDue() async {
    await const OfficialAnkiHomeDueSync().refresh();
    if (mounted) setState(() {});
  }

  void _openAnkiReview(BuildContext context) {
    unawaited(
      const FormalReviewLauncher().open(
        context,
        entry: FormalReviewEntryKind.playHub,
        courseId: 'anki',
        officialOwner: OfficialAnkiHomeDue.officialImportIds.isNotEmpty,
        schedulerRuntimeAvailable:
            OfficialAnkiFeatureFlags.current.allowsOfficialScheduler,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final mistakes = context.select((MistakeProvider p) => p.entries);
    final mistakesCount = mistakes.length;
    final weakCount = WeakWordQuizAssembler.aggregateWeakWords(mistakes).length;
    final srsDue = context.select((SrsProvider p) => p.dueCount);
    final grammarDue = context.select((GrammarReviewProvider p) => p.dueCount);
    final ankiDueWords = context.select((SrsProvider p) => p.getDueAnkiWords());
    // Playground 只属于语言课程：Anki/Official Anki scope 下 Hero 连同其
    // 专属间距一起消失（三层隔离的第一层；页面与数据层仍各自防御）。
    final playgroundEligible = context.select((CourseProvider p) =>
        LanguagePlaygroundEligibility.isEligibleScope(p.courseScope));
    OfficialAnkiHomeDue.turnaDue = srsDue;
    final ankiDue = OfficialAnkiHomeDue.aggregatedAnkiDue(ankiDueWords);

    return RepaintBoundary(
      child: CustomScrollView(
        physics: const BouncingScrollPhysics(),
        slivers: [
          const SliverToBoxAdapter(child: SizedBox(height: 16)),

          // ── 顶部 Hero：Playground（仅语言课程）────────────────
          if (playgroundEligible)
            SliverToBoxAdapter(
              child: Padding(
                // Hero 与下方分区之间的专属间距包进同一块，随 Hero 一起
                // 消失，Anki 课程下不留下空白。
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
                child: PlaygroundHero(
                  title: AppStrings.playgroundTitle,
                  subtitle: AppStrings.playgroundHeroSubtitle,
                  onTap: () =>
                      context.router.push(const LanguagePlaygroundRoute()),
                ),
              ),
            ),

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
                        accentColor: TurnaTheme.errorLight,
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
                        accentColor: TurnaTheme.success,
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
                padding: EdgeInsets.zero,
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
                    // Single Play Hub secondary warm soft-tint (ADR 0033);
                    // slightly stronger alpha so clay is readable at a glance.
                    accentColor: TurnaTheme.anatolianClay,
                    tintAlpha: 0.16,
                    badge: weakCount > 0 ? '$weakCount' : null,
                    onTap: () => context.router.push(const WeakWordsRoute()),
                  ),
                  ReviewTile(
                    title: AppStrings.playGrammarReviewTitle,
                    icon: Icons.menu_book_rounded,
                    accentColor: TurnaTheme.brandTeal,
                    badge: grammarDue > 0 ? '$grammarDue' : null,
                    onTap: () =>
                        context.router.push(const GrammarReviewRoute()),
                  ),
                  ReviewTile(
                    title: AppStrings.playAnkiReviewTitle,
                    icon: Icons.style_rounded,
                    accentColor: TurnaTheme.brandSky,
                    badge: OfficialAnkiHomeDue.officialDueUnavailable
                        ? '—'
                        : (ankiDue > 0 ? '$ankiDue' : null),
                    onTap: () => _openAnkiReview(context),
                  ),
                  ReviewTile(
                    title: AppStrings.playReviewTitle,
                    icon: Icons.repeat_rounded,
                    accentColor: TurnaTheme.success,
                    badge: srsDue > 0 ? '$srsDue' : null,
                    onTap: () => context.router.push(const SrsReviewRoute()),
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
                child: ReviewTile(
                  title: AppStrings.playAiAssistantTitle,
                  icon: Icons.auto_awesome_rounded,
                  accentColor: TurnaTheme.amethystLeague,
                  onTap: () => context.router.push(const AiHubRoute()),
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
                accentColor: TurnaTheme.brandTeal,
                onTap: () => context.router.push(const ReviewProgressRoute()),
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
                accentColor: TurnaTheme.brandSky,
                onTap: () => context.router.push(const DictionaryRoute()),
              ),
            ),
          ),
          SliverToBoxAdapter(
            child: SizedBox(
              height: 16 + MediaQuery.paddingOf(context).bottom,
            ),
          ),
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
    final statusColor = complete ? TurnaTheme.success : TurnaTheme.warning;
    final actionColor = TurnaTheme.accentOnCard(context, TurnaTheme.brandTeal);

    return SoftCard(
      accentColor: TurnaTheme.brandTeal,
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        child: Row(
          children: [
            Icon(
              complete ? Icons.check_circle_rounded : Icons.tune_rounded,
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
                          ? TurnaTheme.textPrimaryColor(context)
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
