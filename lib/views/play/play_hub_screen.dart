// Dart imports:
import 'dart:async';

// Flutter imports:
import 'package:flutter/material.dart';

// Package imports:
import 'package:auto_route/auto_route.dart';
import 'package:provider/provider.dart';

// Project imports:
import 'package:turna/application/ai/engine/ai_engine_config_holder.dart';
import 'package:turna/application/anki_official/review/formal_review_launcher.dart';
import 'package:turna/application/anki_official/engine/official_formal_due_repository.dart';
import 'package:turna/application/anki_official/engine/official_anki_home_due_sync.dart';
import 'package:turna/application/anki_official/official_anki_feature_flags.dart';
import 'package:turna/application/course_provider.dart';
import 'package:turna/application/grammar_review_provider.dart';
import 'package:turna/application/mistake_provider.dart';
import 'package:turna/application/play/play_review_eligibility.dart';
import 'package:turna/application/srs_provider.dart';
import 'package:turna/application/study_stats_provider.dart';
import 'package:turna/application/weak_word_quiz_assembler.dart';
import 'package:turna/routing/routing.gr.dart';
import 'package:turna/l10n/app_strings.dart';
import 'package:turna/views/play/components/info_popup.dart';
import 'package:turna/views/play/components/play_info_panels.dart';
import 'package:turna/views/play/components/play_tiles.dart';
import 'package:turna/views/theme.dart';

/// 练习页主页（2026-08 焕新版）。
///
/// 信息架构（自上而下）：
/// 1. 今日复习主 CTA——大数字总待复习 + 四队列速览 chips，短按智能进入
///    最高优先级队列，长按看全队列浮窗
/// 2. 复习队列 2×2（错题 / 单词 / 语法 / Anki）——每格长按弹出数据浮窗
/// 3. AI 助手行（引擎状态点）——长按看引擎配置浮窗
/// 4. 练习工具三列（薄弱单词 / 词典 / 复习进度）——薄弱单词与复习进度
///    支持长按浮窗，词典无（「部分按钮生效」）
///
/// 交互契约：短按一律直接进入页面；长按仅在有数据可看的入口上生效，
/// 浮窗实现见 `info_popup.dart`。
class PlayHubScreen extends StatefulWidget {
  const PlayHubScreen({super.key});

  /// Test seam: exposes the state's TTL reset (the TTL is process-wide).
  @visibleForTesting
  static void resetDueRefreshTtlForTest() =>
      _PlayHubScreenState.resetDueRefreshTtlForTest();

  @override
  State<PlayHubScreen> createState() => _PlayHubScreenState();
}

class _PlayHubScreenState extends State<PlayHubScreen> {
  /// Official due refresh TTL (Plan 3 §23.2): the Play tab now mounts lazily
  /// (first visit), and a re-mount within this window does not re-refresh.
  static const _dueRefreshTtl = Duration(minutes: 5);
  static DateTime? _lastDueRefreshAt;

  /// Test seam: clears the process-wide TTL so widget tests observe the
  /// initState refresh deterministically.
  @visibleForTesting
  static void resetDueRefreshTtlForTest() => _lastDueRefreshAt = null;

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

  Future<void> _openAnkiReview(BuildContext context) async {
    final repo = OfficialFormalDueRepository.instance;
    await const FormalReviewLauncher().open(
      context,
      entry: FormalReviewEntryKind.playHub,
      courseId: 'anki',
      officialOwner: repo.officialImportIds.isNotEmpty,
      schedulerRuntimeAvailable:
          OfficialAnkiFeatureFlags.current.allowsOfficialScheduler,
    );
    // 复习会话只改调度器，仓库的 schedulerDue 要等下一次 refresh 才更新；
    // 返回 Play 页立即重取，Hero 数字才跟得上复习结果。
    await _refreshOfficialDue();
  }

  // ── 数据浮窗 ────────────────────────────────────────────────────

  /// 弹出锚定浮窗。`builder` 收到的 `enter` 回调会先关浮窗再执行导航，
  /// 供面板内「进入」按钮使用。
  void _showInfoPopup({
    required BuildContext anchor,
    required String semanticsLabel,
    required VoidCallback onEnter,
    required Widget Function(VoidCallback enter) builder,
  }) {
    late final PlayInfoPopup popup;
    popup = PlayInfoPopup.show(
      anchorContext: anchor,
      semanticsLabel: semanticsLabel,
      builder: (_) => builder(() {
        popup.close();
        onEnter();
      }),
    );
  }

