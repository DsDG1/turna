// Dart imports:
import 'dart:async';

// Flutter imports:
import 'package:flutter/material.dart';

// Package imports:
import 'package:auto_route/auto_route.dart';
import 'package:provider/provider.dart';

// Project imports:
import 'package:turna/application/anki_import/anki_import_completion_coordinator.dart';
import 'package:turna/application/anki_official/anki_deck_manager.dart';
import 'package:turna/application/anki_official/engine/official_anki_home_due_sync.dart';
import 'package:turna/application/anki_official/engine/official_formal_due_repository.dart';
import 'package:turna/application/anki_official/official_anki_feature_flags.dart';
import 'package:turna/application/anki_official/review/formal_review_launcher.dart';
import 'package:turna/application/course_catalog.dart';
import 'package:turna/application/course_provider.dart';
import 'package:turna/core/logger.dart';
import 'package:turna/core/spacing.dart';
import 'package:turna/core/text_styles.dart';
import 'package:turna/core/theme.dart';
import 'package:turna/di/injection.dart';
import 'package:turna/domain/course/course_scope.dart';
import 'package:turna/l10n/app_strings.dart';
import 'package:turna/routing/routing.gr.dart';
import 'package:turna/views/anki/import_wizard/official_pending_import_banner.dart';
import 'package:turna/views/anki_official/components/adaptation_restore_sheet.dart';
import 'package:turna/views/widgets/directory_rows.dart';
import 'package:turna/views/widgets/practice_empty_state.dart';
import 'package:turna/views/widgets/report_kit.dart';
import 'package:turna/views/widgets/session_shell.dart';
import 'package:turna/views/widgets/turna_page_content.dart';
import 'package:turna/views/widgets/turna_snack_bar.dart';

/// 记忆卡中枢 —— 记忆卡域的域首页（ADR 0066 §3）。
///
/// 今日任务台版式（P1）：顶部「今日待复习」大数字 + 「开始复习」主行动，
/// 有顺序的牌组队列行（行不是卡，发丝线分隔），尾部文字工具索引（导入、
/// 修复与维护）。承接原课程管理页的记忆卡条目语义：切换为当前复习域、
/// exact-source 确认的卸载、适配恢复（ADR 0057 §6）与修复中心入口。
@RoutePage()
class MemoryCardHubPage extends StatelessWidget {
  const MemoryCardHubPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: TurnaTheme.scaffoldBg(context),
      appBar: AppBar(
        title: Text(AppStrings.memoryCardHubTitle),
        leading: IconButton(
          tooltip: AppStrings.commonBack,
          icon: const Icon(Icons.arrow_back_rounded),
          onPressed: () => context.router.maybePop(),
        ),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: IconButton.filledTonal(
              icon: const Icon(Icons.file_upload_outlined),
              tooltip: AppStrings.memoryCardHubImportTitle,
              onPressed: () => context.router.push(AnkiImportRoute()),
            ),
          ),
        ],
      ),
      body: TurnaPageContent(
        maxWidth: 720,
        child: const _MemoryCardHubBody(),
      ),
    );
  }
}

class _MemoryCardHubBody extends StatefulWidget {
  const _MemoryCardHubBody();

  @override
  State<_MemoryCardHubBody> createState() => _MemoryCardHubBodyState();
}

