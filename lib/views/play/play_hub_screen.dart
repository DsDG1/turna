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
import 'package:turna/di/injection.dart';
import 'package:turna/service/tab_router.dart';
import 'package:turna/views/play/components/info_popup.dart';
import 'package:turna/views/play/components/play_info_panels.dart';
import 'package:turna/views/play/components/play_tiles.dart';
import 'package:turna/views/widgets/adaptive_card_grid.dart';
import 'package:turna/core/theme.dart';

/// 练习页主页（2026-08 焕新版）。
///
/// 信息架构（自上而下）：
/// 1. 今日复习主 CTA——大数字总待复习 + 四队列速览 chips，短按智能进入
///    最高优先级队列，长按看全队列浮窗
/// 2. 复习队列 2×2（错题 / 单词 / 语法 / 智能练习；Anki 课为 Anki / 智能练习）
///    ——每格长按弹出数据浮窗
/// 3. 练习工具三列（薄弱单词 / 词典 / 复习进度）——薄弱单词与复习进度
///    支持长按浮窗，词典无（「部分按钮生效」）
///
/// 2026-10-20：原先「AI 助手」是队列下方一条独立横幅，与练习主线并列，
/// 读起来像另一个专区。改为队列里的「智能练习」一格：AI 只是练习的来源之一，
/// 入口落在练习入口所在的位置。
///
/// 非语言课程（Anki 牌组）没有内置词表可查：复习队列只留 Anki 复习，
/// 练习工具只留复习进度，单词/词典入口整体隐藏。
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

