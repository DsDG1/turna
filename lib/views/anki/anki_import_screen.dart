// Dart imports:
import 'dart:async';

// Flutter imports:
import 'package:flutter/material.dart';

// Package imports:
import 'package:auto_route/auto_route.dart';
import 'package:provider/provider.dart';

// Project imports:
import 'package:turna/application/anki_import/anki_import_controller.dart';
import 'package:turna/application/anki_import/official_import_error_messages.dart';
import 'package:turna/application/anki_import/anki_import_completion_coordinator.dart';
import 'package:turna/application/anki_import/anki_import_dependencies.dart';
import 'package:turna/application/anki_import/anki_import_wizard_state.dart';
import 'package:turna/application/anki_official/engine/official_formal_due_repository.dart';
import 'package:turna/application/anki_official/official_anki_feature_flags.dart';
import 'package:turna/application/anki_official/review/formal_review_launcher.dart';
import 'package:turna/application/course_provider.dart';
import 'package:turna/application/settings_provider.dart';
import 'package:turna/core/spacing.dart';
import 'package:turna/core/text_styles.dart';
import 'package:turna/l10n/app_strings.dart';
import 'package:turna/routing/routing.gr.dart';
import 'package:turna/views/anki/import_wizard/anki_import_done_step.dart';
import 'package:turna/views/anki/import_wizard/anki_import_wizard_widgets.dart';
import 'package:turna/views/anki/import_wizard/modern_anki_import_preview.dart';
import 'package:turna/views/widgets/session_shell.dart';
import 'package:turna/views/widgets/turna_page_content.dart';
import 'package:turna/views/anki/import_wizard/official_pending_import_banner.dart';
import 'package:turna/core/theme.dart';

/// Anki import wizard shell (maintainability plan §10),「湿地雾光」步骤
/// 流程版式（P1 / ADR 0066：只动视觉外壳，流程、判定与保真档位原样）：
///
/// ```text
/// WizardStepper + 阶段说明     顶部：五步指示 + 阶段标题与一句说明
/// 中央单焦点                    文件选择 / 解析进度 / 预览 / 完成摘要
/// SessionActionBand             底部固定阶段操作（选择文件 / 取消 / 导入）
/// ```
///
/// The page only renders controller state, hosts dialogs/routes and performs
/// the done-step navigation intents — the flow state machine lives in
/// [AnkiImportController], business work in the official-first flow.
///
/// Steps: 1. file selection 2. parsing 3. preview (deck structure,
/// notetype mapping) 4. import execution 5. done.
@RoutePage()
class AnkiImportPage extends StatefulWidget {
  const AnkiImportPage({super.key});

  @override
  State<AnkiImportPage> createState() => _AnkiImportPageState();
}

class _AnkiImportPageState extends State<AnkiImportPage> {
  AnkiImportController? _controller;

  @override
  void dispose() {
    unawaited(_controller?.disposeAsync());
    super.dispose();
  }