class _MemoryCardHubBodyState extends State<_MemoryCardHubBody> {
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    unawaited(_refreshDue());
  }

  Future<void> _refreshDue() async {
    await const OfficialAnkiHomeDueSync().refresh();
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final courseProvider = context.watch<CourseProvider>();

    // 与旧课程管理页同源：catalog 顺序即用户持久化的牌组顺序。
    final entries = [
      for (final entry in courseProvider.catalogEntries)
        if (entry.scope is OfficialAnkiCourseScope ||
            entry.scope is LegacyAnkiCourseScope)
          entry,
    ];

    return ListenableBuilder(
      // 复习会话只写调度器与仓库快照；订阅它，回到本页时大数字才跟得上。
      listenable: OfficialFormalDueRepository.instance,
      builder: (context, _) => CustomScrollView(
        slivers: [
          if (_busy)
            const SliverToBoxAdapter(child: LinearProgressIndicator()),
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.pageMargin,
              AppSpacing.lg,
              AppSpacing.pageMargin,
              0,
            ),
            sliver: SliverToBoxAdapter(
              child: _buildDueHero(context),
            ),
          ),
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(
              AppSpacing.pageMargin,
              AppSpacing.md,
              AppSpacing.pageMargin,
              0,
            ),
            sliver: const SliverToBoxAdapter(
              child: OfficialPendingImportBanner(),
            ),
          ),
          if (entries.isEmpty)
            SliverFillRemaining(
              hasScrollBody: false,
              child: _buildEmptyState(context),
            )
          else ...[
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.pageMargin,
                AppSpacing.xl,
                AppSpacing.pageMargin,
                0,
              ),
              sliver: SliverToBoxAdapter(
                child: Text(
                  AppStrings.ankiHubDecksTitle,
                  style: AppTextStyles.sectionTitle(context),
                ),
              ),
            ),
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.pageMargin,
                AppSpacing.md,
                AppSpacing.pageMargin,
                0,
              ),
              sliver: SliverList.builder(
                itemCount: entries.length,
                itemBuilder: (context, index) {
                  final entry = entries[index];
                  return _DeckRow(
                    entry: entry,
                    isActiveScope: courseProvider.scope == entry.scope,
                    dueCount: _dueForEntry(entry),
                    onTap: () => unawaited(_startDeckReview(context, entry)),
                    onBrowse: () => unawaited(
                      context.router.push(
                        AnkiCardBrowserRoute(
                          importId:
                              entry.officialSourceId ?? entry.legacyImportId!,
                          title: entry.displayName,
                          sectionId: ankiImportSectionIdFor(
                            courseProvider,
                            entry.officialSourceId ?? entry.legacyImportId!,
                          ),
                        ),
                      ),
                    ),
                    onStats: () => unawaited(
                      context.router.push(
                        AnkiDeckStatsRoute(
                          importId:
                              entry.officialSourceId ?? entry.legacyImportId!,
                          title: entry.displayName,
                        ),
                      ),
                    ),
                    onSwitchScope: _busy
                        ? null
                        : () => unawaited(_switchScope(context, entry)),
                    onAdaptation:
                        _busy || entry.officialSourceId == null
                            ? null
                            : () => unawaited(
                                  showAdaptationRestoreSheet(
                                    context,
                                    sourceId: entry.officialSourceId!,
                                  ),
                                ),
                    onUninstall: _busy
                        ? null
                        : () => unawaited(_uninstallEntry(context, entry)),
                  );
                },
              ),
            ),
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.pageMargin,
                AppSpacing.xl,
                AppSpacing.pageMargin,
                AppSpacing.xl,
              ),
              sliver: SliverToBoxAdapter(child: _buildToolsIndex(context)),
            ),
          ],
        ],
      ),
    );
  }

  // ─── 今日任务台头部：大数字 + 主行动 ──────────────────────────────

  Widget _buildDueHero(BuildContext context) {
    final repo = OfficialFormalDueRepository.instance;
    if (repo.snapshot.unavailable) {
      return _DueUnavailableBanner(onRetry: _refreshDue);
    }
    final introducedDue = _aggregatedDue();
    final unintroducedNew = repo.snapshot.unintroducedOfficialDue;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ReportMetricHeader(
          key: const Key('memory-card-hub-hero'),
          label: AppStrings.memoryCardHubTodayDue,
          value: '$introducedDue',
          unit: AppStrings.ankiHubDueCountLabel,
          caption: introducedDue <= 0 && unintroducedNew <= 0
              ? AppStrings.ankiHubCaughtUpMessage
              : AppStrings.ankiFormalDueBreakdown(
                  introducedDue: introducedDue,
                  unintroducedNew: unintroducedNew,
                ),
          accentColor: TurnaTheme.brandTealDark,
        ),
        const SizedBox(height: AppSpacing.md),
        SessionPrimaryAction(
          key: const Key('memory-card-hub-review-all'),
          label: AppStrings.ankiReviewAll,
          trailingIcon: Icons.play_arrow_rounded,
          onPressed: introducedDue > 0
              ? () => unawaited(_startAggregateReview(context))
              : null,
        ),
      ],
    );
  }

  Widget _buildEmptyState(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.xxxl),
      child: PracticeEmptyState(
        icon: Icons.layers_outlined,
        accentColor: TurnaTheme.brandTeal,
        title: AppStrings.ankiNoDecksTitle,
        message: AppStrings.ankiNoDecksSubtitle,
        actionLabel: AppStrings.memoryCardHubImportTitle,
        onAction: () => context.router.push(AnkiImportRoute()),
      ),
    );
  }

  Widget _buildToolsIndex(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          AppStrings.memoryCardHubToolsTitle,
          style: AppTextStyles.sectionTitle(context),
        ),
        const SizedBox(height: AppSpacing.md),
        DirectoryLinkRow(
          key: const Key('memory-card-hub-import'),
          icon: Icons.file_download_outlined,
          iconTone: TurnaTheme.brandTeal,
          title: AppStrings.memoryCardHubImportTitle,
          description: AppStrings.memoryCardHubImportDesc,
          onTap: () => context.router.push(AnkiImportRoute()),
        ),
        DirectoryLinkRow(
          key: const Key('memory-card-hub-repair'),
          icon: Icons.healing_outlined,
          iconTone: TurnaTheme.anatolianClay,
          title: AppStrings.memoryCardHubRepairTitle,
          description: AppStrings.memoryCardHubRepairDesc,
          onTap: () =>
              context.router.push(OfficialAnkiRepairCenterRoute()),
        ),
      ],
    );
  }

  // ─── 到期计数 ────────────────────────────────────────────────────

  /// Doc 35 L2：到期只聚合 Official due 仓库；旧版导入源读 0（fail-closed）。
  int? _dueForEntry(CourseCatalogEntry entry) {
    final repo = OfficialFormalDueRepository.instance;
    final importId = entry.officialSourceId ?? entry.legacyImportId;
    if (importId == null ||
        !repo.officialImportIds.contains(importId)) {
      return 0;
    }
    if (repo.snapshot.unavailable) return null;
    return repo.formalOfficialDueForImport(importId);
  }

  int _aggregatedDue() {
    final courseProvider = context.read<CourseProvider>();
    var total = 0;
    for (final entry in courseProvider.catalogEntries) {
      if (entry.scope is! OfficialAnkiCourseScope &&
          entry.scope is! LegacyAnkiCourseScope) {
        continue;
      }
      total += _dueForEntry(entry) ?? 0;
    }
    return total;
  }

  // ─── 行动 ────────────────────────────────────────────────────────

  Future<void> _startAggregateReview(BuildContext context) async {
    await const FormalReviewLauncher().open(
      context,
      entry: FormalReviewEntryKind.courseReview,
      courseId: 'anki',
      officialOwner:
          OfficialFormalDueRepository.instance.officialImportIds.isNotEmpty,
      schedulerRuntimeAvailable:
          OfficialAnkiFeatureFlags.current.allowsOfficialScheduler,
    );
    if (mounted) unawaited(_refreshDue());
  }

  Future<void> _startDeckReview(
    BuildContext context,
    CourseCatalogEntry entry,
  ) async {
    final importId = entry.officialSourceId ?? entry.legacyImportId ?? '';
    await const FormalReviewLauncher().open(
      context,
      entry: FormalReviewEntryKind.deckSection,
      courseId: importId.isEmpty ? 'anki' : 'anki-$importId',
      sectionId: importId.isEmpty
          ? null
          : ankiImportSectionIdFor(context.read<CourseProvider>(), importId),
      officialOwner: OfficialFormalDueRepository
          .instance.officialImportIds.contains(importId),
      schedulerRuntimeAvailable:
          OfficialAnkiFeatureFlags.current.allowsOfficialScheduler,
    );
    if (mounted) unawaited(_refreshDue());
  }

  /// 切换为当前复习域：原课程管理页的选课语义（setScope + 返回上一页）。
  Future<void> _switchScope(
    BuildContext context,
    CourseCatalogEntry entry,
  ) async {
    try {
      await context.read<CourseProvider>().setScope(entry.scope);
    } on CourseScopeSwitchException catch (error) {
      // Provider 已回滚到之前的课程，无需额外恢复。
      if (context.mounted) {
        TurnaSnackBar.show(
          context,
          AppStrings.settingsLanguageSwitchFailed(error.cause),
        );
      }
      return;
    }
    if (context.mounted) await context.router.maybePop();
  }

  /// 卸载：exact-source 确认（名字 + 短源 id + 卡数）+ 完整源身份删除，
  /// 语义摘自原课程管理页（ADR 0043 / ADR 0066 承接）。
  Future<void> _uninstallEntry(
    BuildContext context,
    CourseCatalogEntry entry,
  ) async {
    final idDetail = entry.shortId.isEmpty
        ? ''
        : '\n${entry.shortId} · ${AppStrings.ankiDeckCardCount(entry.cardCount)}';
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(AppStrings.ankiUninstallConfirmTitle),
        content:
            Text('${entry.displayName}$idDetail\n\n${AppStrings.ankiUninstallConfirmBody}'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: Text(AppStrings.commonCancel),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: TurnaTheme.error,
            ),
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: Text(AppStrings.ankiUninstallDeck),
          ),
        ],
      ),
    );
    if (confirmed != true || !context.mounted) return;
    if (_busy) return;
    setState(() => _busy = true);

    final courseProvider = context.read<CourseProvider>();
    // Uninstall with the COMPLETE source identity — never a truncated id.
    final deletionId = entry.officialSourceId ?? entry.legacyImportId!;
    var uninstallCompleted = false;
    try {
      uninstallCompleted = await getIt<AnkiDeckManager>().uninstall(deletionId);
    } catch (e) {
      logger.w('[MemoryCardHub] uninstall failed for $deletionId: $e');
    }
    if (!context.mounted) {
      if (mounted) setState(() => _busy = false);
      return;
    }
    // 删除的是当前复习域时，先落回内置语言课程，再持久化剩余顺序。
    if (courseProvider.scope == entry.scope) {
      await courseProvider.setScope(
        CourseCatalog.fallbackBuiltin(courseProvider.catalogEntries),
      );
    } else {
      await courseProvider.reloadCourse();
    }
    await courseProvider.persistCourseOrder(
      [for (final e in courseProvider.catalogEntries) e.wireKey],
    );
    if (!context.mounted) {
      if (mounted) setState(() => _busy = false);
      return;
    }
    // false（locator 未就绪）与抛错（提交前失败）都意味着本次什么都没删掉
    // ——「未完成，请重试」此时才与牌组列表状态一致。
    TurnaSnackBar.show(
      context,
      uninstallCompleted
          ? AppStrings.ankiDeckRemoved
          : AppStrings.ankiDeckRemovalFailed,
    );
    if (mounted) setState(() => _busy = false);
  }
}

