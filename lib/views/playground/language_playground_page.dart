// Dart imports:
import 'dart:async';

// Flutter imports:
import 'package:flutter/material.dart';

// Package imports:
import 'package:auto_route/auto_route.dart';
import 'package:provider/provider.dart';

// Project imports:
import 'package:turna/application/accessibility_capabilities.dart';
import 'package:turna/application/course_provider.dart';
import 'package:turna/application/diagnostics/performance_trace.dart';
import 'package:turna/application/mistake_provider.dart';
import 'package:turna/application/ai/ai_tutor_chat_provider.dart';
import 'package:turna/application/playground/language_playground_eligibility.dart';
import 'package:turna/application/playground/playground_content_source.dart';
import 'package:turna/application/playground/playground_index.dart';
import 'package:turna/application/playground/playground_index_cache.dart';
import 'package:turna/application/playground/playground_models.dart';
import 'package:turna/l10n/app_strings.dart';
import 'package:turna/routing/routing.gr.dart';
import 'package:turna/views/play/components/play_tiles.dart';
import 'package:turna/views/theme.dart';

/// 语言课程 Playground 首页（计划 §4.2）。
///
/// 三层隔离的第二层：不依赖「用户看不到入口」。进入页面与课程切换后
/// 都会重新检查资格——Anki scope 下不启动任何题库加载，提示一次后返回；
/// 无可返回页面时（深链冷启动）就地展示拦截态。
@RoutePage()
class LanguagePlaygroundPage extends StatefulWidget {
  const LanguagePlaygroundPage({super.key});

  @override
  State<LanguagePlaygroundPage> createState() => _LanguagePlaygroundPageState();
}

class _LanguagePlaygroundPageState extends State<LanguagePlaygroundPage> {
  PlaygroundContentScope _selectedScope = PlaygroundContentScope.recent;

  /// 首版可用模式（P2 接会话执行；P4 翻译挑战不进首版网格）。
  static const List<PlaygroundMode> _gridModes = [
    PlaygroundMode.smartMix,
    PlaygroundMode.wordMatch,
    PlaygroundMode.quickChoice,
    PlaygroundMode.listenAndPick,
    PlaygroundMode.dictation,
    PlaygroundMode.sentenceOrder,
    PlaygroundMode.fillBlank,
    PlaygroundMode.dailyMix,
  ];

  /// 模式会话执行尚未接入（P2）。在此之前模式格必须以「即将推出」的
  /// 禁用态呈现，不能显示成可用后点击只弹 toast（Plan 3 §22.4）。
  static const bool _sessionExecutionEnabled = false;

  bool _availabilityLoading = false;
  Set<PlaygroundMode> _availableModes = const {};
  Map<PlaygroundMode, int> _modeCounts = const {};
  bool _blockedInline = false;
  bool _exitAttempted = false;
  int _availabilityEpoch = 0;

  /// Revision cache (Plan 3 §22.2): identical data reuses the cached index,
  /// so unrelated CourseProvider notifications never re-scan the candidates.
  PlaygroundSourceRevision? _indexRevision;

  /// Cached in initState — dispose must not look up ancestors of a
  /// deactivated widget via context.read.
  late final CourseProvider _courseProvider;

  /// Cached alongside [_courseProvider] for the same reason; feeds the weak
  /// content scope (计划 §7.2: 薄弱内容以错题快照为主要来源).
  late final MistakeProvider _mistakeProvider;

