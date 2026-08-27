// Dart imports:
import 'dart:async';

// Flutter imports:
import 'package:flutter/material.dart';

// Package imports:
import 'package:auto_route/auto_route.dart';
import 'package:provider/provider.dart';

// Project imports:
import 'package:turna/application/anki_import/anki_import_controller.dart';
import 'package:turna/application/anki_import/anki_import_dependencies.dart';
import 'package:turna/application/anki_import/anki_import_wizard_state.dart';
import 'package:turna/application/anki_official/contract/official_anki_dto.dart';
import 'package:turna/application/course_provider.dart';
import 'package:turna/application/settings_provider.dart';
import 'package:turna/l10n/app_strings.dart';
import 'package:turna/routing/routing.gr.dart';
import 'package:turna/views/anki/import_wizard/anki_import_done_step.dart';
import 'package:turna/views/anki/import_wizard/anki_import_wizard_widgets.dart';
import 'package:turna/views/anki/import_wizard/official_anki_import_preview.dart';
import 'package:turna/views/theme.dart';

/// Anki import wizard shell (maintainability plan §10). The page only
/// renders controller state, hosts dialogs/routes and performs the
/// done-step navigation intents — the flow state machine lives in
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
    return Scaffold(
      appBar: AppBar(
        title: Text(
          AppStrings.ankiImportTitle,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => context.router.maybePop(),
        ),
      ),
      body: Column(
        children: [
          WizardStepper(currentStep: controller.state.step),
          Expanded(
            child: AnimatedBuilder(
              animation: controller,
              builder: (context, _) => _buildBody(context, controller),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBody(BuildContext context, AnkiImportController controller) {
    final state = controller.state;
    // A Failed state renders its return-state UI plus the error surface
    // (the legacy page swapped _error + step; this encodes the same
    // outcome in the type).
    final effective = state is AnkiImportFailed ? state.returnState : state;
    final failureMessage = state is AnkiImportFailed ? state.message : null;
    switch (effective) {
      case AnkiImportSelecting(:final error):
        return _buildSelectStep(
          error: failureMessage ?? error,
          controller: controller,
        );
      case AnkiImportParsing():
        return _buildParsingStep(controller, effective);
      case AnkiImportCommitting():
        return _buildCommittingStep(controller, effective);
      case AnkiImportPreviewing():
        return _buildPreviewStep(context, controller, effective, failureMessage);
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
                padding: const EdgeInsets.all(32),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    Icon(
                      Icons.upload_file_rounded,
                      size: 80,
                      color: TurnaTheme.brandTeal.withValues(alpha: 0.6),
                    ),
                    const SizedBox(height: 24),
                    // No duplicate title here; the AppBar already shows it.
                    Text(
                      AppStrings.ankiImportSelectSubtitle,
                      style: TextStyle(
                        color: TurnaTheme.textSecondaryColor(context),
                        fontSize: 15,
                        height: 1.4,
                      ),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 32),
                    if (error != null)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 16),
                        child: Text(
                          error,
                          style: const TextStyle(color: TurnaTheme.error),
                          textAlign: TextAlign.center,
                        ),
                      ),
                    ElevatedButton.icon(
                      onPressed: controller.pickFile,
                      icon: const Icon(Icons.folder_open),
                      label: Text(AppStrings.ankiChooseFile),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: TurnaTheme.brandTeal,
                        foregroundColor: TurnaTheme.textOnPrimary,
                        padding: const EdgeInsets.symmetric(
                            horizontal: 32, vertical: 16),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
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
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          if (parsing.progress > 0)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 60),
              child: LinearProgressIndicator(
                value: parsing.progress,
                backgroundColor: TurnaTheme.brandTeal.withValues(alpha: 0.1),
                valueColor:
                    const AlwaysStoppedAnimation<Color>(TurnaTheme.brandTeal),
              ),
            )
          else
            const CircularProgressIndicator(),
          const SizedBox(height: 24),
          Text(
            AppStrings.ankiParsing,
            style: const TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w600,
            ),
          ),
          if (parsing.message.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(
              parsing.message,
              style: TextStyle(
                color: TurnaTheme.textSecondaryColor(context),
                fontSize: 13,
              ),
            ),
          ],
          const SizedBox(height: 24),
          OutlinedButton.icon(
            onPressed: controller.cancel,
            icon: const Icon(Icons.close, size: 18),
            label: Text(AppStrings.commonCancel),
            style: OutlinedButton.styleFrom(
              foregroundColor: TurnaTheme.textSecondaryColor(context),
              side: BorderSide(
                color: TurnaTheme.textHintColor(context).withValues(alpha: 0.5),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildCommittingStep(
    AnkiImportController controller,
    AnkiImportCommitting committing,
  ) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          if (committing.progress > 0)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 60),
              child: LinearProgressIndicator(
                value: committing.progress,
                backgroundColor: TurnaTheme.brandTeal.withValues(alpha: 0.1),
                valueColor:
                    const AlwaysStoppedAnimation<Color>(TurnaTheme.brandTeal),
              ),
            )
          else
            const CircularProgressIndicator(),
          const SizedBox(height: 24),
          Text(
            committing.message.isEmpty
                ? AppStrings.ankiPreparingImport
                : committing.message,
            style: const TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 24),
          OutlinedButton.icon(
            onPressed: controller.cancel,
            icon: const Icon(Icons.close, size: 18),
            label: Text(AppStrings.commonCancel),
            style: OutlinedButton.styleFrom(
              foregroundColor: TurnaTheme.textSecondaryColor(context),
              side: BorderSide(
                color: TurnaTheme.textHintColor(context).withValues(alpha: 0.5),
              ),
            ),
          ),
        ],
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
    return OfficialAnkiImportPreview(
      preview: official,
      controller: controller,
      error: failureMessage,
      onOpenMapping: (schema) => unawaited(_openOfficialMapping(
        controller,
        schema,
      )),
    );
  }

  Future<void> _openOfficialMapping(
    AnkiImportController controller,
    OfficialAnkiProjectionSchema schema,
  ) async {
    final official = _officialPreviewOf(controller);
    if (official == null) return;
    final suggestion =
        official.suggestions[schema.notetypeId] ?? official.service.suggestFor(schema);
    await context.router.push(
      OfficialAnkiMappingRoute(
        notetypeName: schema.name,
        suggestion: suggestion,
        schema: schema,
        onConfirm: (next) {
          controller.confirmOfficialMapping(schema, next);
        },
        onSkip: () {
          controller.skipOfficialNotetype(schema);
        },
      ),
    );
  }

  OfficialAnkiImportPreviewModel? _officialPreviewOf(
    AnkiImportController controller,
  ) {
    final state = controller.state;
    final effective =
        state is AnkiImportFailed ? state.returnState : state;
    if (effective is AnkiImportPreviewing &&
        effective.preview is OfficialAnkiImportPreviewModel) {
      return effective.preview as OfficialAnkiImportPreviewModel;
    }
    return null;
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
      onViewDecks: () => unawaited(_viewDecks(controller)),
      onDone: () => context.router.maybePop(),
    );
  }

  /// "Start learning now": switch to the freshly-imported course and pop
  /// back to the Learn tab. This is the ONLY done action that switches
  /// the active course (plan 34 R1-4).
  Future<void> _startLearningNow(AnkiImportController controller) async {
    final importId = controllerCompletedImportId(controller);
    if (importId != null) {
      final courseProvider = context.read<CourseProvider>();
      final wire = wireKeyForImportId(controller, importId, courseProvider);
      if (wire != null) {
        await courseProvider.setCourseScope(wire);
      }
    }
    if (mounted) context.router.maybePop();
  }

  /// "View decks": open course management with the new course highlighted.
  /// The current course stays active.
  Future<void> _viewDecks(AnkiImportController controller) async {
    final importId = controllerCompletedImportId(controller);
    String? highlight;
    if (importId != null) {
      highlight = wireKeyForImportId(
        controller,
        importId,
        context.read<CourseProvider>(),
      );
    }
    await context.router.push(CourseManagementRoute(highlightWire: highlight));
  }

  String? controllerCompletedImportId(AnkiImportController controller) {
    final state = controller.state;
    if (state is AnkiImportCompleted) return state.summary.importId;
    if (state is AnkiImportFailed &&
        state.returnState is AnkiImportCompleted) {
      return (state.returnState as AnkiImportCompleted).summary.importId;
    }
    return null;
  }

  String? wireKeyForImportId(
    AnkiImportController controller,
    String id,
    CourseProvider courseProvider,
  ) {
    for (final entry in courseProvider.catalogEntries) {
      if (entry.legacyImportId == id || entry.officialSourceId == id) {
        return entry.wireKey;
      }
    }
    return null;
  }
}