class _PlayHubScreenState extends State<PlayHubScreen>
    with WidgetsBindingObserver {
  /// 防抖窗口：只压「切 tab 回到本页」「app 从后台恢复」这类高频事件。
  /// 挂载与复习返回走 force，永远不被它挡住。
  static const _dueRefreshDebounce = Duration(seconds: 3);
  static DateTime? _lastDueRefreshAt;

  /// Test seam: clears the process-wide debounce timestamp so widget tests
  /// observe the initState refresh deterministically.
  @visibleForTesting
  static void resetDueRefreshTtlForTest() => _lastDueRefreshAt = null;

  /// 本页在 [TabStack] 里永久挂载（未选中只是 Offstage），`initState` 全进程
  /// 只跑一次 —— 所以「回到本页」必须由 tab 通知触发，不能指望重新挂载。
  TabRouter? _tabRouter;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    // 测试里不装 DI：可选依赖守卫，缺失时退化为「只在挂载时刷新」。
    if (getIt.isRegistered<TabRouter>()) {
      _tabRouter = getIt<TabRouter>()..index.addListener(_onTabChanged);
    }
    unawaited(_refreshOfficialDue(force: true));
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _tabRouter?.index.removeListener(_onTabChanged);
    super.dispose();
  }

  /// 每次切回练习页重取一次，否则 Hero 大数字/Anki 队列计数永远停在
  /// 首次挂载时读到的值（复习结果只写调度器，快照要有人刷新）。
  void _onTabChanged() {
    if (_tabRouter?.index.value != TabDestination.play) return;
    unawaited(_refreshOfficialDue());
  }

  /// 从后台回到前台：调度器可能已被系统时间/别的入口改过。
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      unawaited(_refreshOfficialDue());
    }
  }

  Future<void> _refreshOfficialDue({bool force = false}) async {
    final last = _lastDueRefreshAt;
    if (!force &&
        last != null &&
        DateTime.now().difference(last) < _dueRefreshDebounce) {
      return;
    }
    _lastDueRefreshAt = DateTime.now();
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
    // 返回 Play 页立即重取（force：防抖不能吞掉这一次），Hero 数字才跟得上。
    await _refreshOfficialDue(force: true);
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
      mistakeRewriteCount: mistakes.where((e) => e.rewriteCount == 0).length,
      recentMistakes: recentMistakes.take(3).toList(),
      srsDue: srsDue,
      srsExpressionDue: context.select((SrsProvider p) => p.expressionDueCount),
      srsSeen: context.select((SrsProvider p) => p.totalSeen),
      srsRegistered: context.select((SrsProvider p) => p.totalRegistered),
      srsLapse: context.select((SrsProvider p) =>
          p.getLapseWords().length + p.getLapseExpressions().length),
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
    final ankiChipCount =
        snapshot.ankiUnavailable ? null : snapshot.ankiDueCount;
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
          // 同步失败时数字是冻结的旧值（或按 0 显示），而本页原先没有任何
          // 重试入口 —— Anki hub 有，练习页没有，用户只能靠重启碰运气。
          if (ankiCourse && snapshot.ankiUnavailable)
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 12, 20, 0),
                child: _AnkiDueRetryBar(
                  onRetry: () => unawaited(_refreshOfficialDue(force: true)),
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
              // 固定 1.6 宽高比在系统字体放大后挤掉标题行
              // （真机收据 `BOTTOM OVERFLOWED BY 11 PIXELS`）。改行高自适应，
              // 1.6 作为常规字号下的高度基线。
              child: AdaptiveCardGrid(
                columns: 2,
                spacing: 12,
                minChildAspectRatio: 1.6,
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
                        onLongPress: () => _showSrsPopup(tileContext, snapshot),
                      ),
                    ),
                    Builder(
                      builder: (tileContext) => ReviewTile(
                        title: AppStrings.playGrammarReviewTitle,
                        icon: Icons.menu_book_rounded,
                        // 语法原先用 brandTeal；「智能练习」按 AI 语义占用 teal，
                        // 同格两卡同色会被读成同一个入口，语法改用 sky（冷色档，
                        // Anki 卡只在 Anki 课程出现，不会与之同屏）。
                        accentColor: TurnaTheme.brandSky,
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
                  // 智能练习：按错题/弱词生成定制练习（AI 伴学的入排位置）。
                  // 两平台一致、两种课程都保留——Anki 课同样能按错题生成。
                  Builder(
                    builder: (tileContext) => ReviewTile(
                      title: AppStrings.playSmartPracticeTitle,
                      icon: Icons.auto_awesome_rounded,
                      accentColor: TurnaTheme.brandTeal,
                      badge: engineReady
                          ? null
                          : AppStrings.playAiEngineNotConfigured,
                      badgeColor: TurnaTheme.warning,
                      onTap: () => context.router.push(const AiHubRoute()),
                      onLongPress: () => _showAiPopup(tileContext),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SliverToBoxAdapter(child: SizedBox(height: 24)),

          // ── 练习工具（语言课三列；Anki 课只留复习进度） ──────────
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: SectionTitle(title: AppStrings.playPracticeToolsTitle),
            ),
          ),
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              // 原来是 `SizedBox(height: 104)` + Row：字体放大后标题行会被
              // 104 掐住。改行高自适应网格，104 作为常规字号下的高度基线。
              child: AdaptiveCardGrid(
                columns: ankiCourse ? 1 : 3,
                spacing: 12,
                minChildHeight: 104,
                children: [
                  if (!ankiCourse) ...[
                    Builder(
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
                    CompactToolTile(
                      title: AppStrings.playDictionaryTitle,
                      icon: Icons.menu_book_outlined,
                      accentColor: TurnaTheme.brandSky,
                      onTap: () => context.router.push(const DictionaryRoute()),
                    ),
                  ],
                  Builder(
                    builder: (tileContext) => CompactToolTile(
                      title: AppStrings.playReviewProgressTitle,
                      icon: Icons.show_chart_rounded,
                      accentColor: TurnaTheme.brandTeal,
                      onTap: () =>
                          context.router.push(const ReviewProgressRoute()),
                      onLongPress: () => _showReviewProgressPopup(tileContext),
                    ),
                  ),
                ],
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
      builder: (enter) => MistakePanelBody(snapshot: snapshot, onEnter: enter),
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
      builder: (enter) => GrammarPanelBody(snapshot: snapshot, onEnter: enter),
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
      semanticsLabel: AppStrings.playSmartPracticeTitle,
      onEnter: () => context.router.push(const AiHubRoute()),
      builder: (enter) => AiPanelBody(
        config: context.read<AiEngineConfigHolder>().config,
        onEnter: enter,
      ),
    );
  }
}

/// Anki due 同步失败的重试条（仅 Anki 课显示）。
///
/// 数字冻结时用户没有别的自救手段：Hero 短按会直接进复习，长按浮窗只把
/// Anki 行显示成「—」。这里对齐 Anki hub 的 `_AnkiDueUnavailableBanner`，
/// 但用练习页自己的卡片语言。
class _AnkiDueRetryBar extends StatelessWidget {
  const _AnkiDueRetryBar({required this.onRetry});

  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return SoftCard(
      key: const Key('play-anki-due-unavailable'),
      accentColor: TurnaTheme.warning,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 10, 8, 10),
        child: Row(
          children: [
            AccentIconChip(
              icon: Icons.sync_problem_rounded,
              color: TurnaTheme.warning,
              size: 20,
              padding: 7,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                AppStrings.ankiDueUnavailable,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
              ),
            ),
            TextButton(
              onPressed: onRetry,
              child: Text(AppStrings.ankiReviewRetry),
            ),
          ],
        ),
      ),
    );
  }
}