  PlayQueueSnapshot _gatherSnapshot(BuildContext context) {
    final mistakes = context.select((MistakeProvider p) => p.entries);
    final recentMistakes = List.of(mistakes)
      ..sort((a, b) => b.timestamp.compareTo(a.timestamp));

    final srsDue = context.select((SrsProvider p) => p.dueCount);
    final ankiDueWords = context.select((SrsProvider p) => p.getDueAnkiWords());

    final dueRepo = OfficialFormalDueRepository.instance;
    final ankiUnavailable = dueRepo.snapshot.unavailable;
    final ankiCourse = PlayReviewEligibility.isAnkiScope(
      context.select((CourseProvider p) => p.courseScope),
    );

    return PlayQueueSnapshot(
      mistakeCount: mistakes.length,
      mistakeGrammarCount:
          mistakes.where((e) => e.grammarPointId != null).length,
      mistakeRewriteCount:
          mistakes.where((e) => e.rewriteCount == 0).length,
      recentMistakes: recentMistakes.take(3).toList(),
      srsDue: srsDue,
      srsExpressionDue:
          context.select((SrsProvider p) => p.expressionDueCount),
      srsSeen: context.select((SrsProvider p) => p.totalSeen),
      srsRegistered: context.select((SrsProvider p) => p.totalRegistered),
      srsLapse: context.select(
          (SrsProvider p) => p.getLapseWords().length + p.getLapseExpressions().length),
      grammarDue: context.select((GrammarReviewProvider p) => p.dueCount),
      grammarSeen: context.select((GrammarReviewProvider p) => p.totalSeen),
      grammarRegistered:
          context.select((GrammarReviewProvider p) => p.totalRegistered),
      legacyAnkiDue: ankiDueWords.length,
      officialAnkiDue:
          ankiUnavailable ? null : dueRepo.snapshot.introducedOfficialDue,
      ankiUnavailable: ankiUnavailable,
      weakWords: WeakWordQuizAssembler.aggregateWeakWords(mistakes),
      ankiCourse: ankiCourse,
    );
  }

  // ── 智能路由（Hero 短按） ───────────────────────────────────────

  /// 语言课：错题 → 单词 → 语法；Anki 课：只进 Anki 复习。
  void _startToday(BuildContext context, PlayQueueSnapshot snapshot) {
    if (snapshot.ankiCourse) {
      _openAnkiReview(context);
      return;
    }
    if (snapshot.mistakeCount > 0) {
      context.router.push(const MistakeReviewRoute());
    } else if (snapshot.srsDue > 0) {
      context.router.push(const SrsReviewRoute());
    } else if (snapshot.grammarDue > 0) {
      context.router.push(const GrammarReviewRoute());
    } else {
      context.router.push(const SrsReviewRoute());
    }
  }

  String _heroSubtitle(PlayQueueSnapshot snapshot) {
    if (snapshot.ankiCourse) {
      if (snapshot.ankiUnavailable) {
        return AppStrings.ankiDueUnavailable;
      }
      if (snapshot.ankiDueCount > 0) {
        return AppStrings.playTodayHeroNext(AppStrings.playAnkiReviewTitle);
      }
      return AppStrings.playTodayHeroAllClear;
    }
    if (snapshot.mistakeCount > 0) {
      return AppStrings.playTodayHeroNext(
          '${AppStrings.playMistakeReviewTitle} · ${snapshot.mistakeCount}');
    }
    if (snapshot.srsDue > 0) {
      return AppStrings.playTodayHeroNext(
          '${AppStrings.playReviewTitle} · ${snapshot.srsDue}');
    }
    if (snapshot.grammarDue > 0) {
      return AppStrings.playTodayHeroNext(
          '${AppStrings.playGrammarReviewTitle} · ${snapshot.grammarDue}');
    }
    return AppStrings.playTodayHeroAllClear;
  }

  @override
  Widget build(BuildContext context) {
    // Official due 快照仓库是 ChangeNotifier 单例：commit / mutation 只发通知。
    // 本页挂在 IndexedStack 里整个进程只 mount 一次，不订阅的话 Hero 大数字
    // 永远冻结在 initState 那次刷新读到的值上（启动竞态失败时一直是 0）。
    return ListenableBuilder(
      listenable: OfficialFormalDueRepository.instance,
      builder: (context, _) => _buildHub(context),
    );
  }