  @override
  void initState() {
    super.initState();
    _courseProvider = context.read<CourseProvider>();
    _mistakeProvider = context.read<MistakeProvider>();
    _courseProvider.addListener(_onCourseChanged);
    // Post-frame: 初始资格检查与 availability 加载都走 setState，首帧
    // 挂载期间直接调用会在 build 阶段触发 markNeedsBuild 断言。
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _onCourseChanged(initial: true);
    });
  }

  @override
  void dispose() {
    _courseProvider.removeListener(_onCourseChanged);
    super.dispose();
  }

  void _onCourseChanged({bool initial = false}) {
    final eligible = LanguagePlaygroundEligibility.isEligibleScope(
      _courseProvider.courseScope,
    );
    if (eligible) {
      if (_blockedInline) {
        // 深链拦截后课程切回语言 scope：解除就地拦截并恢复退出提示资格
        // （否则页面会永远停在拦截态，且不再尝试退出）。
        setState(() => _blockedInline = false);
        _exitAttempted = false;
      }
      // 加载进行中不再重触发：ensureSectionLoaded 的 loading/完成通知会
      // 回到这里，无守卫时每次通知都重跑 _loadAvailability，叠加失败态
      // （失败不缓存）会形成自激的无限重试风暴，页面永远停在加载中。
      if (initial || (!_availabilityLoading && _availableModes.isEmpty)) {
        unawaited(_loadAvailability());
      }
      return;
    }
    // 已在页面上时课程被切到 Anki：停止一切加载并退出。
    _availabilityEpoch++;
    unawaited(_exitWhenIneligible());
  }

  Future<void> _exitWhenIneligible() async {
    if (_exitAttempted) return;
    _exitAttempted = true;
    if (!mounted) return;
    ScaffoldMessenger.maybeOf(context)?.showSnackBar(
      SnackBar(content: Text(AppStrings.playgroundBlockedToast)),
    );
    final animation = ModalRoute.of(context)?.animation;
    if (animation != null && animation.status != AnimationStatus.completed) {
      // 入场转场进行中（深链/快速切换）：等它完成再返回，避免反转
      // 进行中的 push 动画。
      void listener(AnimationStatus status) {
        if (status == AnimationStatus.completed) {
          animation.removeStatusListener(listener);
          unawaited(_finishExit());
        }
      }

      animation.addStatusListener(listener);
      return;
    }
    await _finishExit();
  }

  Future<void> _finishExit() async {
    if (!mounted) return;
    final router = context.router;
    final popped = await router.maybePop();
    if (!popped && mounted) {
      // 无可返回页面（深链冷启动）：就地拦截，不加载任何题目。
      setState(() => _blockedInline = true);
    }
  }

  Future<void> _loadAvailability() async {
    final revision = PlaygroundSourceRevision.of(
      course: _courseProvider,
      mistakes: _mistakeProvider,
      scope: _selectedScope,
    );
    if (revision == _indexRevision && _availableModes.isNotEmpty) {
      return; // data unchanged since the last analysis
    }
    final cached = PlaygroundIndexCache.instance.get(revision);
    if (cached != null) {
      PerformanceTrace.instance.record(
        feature: 'playground',
        operation: 'index',
        duration: Duration.zero,
        resultSize: cached.candidateCount,
        cacheStatus: TraceCacheStatus.hit,
      );
      if (!mounted) return;
      setState(() {
        _availabilityLoading = false;
        _availableModes = cached.availableModes;
        _modeCounts = cached.counts;
        _indexRevision = revision;
      });
      return;
    }
    final epoch = ++_availabilityEpoch;
    if (mounted) setState(() => _availabilityLoading = true);
    final bundle = await PlaygroundContentSource(
      _courseProvider,
    ).load(_selectedScope, weakEntries: _mistakeProvider.entries);
    if (!mounted || epoch != _availabilityEpoch) return;
    // Single-pass classification (Plan 3 §22.1): availability AND counts in
    // one traversal — counts and startable modes can no longer disagree.
    final index = PlaygroundIndex.build(bundle);
    if (!mounted || epoch != _availabilityEpoch) return;
    PlaygroundIndexCache.instance.put(revision, index);
    setState(() {
      _availabilityLoading = false;
      _availableModes = index.availableModes;
      _modeCounts = index.counts;
      _indexRevision = revision;
    });
  }

  /// 三个轻量 AI 语言工具（Plan 3 §19.2）：全部进入同一个 AiTutorChat
  /// 页面，靠 typed [AiTutorChatMode] 参数直达对应模式；普通练习模式不
  /// 依赖 AI 配置，打开本页也不发起任何 AI 请求。
  void _openAiTool(AiTutorChatMode mode) {
    context.router.push(AiTutorChatRoute(initialMode: mode));
  }

  void _selectScope(PlaygroundContentScope scope) {
    if (scope == _selectedScope) return;
    setState(() => _selectedScope = scope);
    unawaited(_loadAvailability());
  }

  void _onModeTap(PlaygroundMode mode) {
    if (!_sessionExecutionEnabled) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(AppStrings.playgroundComingSoon)),
      );
      return;
    }
    if (!_availableModes.contains(mode)) {
      // 不可用模式解释原因，而不是进入空页面（计划 §4.2）。
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(AppStrings.playgroundUnavailableNoContent)),
      );
      return;
    }
  }

  @override
  Widget build(BuildContext context) {
    final eligible = LanguagePlaygroundEligibility.isEligibleScope(
      _courseProvider.courseScope,
    );
    return Scaffold(
      appBar: AppBar(title: Text(AppStrings.playgroundTitle)),
      body: !eligible || _blockedInline
          ? const _PlaygroundBlockedBody()
          : _buildBody(context),
    );
  }

  Widget _buildBody(BuildContext context) {
    final focusMode = accessibilityOf(context).focusMode;
    return SafeArea(
      child: ListView(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
        children: [
          if (!focusMode) ...[
            PlaygroundHero(
              title: AppStrings.playgroundSmartStartTitle,
              subtitle: AppStrings.playgroundSmartStartCaption,
              onTap: () => _onModeTap(PlaygroundMode.smartMix),
            ),
            const SizedBox(height: 24),
          ],
          SectionTitle(title: AppStrings.playgroundContentScopeTitle),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final scope in PlaygroundContentScope.values)
                ChoiceChip(
                  label: Text(_scopeLabel(scope)),
                  selected: scope == _selectedScope,
                  onSelected: (_) => _selectScope(scope),
                ),
            ],
          ),
          const SizedBox(height: 24),
          SectionTitle(
            title: _availabilityLoading
                ? '${AppStrings.playgroundModeTitle}…'
                : AppStrings.playgroundModeTitle,
          ),
          GridView.count(
            crossAxisCount: 2,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            mainAxisSpacing: 12,
            crossAxisSpacing: 12,
            childAspectRatio: 1.6,
            children: [
              for (final mode in _gridModes)
                _ModeTile(
                  mode: mode,
                  available: _sessionExecutionEnabled &&
                      _availableModes.contains(mode),
                  count: _modeCounts[mode] ?? 0,
                  onTap: () => _onModeTap(mode),
                ),
            ],
          ),
          if (!focusMode) ...[
            const SizedBox(height: 24),
            SectionTitle(title: AppStrings.playgroundAiToolsTitle),
            const SizedBox(height: 8),
            Row(
              children: [
                _AiToolChip(
                  icon: Icons.help_outline_rounded,
                  label: AppStrings.playgroundAiToolQa,
                  onTap: () => _openAiTool(AiTutorChatMode.qa),
                ),
                const SizedBox(width: 8),
                _AiToolChip(
                  icon: Icons.spellcheck_rounded,
                  label: AppStrings.playgroundAiToolSentence,
                  onTap: () => _openAiTool(AiTutorChatMode.sentenceCheck),
                ),
                const SizedBox(width: 8),
                _AiToolChip(
                  icon: Icons.theater_comedy_outlined,
                  label: AppStrings.playgroundAiToolRoleplay,
                  onTap: () => _openAiTool(AiTutorChatMode.roleplay),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  String _scopeLabel(PlaygroundContentScope scope) => switch (scope) {
        PlaygroundContentScope.recent => AppStrings.playgroundScopeRecent,
        PlaygroundContentScope.currentUnit =>
          AppStrings.playgroundScopeCurrentUnit,
        PlaygroundContentScope.wholeCourse =>
          AppStrings.playgroundScopeWholeCourse,
        PlaygroundContentScope.weak => AppStrings.playgroundScopeWeak,
      };
}

/// 拦截态：当前课程不是语言课程时不提供任何练习内容。
class _PlaygroundBlockedBody extends StatelessWidget {
  const _PlaygroundBlockedBody();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.sports_esports_rounded,
              size: 48,
              color: TurnaTheme.textSecondaryColor(context),
            ),
            const SizedBox(height: 12),
            Text(
              AppStrings.playgroundBlockedTitle,
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w800,
                    color: TurnaTheme.textPrimaryColor(context),
                  ),
            ),
            const SizedBox(height: 4),
            Text(
              AppStrings.playgroundBlockedMessage,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    color: TurnaTheme.textSecondaryColor(context),
                  ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 模式格：可用时显示题量，不可用时降透明度并保留可读的禁用语义。
class _ModeTile extends StatelessWidget {
  final PlaygroundMode mode;
  final bool available;
  final int count;
  final VoidCallback onTap;

  const _ModeTile({
    required this.mode,
    required this.available,
    required this.count,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final accent = TurnaTheme.accentOnCard(context, TurnaTheme.brandTeal);
    final label = switch (mode) {
      PlaygroundMode.smartMix => AppStrings.playgroundModeSmartMix,
      PlaygroundMode.wordMatch => AppStrings.playgroundModeWordMatch,
      PlaygroundMode.quickChoice => AppStrings.playgroundModeQuickChoice,
      PlaygroundMode.listenAndPick => AppStrings.playgroundModeListenAndPick,
      PlaygroundMode.dictation => AppStrings.playgroundModeDictation,
      PlaygroundMode.sentenceOrder => AppStrings.playgroundModeSentenceOrder,
      PlaygroundMode.fillBlank => AppStrings.playgroundModeFillBlank,
      PlaygroundMode.dailyMix => AppStrings.playgroundModeDailyMix,
      PlaygroundMode.translation => AppStrings.playgroundModeTranslation,
    };
    final countText = mode == PlaygroundMode.dailyMix
        ? AppStrings.playgroundModeCount(15)
        : AppStrings.playgroundModeCount(count);

    return Opacity(
      opacity: available ? 1.0 : 0.5,
      child: Semantics(
        button: true,
        enabled: available,
        label: label,
        child: SoftCard(
          accentColor: TurnaTheme.brandTeal,
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Text(
                    label,
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.w700,
                          color: available
                              ? accent
                              : TurnaTheme.textSecondaryColor(context),
                        ),
                  ),
                ),
                Text(
                  !available ? AppStrings.playgroundComingSoon : countText,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: TurnaTheme.textSecondaryColor(context),
                      ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// 紧凑的 AI 小工具入口：不抢占 Playground Hero，也不复制完整聊天页。
class _AiToolChip extends StatelessWidget {
  const _AiToolChip({
    required this.icon,
    required this.label,
    required this.onTap,
  });

  final IconData icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: SoftCard(
        accentColor: TurnaTheme.brandTeal,
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
          child: Column(
            children: [
              Icon(icon, size: 20, color: TurnaTheme.brandTeal),
              const SizedBox(height: 6),
              Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.labelMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