/// 牌组队列行：牌组名 + 到期/卡数 + 短源 id 元信息；点按 = 该牌组正式
/// 复习，尾键承接原课程卡菜单语义（浏览 / 统计 / 切换复习域 / 适配恢复 /
/// 卸载）。
class _DeckRow extends StatelessWidget {
  const _DeckRow({
    required this.entry,
    required this.isActiveScope,
    required this.dueCount,
    required this.onTap,
    required this.onBrowse,
    required this.onStats,
    required this.onSwitchScope,
    required this.onAdaptation,
    required this.onUninstall,
  });

  final CourseCatalogEntry entry;
  final bool isActiveScope;

  /// null = 到期仓库暂不可用（显示 —，不做 fail-open 的 0）。
  final int? dueCount;
  final VoidCallback onTap;
  final VoidCallback onBrowse;
  final VoidCallback onStats;
  final VoidCallback? onSwitchScope;
  final VoidCallback? onAdaptation;
  final VoidCallback? onUninstall;

  @override
  Widget build(BuildContext context) {
    final subtitle = [
      switch (dueCount) {
        null => AppStrings.memoryCardHubDeckDueUnknown,
        final due => AppStrings.memoryCardHubDeckDue(due),
      },
      AppStrings.ankiDeckCardCount(entry.cardCount),
    ].join(' · ');
    final meta = entry.shortId.isEmpty
        ? null
        : (isActiveScope
            ? '${AppStrings.memoryCardHubActiveScopeBadge} · ${entry.shortId}'
            : entry.shortId);

    return DirectoryEntryRow(
      key: ValueKey('memory-card-hub-deck-${entry.wireKey}'),
      title: entry.displayName,
      subtitle: subtitle,
      meta: meta,
      trailing: _DeckMenuButton(
        onBrowse: onBrowse,
        onStats: onStats,
        onSwitchScope: onSwitchScope,
        onAdaptation: onAdaptation,
        onUninstall: onUninstall,
      ),
      onTap: onTap,
    );
  }
}