  Widget _buildHub(BuildContext context) {
    final snapshot = _gatherSnapshot(context);
    final totalDue = snapshot.totalDue;
    final ankiChipCount = snapshot.ankiUnavailable
        ? null
        : snapshot.ankiDueCount;
    final engineReady =
        context.select((AiEngineConfigHolder h) => h.config.isComplete);
    final ankiCourse = snapshot.ankiCourse;

    return RepaintBoundary(
      child: CustomScrollView(
        physics: const BouncingScrollPhysics(),
        slivers: [
          const SliverToBoxAdapter(child: SizedBox(height: 16)),

          // ── 今日复习主 CTA ────────────────────────────────────
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 0),
              child: Builder(
                builder: (heroContext) => TodayHeroCard(
                  subtitle: _heroSubtitle(snapshot),
                  totalDue: totalDue,
                  chips: [
                    if (!ankiCourse) ...[
                      QueueChipData(
                        label: AppStrings.playQueueChipMistake,
                        color: TurnaTheme.errorLight,
                        count: snapshot.mistakeCount,
                      ),
                      QueueChipData(
                        label: AppStrings.playQueueChipWords,
                        color: TurnaTheme.success,
                        count: snapshot.srsDue,
                      ),
                      QueueChipData(
                        label: AppStrings.playQueueChipGrammar,
                        color: TurnaTheme.warmSand,
                        count: snapshot.grammarDue,
                      ),
                    ] else
                      QueueChipData(
                        label: AppStrings.playQueueChipAnki,
                        color: Colors.white,
                        count: ankiChipCount,
                      ),
                  ],
                  onTap: () => _startToday(context, snapshot),
                  onLongPress: () => _showTodayPopup(heroContext, snapshot),
                ),
              ),
            ),
          ),
          const SliverToBoxAdapter(child: SizedBox(height: 24)),

          // ── 复习队列（2×2，每格长按数据浮窗） ──────────────────
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: SectionTitle(title: AppStrings.playQueueSectionTitle),
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
                  if (!ankiCourse) ...[
                    Builder(
                      builder: (tileContext) => ReviewTile(
                        title: AppStrings.playMistakeReviewTitle,
                        icon: Icons.priority_high_rounded,
                        accentColor: TurnaTheme.errorLight,
                        badge: snapshot.mistakeCount > 0
                            ? '${snapshot.mistakeCount}'
                            : null,
                        onTap: () =>
                            context.router.push(const MistakeReviewRoute()),
                        onLongPress: () =>
                            _showMistakePopup(tileContext, snapshot),
                      ),
                    ),
                    Builder(
                      builder: (tileContext) => ReviewTile(
                        title: AppStrings.playReviewTitle,
                        icon: Icons.repeat_rounded,
                        accentColor: TurnaTheme.success,
                        badge:
                            snapshot.srsDue > 0 ? '${snapshot.srsDue}' : null,
                        onTap: () =>
                            context.router.push(const SrsReviewRoute()),
                        onLongPress: () =>
                            _showSrsPopup(tileContext, snapshot),
                      ),
                    ),
                    Builder(
                      builder: (tileContext) => ReviewTile(
                        title: AppStrings.playGrammarReviewTitle,
                        icon: Icons.menu_book_rounded,
                        accentColor: TurnaTheme.brandTeal,
                        badge: snapshot.grammarDue > 0
                            ? '${snapshot.grammarDue}'
                            : null,
                        onTap: () =>
                            context.router.push(const GrammarReviewRoute()),
                        onLongPress: () =>
                            _showGrammarPopup(tileContext, snapshot),
                      ),
                    ),
                  ] else
                    Builder(
                      builder: (tileContext) => ReviewTile(
                        title: AppStrings.playAnkiReviewTitle,
                        icon: Icons.style_rounded,
                        accentColor: TurnaTheme.brandSky,
                        badge: snapshot.ankiUnavailable
                            ? '—'
                            : (ankiChipCount! > 0 ? '$ankiChipCount' : null),
                        onTap: () => _openAnkiReview(context),
                        onLongPress: () =>
                            _showAnkiPopup(tileContext, snapshot),
                      ),
                    ),
                ],
              ),
            ),
          ),
          const SliverToBoxAdapter(child: SizedBox(height: 24)),

          // ── AI 助手（单行 + 引擎状态） ─────────────────────────
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: SectionTitle(title: AppStrings.playAiAssistantTitle),
            ),
          ),
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Builder(
                builder: (tileContext) => AiAssistantTile(
                  engineReady: engineReady,
                  onTap: () => context.router.push(const AiHubRoute()),
                  onLongPress: () => _showAiPopup(tileContext),
                ),
              ),
            ),
          ),
          const SliverToBoxAdapter(child: SizedBox(height: 24)),

          // ── 练习工具（三列紧凑格） ─────────────────────────────
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child:
                  SectionTitle(title: AppStrings.playPracticeToolsTitle),
            ),
          ),
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: SizedBox(
                height: 104,
                child: Row(
                  children: [
                    if (!ankiCourse) ...[
                      Expanded(
                        child: Builder(
                          builder: (tileContext) => CompactToolTile(
                            title: AppStrings.playWeakWordsTitle,
                            icon: Icons.fitness_center_rounded,
                            // Single Play Hub secondary warm soft-tint
                            // (ADR 0033); slightly stronger alpha so clay is
                            // readable at a glance.
                            accentColor: TurnaTheme.anatolianClay,
                            badge: snapshot.weakWords.isNotEmpty
                                ? '${snapshot.weakWords.length}'
                                : null,
                            onTap: () =>
                                context.router.push(const WeakWordsRoute()),
                            onLongPress: () =>
                                _showWeakWordsPopup(tileContext, snapshot),
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                    ],
                    Expanded(
                      child: CompactToolTile(
                        title: AppStrings.playDictionaryTitle,
                        icon: Icons.menu_book_outlined,
                        accentColor: TurnaTheme.brandSky,
                        onTap: () =>
                            context.router.push(const DictionaryRoute()),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Builder(
                        builder: (tileContext) => CompactToolTile(
                          title: AppStrings.playReviewProgressTitle,
                          icon: Icons.show_chart_rounded,
                          accentColor: TurnaTheme.brandTeal,
                          onTap: () => context.router
                              .push(const ReviewProgressRoute()),
                          onLongPress: () =>
                              _showReviewProgressPopup(tileContext),
                        ),
                      ),
                    ),
                  ],
                ),
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

  // ── 各入口浮窗装配 ─────────────────────────────────────────────
  // `anchor` 是被长按卡片的 BuildContext（Builder 提供），用于浮窗锚定；
  // 导航统一走 State 自己的 context。

  void _showTodayPopup(BuildContext anchor, PlayQueueSnapshot snapshot) {
    _showInfoPopup(
      anchor: anchor,
      semanticsLabel: AppStrings.playTodayHeroTitle,
      onEnter: () => _startToday(context, snapshot),
      builder: (enter) => TodayOverviewPanelBody(
        snapshot: snapshot,
        nextLabel: _heroSubtitle(snapshot),
        onEnter: enter,
      ),
    );
  }

  void _showMistakePopup(BuildContext anchor, PlayQueueSnapshot snapshot) {
    _showInfoPopup(
      anchor: anchor,
      semanticsLabel: AppStrings.playMistakeReviewTitle,
      onEnter: () => context.router.push(const MistakeReviewRoute()),
      builder: (enter) =>
          MistakePanelBody(snapshot: snapshot, onEnter: enter),
    );
  }

  void _showSrsPopup(BuildContext anchor, PlayQueueSnapshot snapshot) {
    _showInfoPopup(
      anchor: anchor,
      semanticsLabel: AppStrings.playReviewTitle,
      onEnter: () => context.router.push(const SrsReviewRoute()),
      builder: (enter) => SrsPanelBody(snapshot: snapshot, onEnter: enter),
    );
  }

  void _showGrammarPopup(BuildContext anchor, PlayQueueSnapshot snapshot) {
    _showInfoPopup(
      anchor: anchor,
      semanticsLabel: AppStrings.playGrammarReviewTitle,
      onEnter: () => context.router.push(const GrammarReviewRoute()),
      builder: (enter) =>
          GrammarPanelBody(snapshot: snapshot, onEnter: enter),
    );
  }

  void _showAnkiPopup(BuildContext anchor, PlayQueueSnapshot snapshot) {
    _showInfoPopup(
      anchor: anchor,
      semanticsLabel: AppStrings.playAnkiReviewTitle,
      onEnter: () => _openAnkiReview(context),
      builder: (enter) => AnkiPanelBody(snapshot: snapshot, onEnter: enter),
    );
  }

  void _showWeakWordsPopup(BuildContext anchor, PlayQueueSnapshot snapshot) {
    _showInfoPopup(
      anchor: anchor,
      semanticsLabel: AppStrings.playWeakWordsTitle,
      onEnter: () => context.router.push(const WeakWordsRoute()),
      builder: (enter) =>
          WeakWordsPanelBody(snapshot: snapshot, onEnter: enter),
    );
  }

  void _showReviewProgressPopup(BuildContext anchor) {
    _showInfoPopup(
      anchor: anchor,
      semanticsLabel: AppStrings.playReviewProgressTitle,
      onEnter: () => context.router.push(const ReviewProgressRoute()),
      builder: (enter) => ReviewProgressPanelBody(
        stats: context.read<StudyStatsProvider>(),
        onEnter: enter,
      ),
    );
  }

  void _showAiPopup(BuildContext anchor) {
    _showInfoPopup(
      anchor: anchor,
      semanticsLabel: AppStrings.playAiAssistantTitle,
      onEnter: () => context.router.push(const AiHubRoute()),
      builder: (enter) => AiPanelBody(
        config: context.read<AiEngineConfigHolder>().config,
        onEnter: enter,
      ),
    );
  }
}
