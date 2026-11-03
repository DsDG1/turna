// Dart imports:
import 'dart:async';

// Flutter imports:
import 'package:flutter/material.dart';

// Package imports:
import 'package:auto_route/auto_route.dart';
import 'package:provider/provider.dart';

// Project imports:
import 'package:turna/application/ai/engine/ai_engine_config_holder.dart';
import 'package:turna/application/ai/practice/ai_practice_job_queue.dart';
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
import 'package:turna/views/widgets/directory_rows.dart';
import 'package:turna/views/widgets/session_shell.dart';
import 'package:turna/views/widgets/turna_cards.dart';
import 'package:turna/core/ohos_target.dart';
import 'package:turna/core/spacing.dart';
import 'package:turna/core/text_styles.dart';
import 'package:turna/core/theme.dart';

/// 练习页主页（「湿地雾光」R07 · 今日任务台版式）。
///
/// 信息架构（P1「今日任务台」模式，自上而下）：
/// 1. 页内页头：「练习」pageTitle + 日期 captionSm（PlayAppBar 退化为透明
///    占位，标题在正文里）
/// 2. 今日复习玻璃对象（全页唯一玻璃）：「今日复习」小标签 + 特大数字
///    （46）+ 单位 + 预计分钟，下方全宽「开始复习」主行动；长按弹全队列
///    浮窗。短按智能进入最高优先级队列
/// 3. 有顺序的队列行（DirectoryTaskRow，顺序即优先级：错题重练 clay 置顶
///    emphasized、单词 SRS teal、语法 sky、智能练习 reed；Anki 课为独立的
///    Anki 队列行）——行长按弹数据浮窗
/// 4. 文字工具索引（每日挑战 / 薄弱单词 / 词典 / 复习进度）：teal 文字链
///    + 间隔点，不再四张卡；薄弱单词与复习进度长按浮窗挂在文字链上
///
/// 非语言课程（Anki 牌组）没有内置词表可查：队列只留 Anki 复习 + 智能练习
/// ，工具索引只留复习进度（ADR 0066：记忆卡域独立，不并入语言队列逻辑）。
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

  /// 每次切回练习页重取一次，否则大数字/Anki 队列计数永远停在
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
    // 返回 Play 页立即重取（force：防抖不能吞掉这一次），大数字才跟得上。
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

  // ── 智能路由（玻璃对象短按） ─────────────────────────────────────

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

  @override
  Widget build(BuildContext context) {
    // Official due 快照仓库是 ChangeNotifier 单例：commit / mutation 只发通知。
    // 本页挂在 IndexedStack 里整个进程只 mount 一次，不订阅的话大数字
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
    ({bool active, int ready}) practiceStatus = (active: false, ready: 0);
    try {
      practiceStatus =
          context.select<AiPracticeJobQueue, ({bool active, int ready})>(
        (q) => (active: q.hasActiveJob, ready: q.readyCount),
      );
    } catch (_) {
      // Optional dependency: widget tests pump the hub without the queue.
    }
    final ankiCourse = snapshot.ankiCourse;
    final now = DateTime.now();

    return RepaintBoundary(
      child: CustomScrollView(
        physics: const BouncingScrollPhysics(),
        slivers: [
          // ── 页内页头（「练习」pageTitle + 日期 captionSm） ──────────
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.pageMargin,
                AppSpacing.lg,
                AppSpacing.pageMargin,
                0,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(AppStrings.playTitle,
                      style: AppTextStyles.pageTitle(context)),
                  const SizedBox(height: AppSpacing.xs),
                  Text(
                    AppStrings.playHeaderDate(now.month, now.day),
                    style: AppTextStyles.captionSm(context),
                  ),
                ],
              ),
            ),
          ),
          const SliverToBoxAdapter(child: SizedBox(height: AppSpacing.lg)),

          // ── 今日复习玻璃对象（全页唯一玻璃） ────────────────────────
          SliverToBoxAdapter(
            child: Padding(
              padding: AppSpacing.pageGutterMist,
              child: Builder(
                builder: (heroContext) => _TodayGlassPanel(
                  totalDue: totalDue,
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
                padding: const EdgeInsets.fromLTRB(
                  AppSpacing.pageMargin,
                  AppSpacing.md,
                  AppSpacing.pageMargin,
                  0,
                ),
                child: _AnkiDueRetryBar(
                  onRetry: () => unawaited(_refreshOfficialDue(force: true)),
                ),
              ),
            ),
          const SliverToBoxAdapter(child: SizedBox(height: AppSpacing.xxl)),

          // ── 复习队列（顺序即优先级，长按数据浮窗） ──────────────────
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.pageMargin,
                0,
                AppSpacing.pageMargin,
                AppSpacing.sm,
              ),
              child: Text(
                AppStrings.playQueueSectionTitle,
                style: AppTextStyles.sectionTitle(context),
              ),
            ),
          ),
          SliverToBoxAdapter(
            child: Padding(
              padding: AppSpacing.pageGutterMist,
              child: Column(
                children: [
                  if (!ankiCourse) ...[
                    Builder(
                      builder: (rowContext) => _PopupAnchor(
                        semanticsLabel: AppStrings.playMistakeReviewTitle,
                        onLongPress: () =>
                            _showMistakePopup(rowContext, snapshot),
                        child: DirectoryTaskRow(
                          icon: Icons.priority_high_rounded,
                          accent: TurnaTheme.anatolianClay,
                          title: AppStrings.playMistakeReviewTitle,
                          countLabel: snapshot.mistakeCount > 0
                              ? '${snapshot.mistakeCount}'
                              : null,
                          emphasized: true,
                          onTap: () =>
                              context.router.push(const MistakeReviewRoute()),
                        ),
                      ),
                    ),
                    Builder(
                      builder: (rowContext) => _PopupAnchor(
                        semanticsLabel: AppStrings.playReviewTitle,
                        onLongPress: () => _showSrsPopup(rowContext, snapshot),
                        child: DirectoryTaskRow(
                          icon: Icons.repeat_rounded,
                          accent: TurnaTheme.brandTeal,
                          title: AppStrings.playReviewTitle,
                          countLabel: snapshot.srsDue > 0
                              ? '${snapshot.srsDue}'
                              : null,
                          onTap: () =>
                              context.router.push(const SrsReviewRoute()),
                        ),
                      ),
                    ),
                    Builder(
                      builder: (rowContext) => _PopupAnchor(
                        semanticsLabel: AppStrings.playGrammarReviewTitle,
                        onLongPress: () =>
                            _showGrammarPopup(rowContext, snapshot),
                        child: DirectoryTaskRow(
                          icon: Icons.menu_book_rounded,
                          accent: TurnaTheme.brandSky,
                          title: AppStrings.playGrammarReviewTitle,
                          countLabel: snapshot.grammarDue > 0
                              ? '${snapshot.grammarDue}'
                              : null,
                          onTap: () =>
                              context.router.push(const GrammarReviewRoute()),
                        ),
                      ),
                    ),
                  ] else
                    Builder(
                      builder: (rowContext) => _PopupAnchor(
                        semanticsLabel: AppStrings.playAnkiReviewTitle,
                        onLongPress: () =>
                            _showAnkiPopup(rowContext, snapshot),
                        child: DirectoryTaskRow(
                          icon: Icons.style_rounded,
                          accent: TurnaTheme.brandSky,
                          title: AppStrings.playAnkiReviewTitle,
                          countLabel: snapshot.ankiUnavailable
                              ? '—'
                              : (ankiChipCount != null && ankiChipCount > 0
                                  ? '$ankiChipCount'
                                  : null),
                          onTap: () => _openAnkiReview(context),
                        ),
                      ),
                    ),
                  // 智能练习：按错题/弱词生成定制练习（AI 伴学的入排位置）。
                  // 两种课程都保留——Anki 课同样能按错题生成；但鸿蒙伴生版
                  // 不随包 AI 模块（华为审核合规，ADR 0056），整行不渲染。
                  if (!isDegraded(OhosDegradation.aiGeneration))
                    Builder(
                      builder: (rowContext) => _PopupAnchor(
                        semanticsLabel: AppStrings.playSmartPracticeTitle,
                        onLongPress: () => _showAiPopup(rowContext),
                        child: DirectoryTaskRow(
                          icon: Icons.auto_awesome_rounded,
                          // teal 已归 SRS 队列（P2 任务行色规），智能练习
                          // 按湿地色轴取芦苇青，与错题 clay、语法 sky 分开。
                          accent: TurnaTheme.brandReed,
                          title: AppStrings.playSmartPracticeTitle,
                          countLabel: engineReady
                              ? (practiceStatus.active
                                  ? '…'
                                  : practiceStatus.ready > 0
                                      ? '${practiceStatus.ready}'
                                      : null)
                              : AppStrings.playAiEngineNotConfigured,
                          onTap: () => context.router.push(const AiHubRoute()),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
          const SliverToBoxAdapter(child: SizedBox(height: AppSpacing.xl)),

          // ── 工具索引（teal 文字链 + 间隔点，长按浮窗挂在文字链上） ──
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.pageMargin,
                0,
                AppSpacing.pageMargin,
                AppSpacing.sm,
              ),
              child: Text(
                AppStrings.playPracticeToolsTitle,
                style: AppTextStyles.sectionTitle(context),
              ),
            ),
          ),
          SliverToBoxAdapter(
            child: Padding(
              padding: AppSpacing.pageGutterMist,
              child: Wrap(
                spacing: AppSpacing.sm,
                runSpacing: AppSpacing.xs,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  if (!ankiCourse) ...[
                    // 每日挑战原是孤儿路由（功能在、入口丢），在此恢复
                    // 练习台入口；Anki 牌组课不出现（题目取自已学课时）。
                    _ToolIndexLink(
                      label: AppStrings.playDailyTitle,
                      onTap: () =>
                          context.router.push(const DailyChallengeRoute()),
                    ),
                    const _ToolIndexDot(),
                    Builder(
                      builder: (linkContext) => _ToolIndexLink(
                        label: AppStrings.playWeakWordsTitle,
                        onTap: () =>
                            context.router.push(const WeakWordsRoute()),
                        onLongPress: () =>
                            _showWeakWordsPopup(linkContext, snapshot),
                      ),
                    ),
                    const _ToolIndexDot(),
                    _ToolIndexLink(
                      label: AppStrings.playDictionaryTitle,
                      onTap: () =>
                          context.router.push(const DictionaryRoute()),
                    ),
                    const _ToolIndexDot(),
                  ],
                  Builder(
                    builder: (linkContext) => _ToolIndexLink(
                      label: AppStrings.playReviewProgressTitle,
                      onTap: () =>
                          context.router.push(const ReviewProgressRoute()),
                      onLongPress: () =>
                          _showReviewProgressPopup(linkContext),
                    ),
                  ),
                  // ADR 0066 §3：记忆卡域独立入口——语言课程用户也能直达
                  // 记忆卡中枢（牌组管理 / 导入 / 修复都在那边）。
                  const _ToolIndexDot(),
                  _ToolIndexLink(
                    label: AppStrings.memoryCardHubTitle,
                    onTap: () =>
                        context.router.push(const MemoryCardHubRoute()),
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
  // `anchor` 是被长按元素的 BuildContext（Builder 提供），用于浮窗锚定；
  // 导航统一走 State 自己的 context。

  void _showTodayPopup(BuildContext anchor, PlayQueueSnapshot snapshot) {
    _showInfoPopup(
      anchor: anchor,
      semanticsLabel: AppStrings.reviewTodayTitle,
      onEnter: () => _startToday(context, snapshot),
      builder: (enter) => TodayOverviewPanelBody(
        snapshot: snapshot,
        nextLabel: _heroSubtitle(snapshot),
        onEnter: enter,
      ),
    );
  }

  /// 长按浮窗里「下一个」行的文案（短按智能路由的镜像）。
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

/// 今日复习玻璃对象：「今日复习」小标签 + 特大数字（46）+ 单位 + 预计分钟，
/// 下方全宽「开始复习」主行动。
///
/// 它是本页**唯一**的玻璃对象（P1 用量规则）；长按弹全队列浮窗。
class _TodayGlassPanel extends StatelessWidget {
  const _TodayGlassPanel({
    required this.totalDue,
    required this.onTap,
    this.onLongPress,
  });

  final int totalDue;
  final VoidCallback onTap;
  final GestureLongPressCallback? onLongPress;

  /// 每张卡的估计用时（秒）——纯展示层换算，不落任何仓储。
  static const _secondsPerItem = 10;

  @override
  Widget build(BuildContext context) {
    final estimateMinutes =
        totalDue > 0 ? (totalDue * _secondsPerItem / 60).ceil() : 0;

    return Semantics(
      container: true,
      onLongPress: onLongPress,
      hint: onLongPress == null ? null : AppStrings.playLongPressHint,
      child: GestureDetector(
        onLongPress: onLongPress,
        behavior: HitTestBehavior.deferToChild,
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.all(AppSpacing.pageMargin),
          decoration: TurnaTheme.glassDecoration(
            context,
            TurnaTheme.glassFocus,
            borderRadius: BorderRadius.circular(TurnaTheme.radiusXLarge),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                AppStrings.reviewTodayTitle,
                style: AppTextStyles.caption(context),
              ),
              const SizedBox(height: AppSpacing.sm),
              Row(
                crossAxisAlignment: CrossAxisAlignment.baseline,
                textBaseline: TextBaseline.alphabetic,
                children: [
                  Text(
                    '$totalDue',
                    key: const Key('play-today-hero-number'),
                    style: AppTextStyles.metricHero(
                      context,
                      color: TurnaTheme.brandTealDark,
                    ).copyWith(
                      fontSize: 46,
                      fontFeatures: const [FontFeature.tabularFigures()],
                    ),
                  ),
                  const SizedBox(width: AppSpacing.xs + 2),
                  Text(
                    AppStrings.playTodayHeroTotalLabel,
                    style: AppTextStyles.captionSm(context)
                        .copyWith(fontWeight: FontWeight.w600),
                  ),
                ],
              ),
              if (estimateMinutes > 0) ...[
                const SizedBox(height: AppSpacing.xs),
                Text(
                  AppStrings.playTodayEstimateMinutes(estimateMinutes),
                  style: AppTextStyles.captionSm(context),
                ),
              ],
              const SizedBox(height: AppSpacing.xl),
              SessionPrimaryAction(
                label: AppStrings.playTodayStartReview,
                onPressed: onTap,
                trailingIcon: Icons.play_arrow_rounded,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// 长按浮窗锚：包在队列行 / 文字链外，把长按手势与语义名转给浮窗。
///
/// 点击仍由内部的 InkWell 处理（长按与单击是不同手势，不竞争）。
class _PopupAnchor extends StatelessWidget {
  const _PopupAnchor({
    required this.semanticsLabel,
    required this.onLongPress,
    required this.child,
  });

  final String semanticsLabel;
  final GestureLongPressCallback? onLongPress;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    if (onLongPress == null) return child;
    return Semantics(
      onLongPress: onLongPress,
      hint: AppStrings.playLongPressHint,
      child: GestureDetector(
        onLongPress: onLongPress,
        behavior: HitTestBehavior.deferToChild,
        child: child,
      ),
    );
  }
}

/// 工具索引文字链：teal 文字，短按进页、长按弹数据浮窗（可选）。
class _ToolIndexLink extends StatelessWidget {
  const _ToolIndexLink({
    required this.label,
    required this.onTap,
    this.onLongPress,
  });

  final String label;
  final VoidCallback onTap;
  final GestureLongPressCallback? onLongPress;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      onLongPress: onLongPress,
      borderRadius: BorderRadius.circular(TurnaTheme.radiusSmall),
      child: Padding(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.xs + 2,
          vertical: AppSpacing.sm - 2,
        ),
        child: Text(
          label,
          style: AppTextStyles.captionSm(context).copyWith(
            fontSize: 14,
            fontWeight: FontWeight.w600,
            color: TurnaTheme.brandTeal,
          ),
        ),
      ),
    );
  }
}

/// 工具索引的间隔点。
class _ToolIndexDot extends StatelessWidget {
  const _ToolIndexDot();

  @override
  Widget build(BuildContext context) {
    return Text(
      '·',
      style: AppTextStyles.captionSm(context).copyWith(
        color: TurnaTheme.textHintColor(context),
      ),
    );
  }
}

/// Anki due 同步失败的重试条（仅 Anki 课显示）。
///
/// 数字冻结时用户没有别的自救手段：玻璃对象短按会直接进复习，长按浮窗只把
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