class _DeckMenuButton extends StatelessWidget {
  const _DeckMenuButton({
    required this.onBrowse,
    required this.onStats,
    required this.onSwitchScope,
    required this.onAdaptation,
    required this.onUninstall,
  });

  final VoidCallback onBrowse;
  final VoidCallback onStats;
  final VoidCallback? onSwitchScope;
  final VoidCallback? onAdaptation;
  final VoidCallback? onUninstall;

  @override
  Widget build(BuildContext context) {
    return PopupMenuButton<String>(
      tooltip: AppStrings.commonMoreActions,
      icon: Icon(
        Icons.more_vert_rounded,
        size: 20,
        color: TurnaTheme.textSecondaryColor(context),
      ),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
      ),
      onSelected: (value) {
        switch (value) {
          case 'browse':
            onBrowse();
          case 'stats':
            onStats();
          case 'switch':
            onSwitchScope?.call();
          case 'adaptation':
            onAdaptation?.call();
          case 'uninstall':
            onUninstall?.call();
        }
      },
      itemBuilder: (context) => [
        PopupMenuItem(
          value: 'browse',
          child: _menuRow(
            context,
            icon: Icons.view_list_outlined,
            label: AppStrings.ankiBrowseCards,
          ),
        ),
        PopupMenuItem(
          value: 'stats',
          child: _menuRow(
            context,
            icon: Icons.insights_outlined,
            label: AppStrings.ankiDeckStats,
          ),
        ),
        if (onSwitchScope != null)
          PopupMenuItem(
            value: 'switch',
            child: _menuRow(
              context,
              icon: Icons.swap_horiz_rounded,
              label: AppStrings.memoryCardHubSwitchScope,
            ),
          ),
        // 只有官方来源才有适配方案可恢复（ADR 0057 §6）。
        if (onAdaptation != null)
          PopupMenuItem(
            value: 'adaptation',
            child: _menuRow(
              context,
              icon: Icons.tune_rounded,
              label: AppStrings.ankiAdaptationRestoreTitle,
            ),
          ),
        if (onUninstall != null)
          PopupMenuItem(
            value: 'uninstall',
            child: _menuRow(
              context,
              icon: Icons.delete_outline_rounded,
              label: AppStrings.ankiUninstallDeck,
              color: TurnaTheme.error,
            ),
          ),
      ],
    );
  }

  Widget _menuRow(
    BuildContext context, {
    required IconData icon,
    required String label,
    Color? color,
  }) {
    return Row(
      children: [
        Icon(icon, size: 20, color: color ?? TurnaTheme.brandTeal),
        const SizedBox(width: 12),
        Text(label),
      ],
    );
  }
}

/// 到期仓库暂不可用的横条（纸面 + 警示描边 + 重试）。
class _DueUnavailableBanner extends StatelessWidget {
  const _DueUnavailableBanner({required this.onRetry});

  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Container(
      key: const Key('memory-card-hub-due-unavailable'),
      padding: const EdgeInsets.fromLTRB(16, 12, 8, 12),
      decoration: BoxDecoration(
        color: TurnaTheme.warning.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(TurnaTheme.radiusLarge),
        border: Border.all(color: TurnaTheme.warning.withValues(alpha: 0.4)),
      ),
      child: Row(
        children: [
          Icon(
            Icons.sync_problem_rounded,
            color: TurnaTheme.warning,
            size: 22,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              AppStrings.ankiDueUnavailable,
              style: AppTextStyles.bodyText(context).copyWith(
                fontSize: 14,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          IconButton(
            tooltip: AppStrings.ankiReviewRetry,
            onPressed: onRetry,
            icon: const Icon(Icons.refresh_rounded),
          ),
        ],
      ),
    );
  }
}