  AnkiImportController _buildController() {
    return AnkiImportController(
      deps: AnkiImportDependencies.production(
        courseProvider: context.read<CourseProvider>(),
        settings: context.read<SettingsProvider>(),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    // The controller is created on first build (not initState) so provider
    // lookups happen inside a valid provider scope.
    final controller = _controller ??= _buildController();
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;
        if (!mounted) return;
        final leave = await _confirmLeave(context, controller);
        // Unconditional pop bypasses canPop so this callback doesn't
        // re-enter (the ai_api_config_page pop-loop fix, same landmine).
        if (leave && context.mounted) context.router.pop();
      },
      child: Scaffold(
        appBar: AppBar(
          title: Text(
            AppStrings.ankiImportTitle,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          leading: IconButton(
            tooltip: AppStrings.commonBack,
            icon: const Icon(Icons.arrow_back),
            onPressed: () async {
              final leave = await _confirmLeave(context, controller);
              // Same as the PopScope handler: pop unconditionally after the
              // confirm — maybePop re-enters the canPop gate forever.
              if (leave && context.mounted) context.router.pop();
            },
          ),
        ),
        body: AnimatedBuilder(
          animation: controller,
          builder: (context, _) {
            final state = controller.state;
            // A Failed state renders its return-state UI plus the error
            // surface (the legacy page swapped _error + step; this encodes
            // the same outcome in the type).
            final effective =
                state is AnkiImportFailed ? state.returnState : state;
            final failureMessage =
                state is AnkiImportFailed ? state.message : null;
            return TurnaPageContent(
              maxWidth: 840,
              child: Column(
                children: [
                  // The stepper must listen to the same controller as the
                  // body. It used to sit outside this AnimatedBuilder, so it
                  // rendered the initial step once and stayed frozen on
                  // 选择文件 while the body advanced underneath it.
                  WizardStepper(currentStep: state.step),
                  _stageHeaderFor(effective, failureMessage),
                  Expanded(
                    child: _buildCentralFocus(
                      context,
                      controller,
                      effective,
                      failureMessage,
                    ),
                  ),
                  if (_buildActionBand(context, controller, effective,
                          failureMessage) case final band?)
                    band,
                ],
              ),
            );
          },
        ),
      ),
    );
  }

  /// 步骤流程的顶部阶段说明。预览与完成步自带内容级说明（预览头卡 /
  /// 完成摘要），不再叠一层阶段头。
  Widget _stageHeaderFor(AnkiImportWizardState effective, String? error) {
    final (String? title, String? hint) = switch (effective) {
      AnkiImportSelecting() => (
          AppStrings.ankiImportSelectTitle,
          error ?? AppStrings.ankiImportSelectSubtitle,
        ),
      AnkiImportAlreadyImported(:final displayName) => (
          AppStrings.ankiAlreadyImportedTitle,
          displayName,
        ),
      AnkiImportParsing() => (AppStrings.ankiStepParse, null),
      AnkiImportCommitting() => (AppStrings.ankiStepImport, null),
      _ => (null, null),
    };
    if (title == null) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.pageMargin,
        AppSpacing.md,
        AppSpacing.pageMargin,
        0,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: AppTextStyles.sectionTitle(context)),
          if (hint != null && hint.isNotEmpty) ...[
            const SizedBox(height: AppSpacing.xs + 2),
            Text(
              hint,
              style: AppTextStyles.captionSm(context).copyWith(height: 1.45),
            ),
          ],
        ],
      ),
    );
  }

  Future<bool> _confirmLeave(
    BuildContext context,
    AnkiImportController controller,
  ) async {
    final state = controller.state;
    if (state is AnkiImportSelecting ||
        state is AnkiImportCompleted ||
        state is AnkiImportAlreadyImported) {
      return true;
    }
    if (state is AnkiImportPreviewing) {
      final choice = await showDialog<String>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Text(AppStrings.ankiImportLeaveTitle),
          content: Text(AppStrings.ankiImportLeavePreviewMessage),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, 'later'),
              child: Text(AppStrings.ankiImportLeaveContinueLater),
            ),
            TextButton(
              onPressed: () => Navigator.pop(ctx, 'discard'),
              child: Text(AppStrings.ankiImportLeaveDiscard),
            ),
          ],
        ),
      );
      if (choice == 'discard') {
        await controller.reset();
        return true;
      }
      return choice == 'later';
    }
    final choice = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(AppStrings.ankiImportLeaveTitle),
        content: Text(AppStrings.ankiImportLeaveBusyMessage),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, 'wait'),
            child: Text(AppStrings.ankiImportLeaveWait),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, 'discard'),
            child: Text(AppStrings.ankiImportLeaveDiscard),
          ),
        ],
      ),
    );
    if (choice == 'discard') {
      controller.cancel();
      return true;
    }
    return false;
  }

  // ─── 中央单焦点（每步一个焦点，不混排） ───────────────────────────

  Widget _buildCentralFocus(
    BuildContext context,
    AnkiImportController controller,
    AnkiImportWizardState effective,
    String? failureMessage,
  ) {
    switch (effective) {
      case AnkiImportSelecting(:final error):
        return _buildSelectStep(
          error: failureMessage ?? error,
          controller: controller,
        );
      case AnkiImportAlreadyImported():
        return _buildAlreadyImportedCentral(controller);
      case AnkiImportParsing():
        return _buildParsingStep(controller, effective);
      case AnkiImportCommitting():
        return _buildCommittingStep(controller, effective);
      case AnkiImportPreviewing():
        return _buildPreviewStep(
            context, controller, effective, failureMessage);
      case AnkiImportCompleted():
        return _buildDoneStep(controller, effective);
      case AnkiImportFailed():
        return const SizedBox.shrink();
    }
  }

  // ─── Step 0: File Selection ─────────────────────────────────────────

  Widget _buildSelectStep({
    required String? error,
    required AnkiImportController controller,
  }) {
    // Wrap in SafeArea + a constrained scroll view so the column stays
    // vertically centered when there is enough room, and becomes
    // scrollable when a small viewport reduces the available height.
    return SafeArea(
      child: LayoutBuilder(
        builder: (context, constraints) => SingleChildScrollView(
          padding: EdgeInsets.zero,
          child: ConstrainedBox(
            constraints: BoxConstraints(
              minHeight: constraints.maxHeight,
              minWidth: constraints.maxWidth,
            ),
            child: Center(
              child: Padding(
                padding: const EdgeInsets.all(AppSpacing.xl),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Icon(
                      Icons.upload_file_rounded,
                      size: 72,
                      color: TurnaTheme.brandTeal.withValues(alpha: 0.6),
                    ),
                    const SizedBox(height: AppSpacing.lg),
                    OfficialPendingImportBanner(
                      // Banner 放弃后 controller 重发 Selecting 态，本页
                      // 随 AnimatedBuilder 一起重读 catalog（C2：一次
                      // build 只查一次由 build 侧承担——见 _buildActionBand）。
                      onChanged: controller.clearSelectFailure,
                      onContinue: (item) => controller.continuePending(item),
                    ),
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      title: Text(AppStrings.ankiIncludeMedia),
                      subtitle: Text(AppStrings.ankiIncludeMediaHint),
                      value: controller.includeMedia,
                      onChanged: (value) {
                        controller.setIncludeMedia(value);
                        // The switch is plain local state; the shell only
                        // rebuilds on controller ticks, so nudge it here.
                        setState(() {});
                      },
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  // ─── Steps 1 & 3: Progress ───────────────────────────────────────────

  Widget _buildParsingStep(
    AnkiImportController controller,
    AnkiImportParsing parsing,
  ) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.xl),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            // Doc 39 P5: the never-non-zero progress bar died with the field.
            _ImportProgressIndicator(
              current: parsing.progressCurrent,
              total: parsing.progressTotal,
            ),
            const SizedBox(height: AppSpacing.lg),
            Text(
              AppStrings.ankiParsing,
              style: AppTextStyles.cardTitle(context),
            ),
            if (parsing.message.isNotEmpty) ...[
              const SizedBox(height: AppSpacing.sm),
              Text(
                parsing.message,
                textAlign: TextAlign.center,
                style: AppTextStyles.captionSm(context),
              ),
            ],
            if (parsing.stage != null) ...[
              const SizedBox(height: AppSpacing.sm),
              Text(
                parsing.stage!,
                style: AppTextStyles.captionSm(context).copyWith(
                  color: TurnaTheme.textHintColor(context),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildCommittingStep(
    AnkiImportController controller,
    AnkiImportCommitting committing,
  ) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.xl),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            _ImportProgressIndicator(
              current: committing.progressCurrent,
              total: committing.progressTotal,
            ),
            const SizedBox(height: AppSpacing.lg),
            Text(
              committing.message.isEmpty
                  ? AppStrings.ankiPreparingImport
                  : committing.message,
              textAlign: TextAlign.center,
              style: AppTextStyles.cardTitle(context),
            ),
            if (committing.stage != null) ...[
              const SizedBox(height: AppSpacing.sm),
              Text(
                committing.stage!,
                style: AppTextStyles.captionSm(context).copyWith(
                  color: TurnaTheme.textHintColor(context),
                ),
              ),
            ],
            const SizedBox(height: AppSpacing.sm),
            Text(
              AppStrings.ankiProgressCannotCancel,
              style: AppTextStyles.captionSm(context),
            ),
            // A2：commit 一旦进入 live 写不可取消——底部不提供任何阶段
            // 操作，避免用户以为能中断（台账已在写，强退由 finishCommit
            // 收尾清理）。
          ],
        ),
      ),
    );
  }

  // ─── Step 2: Preview ────────────────────────────────────────────────

  Widget _buildPreviewStep(
    BuildContext context,
    AnkiImportController controller,
    AnkiImportPreviewing previewing,
    String? failureMessage,
  ) {
    final official = previewing.preview as OfficialAnkiImportPreviewModel;
    // 预览步自带滚动内容 + 底部固定导入操作（StickyImportBar 已换
    // SessionActionBand 壳），外层不再叠阶段操作。
    return ModernAnkiImportPreview(
      preview: official,
      controller: controller,
      error: failureMessage,
    );
  }

  // ─── Step 4: Done ───────────────────────────────────────────────────

  Widget _buildDoneStep(
    AnkiImportController controller,
    AnkiImportCompleted completed,
  ) {
    return AnkiImportDoneStep(
      summary: completed.summary,
      keptLearningProgress: false,
      onStartLearningNow: () => unawaited(_startLearningNow(controller)),
      onViewDecks: () => unawaited(_viewDecks()),
      onDone: () => context.router.pop(),
    );
  }

  /// "Start learning now": go straight into the freshly-imported deck's
  /// formal review. ADR 0066 §2 — this action no longer switches the active
  /// language course; the wizard pops afterwards so the session host is what
  /// remains on screen.
  Future<void> _startLearningNow(AnkiImportController controller) async {
    final importId = controllerCompletedImportId(controller);
    if (importId != null && mounted) {
      final courseProvider = context.read<CourseProvider>();
      await const FormalReviewLauncher().open(
        context,
        entry: FormalReviewEntryKind.deckSection,
        courseId: 'anki-$importId',
        sectionId: ankiImportSectionIdFor(courseProvider, importId),
        officialOwner: OfficialFormalDueRepository
            .instance.officialImportIds.contains(importId),
        schedulerRuntimeAvailable:
            OfficialAnkiFeatureFlags.current.allowsOfficialScheduler,
      );
    }
    // In Completed state _confirmLeave is an instant `true`, so a maybePop
    // here would bounce off the canPop gate and re-enter the pop handler
    // forever (the on-device freeze). Leave unconditionally.
    if (mounted) context.router.pop();
  }

  /// "View decks": open the memory-card hub (ADR 0066 §2 — the language
  /// course management no longer lists decks). The active course stays.
  Future<void> _viewDecks() async {
    await context.router.push(const MemoryCardHubRoute());
  }

  String? controllerCompletedImportId(AnkiImportController controller) {
    final state = controller.state;
    if (state is AnkiImportCompleted) return state.summary.importId;
    if (state is AnkiImportFailed && state.returnState is AnkiImportCompleted) {
      return (state.returnState as AnkiImportCompleted).summary.importId;
    }
    return null;
  }

  Widget _buildAlreadyImportedCentral(AnkiImportController controller) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.xl),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.inventory_2_outlined,
                size: 72, color: TurnaTheme.brandTeal),
          ],
        ),
      ),
    );
  }

  // ─── 底部固定阶段操作（SessionActionBand） ────────────────────────

  Widget? _buildActionBand(
    BuildContext context,
    AnkiImportController controller,
    AnkiImportWizardState effective,
    String? failureMessage,
  ) {
    switch (effective) {
      case AnkiImportSelecting():
        // C2：一次 build 只查一次 catalog（同步 sqlite）；banner 变化经
        // controller 重发 Selecting 后由 AnimatedBuilder 重建再查。
        final hasUnfinished = catalogHasUnfinishedOfficialImport();
        return SessionActionBand(
          child: SessionPrimaryAction(
            label: AppStrings.ankiChooseFile,
            trailingIcon: Icons.folder_open_outlined,
            onPressed: hasUnfinished ? null : controller.pickFile,
          ),
        );
      case AnkiImportAlreadyImported():
        return SessionActionBand(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SessionPrimaryAction(
                label: AppStrings.ankiAlreadyImportedOpen,
                trailingIcon: Icons.play_arrow_rounded,
                onPressed: () =>
                    unawaited(controller.openExistingCourse()),
              ),
              const SizedBox(height: AppSpacing.sm),
              SizedBox(
                height: 48,
                child: OutlinedButton(
                  onPressed: () => unawaited(controller.replaceExisting()),
                  child: Text(AppStrings.ankiAlreadyImportedReplace),
                ),
              ),
            ],
          ),
        );
      case AnkiImportParsing():
        return SessionActionBand(
          child: SizedBox(
            height: 48,
            child: OutlinedButton.icon(
              onPressed: controller.cancel,
              icon: const Icon(Icons.close_rounded, size: 18),
              label: Text(AppStrings.commonCancel),
            ),
          ),
        );
      case AnkiImportCommitting():
        // 不可取消（A2）：无阶段操作。
        return null;
      case AnkiImportPreviewing():
        // 预览的导入操作在 ModernAnkiImportPreview 的 StickyImportBar 内。
        return null;
      case AnkiImportCompleted():
        // 完成动作在 AnkiImportDoneStep 的动作带内。
        return null;
      case AnkiImportFailed():
        return null;
    }
  }
}

class _ImportProgressIndicator extends StatelessWidget {
  const _ImportProgressIndicator({this.current, this.total});

  final int? current;
  final int? total;

  @override
  Widget build(BuildContext context) {
    final totalCount = total;
    if (current != null && totalCount != null && totalCount > 0) {
      return SizedBox(
        width: 220,
        child: LinearProgressIndicator(value: current! / totalCount),
      );
    }
    return const CircularProgressIndicator();
  }
}
