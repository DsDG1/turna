import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:turna/application/anki_import/official_import_error_messages.dart';
import 'package:turna/application/anki_import/anki_import_completion_coordinator.dart';
import 'package:turna/application/anki_import/anki_import_dependencies.dart';
import 'package:turna/application/anki_import/anki_import_wizard_state.dart';
import 'package:turna/application/anki_import/recognition/official_recognition_triage.dart';
import 'package:turna/application/anki_official/contract/official_anki_dto.dart';
import 'package:turna/application/anki_official/contract/official_anki_errors.dart';
import 'package:turna/application/anki_official/import/anki_import_execution_plan.dart';
import 'package:turna/application/anki_official/lifecycle/official_anki_repair_executor.dart';
import 'package:turna/application/anki_official/lifecycle/official_anki_source_metadata_dao.dart';
import 'package:turna/application/anki_official/official_anki_composition.dart';
import 'package:turna/application/anki_official/official_anki_feature_flags.dart';
import 'package:turna/application/anki_official/import/official_anki_import_saga.dart';
import 'package:turna/application/anki_official/import/official_anki_import_state.dart';
import 'package:turna/application/anki_official/import/official_anki_import_orchestrator.dart';
import 'package:turna/application/anki_official/storage/official_anki_import_attempt_dao.dart';
import 'package:turna/application/anki_official/storage/official_anki_source_dao.dart';
import 'package:turna/application/anki_official/projection/official_anki_mapping_suggestion.dart';
import 'package:turna/l10n/app_strings.dart';
import 'package:turna/utils/validated_file_picker.dart';

/// File extensions accepted by the Anki import wizard.
/// `.colpkg` is unsupported until an Official backend exists (doc 34 W4-08).
const List<String> kAnkiImportExtensions = ['apkg'];

class _OfficialFirstCommitResult {
  const _OfficialFirstCommitResult({
    required this.summary,
    required this.needsMapping,
  });

  final AnkiImportSummary summary;
  final bool needsMapping;
}

/// Wizard state-machine owner (maintainability plan §10.1/§10.2).
///
/// The page renders [state] and forwards user intents here; every long
/// operation is single-flight and tagged with an operation generation, so
/// a stale async result from an abandoned pick can never overwrite the
/// user's next selection.
class AnkiImportController extends ChangeNotifier {
  AnkiImportController({required AnkiImportDependencies deps}) : _deps = deps;

  final AnkiImportDependencies _deps;
  final completion = const AnkiImportCompletionCoordinator();

  AnkiImportWizardState _state = const AnkiImportSelecting();
  AnkiImportWizardState get state => _state;

  /// The pick-time plan frozen for the whole flow (doc 34 W0-03). Null
  /// outside parse/preview/commit.
  AnkiImportExecutionPlan? get plan => switch (_state) {
        AnkiImportPreviewing(:final preview) => preview.plan,
        AnkiImportFailed(:final returnState) => switch (returnState) {
            AnkiImportPreviewing(:final preview) => preview.plan,
            _ => null,
          },
        AnkiImportParsing() => _parsingPlan,
        AnkiImportCommitting() => _committingPlan,
        _ => null,
      };
  AnkiImportExecutionPlan? _parsingPlan;
  AnkiImportExecutionPlan? _committingPlan;

  int _operation = 0;
  bool _cancelRequested = false;
  bool _commitInFlight = false;
  bool _disposed = false;

  bool get isCancelRequested => _cancelRequested;

  void _emit(AnkiImportWizardState next) {
    if (_disposed) return;
    _state = next;
    notifyListeners();
  }

  // ─── Selection & parsing intents ────────────────────────────────────

  /// Opens the file picker; on a picked path continues with
  /// [proceedWithPath]. Picker failures surface on the select step.
  Future<void> pickFile() async {
    final String? path;
    try {
      path = await _deps.pickFilePath(
        allowedExtensions: kAnkiImportExtensions,
        dialogTitle: AppStrings.ankiImportDialogTitle,
      );
    } on ValidatedFilePickerInvalidExtension {
      _failToSelect(AppStrings.ankiPickFileError);
      return;
    } catch (error) {
      _failToSelect(AppStrings.ankiPickFileFailed(error));
      return;
    }
    if (path == null || path.isEmpty || _disposed) return;
    await proceedWithPath(path);
  }

  /// Entry for a concrete path (picker or tests). Computes the ONE
  /// atomic plan for the whole import (doc 34 W0) and dispatches to the
  /// official-first saga. Unsupported / fail-closed plans produce zero
  /// sources and return to Selecting with the mapped error.
  Future<void> proceedWithPath(String path) async {
    final op = ++_operation;
    _cancelRequested = false;
    OfficialAnkiCompositionRoot.stagingDiscardRequested = false;
    final plan = _deps.planFor(
      flags: OfficialAnkiFeatureFlags.current,
      filePath: path,
    );
    _parsingPlan = plan;
    _emit(
      AnkiImportParsing(
        message: plan.kind == AnkiImportExecutionKind.officialFirst
            ? AppStrings.ankiImportingOfficialFirst
            : '',
      ),
    );
    switch (plan.kind) {
      case AnkiImportExecutionKind.officialFirst:
        await _runOfficialFirst(path, plan, op);
      case AnkiImportExecutionKind.failClosed:
      case AnkiImportExecutionKind.unsupported:
        _parsingPlan = null;
        _failToSelect(_humanizePlanFailure(plan));
    }
  }

  Future<void> _runOfficialFirst(
    String path,
    AnkiImportExecutionPlan plan,
    int op,
  ) async {
    try {
      final preview = await _importThenPreview(path, plan: plan);
      if (_stale(op)) return;
      _emit(AnkiImportPreviewing(preview: preview));
    } on OfficialAnkiException catch (error) {
      if (_stale(op)) return;
      _parsingPlan = null;
      _failToSelect(mapOfficialErrorToHuman(error));
    } catch (error) {
      if (_stale(op)) return;
      _parsingPlan = null;
      _failToSelect(mapGeneralErrorToHuman(error));
    }
  }

  // ─── Preview editing intents ────────────────────────────────────────

  void toggleShowAllRecognition() {
    final official = _officialPreview;
    if (official != null) {
      official.showAllRecognition = !official.showAllRecognition;
      notifyListeners();
    }
  }

  void confirmOfficialMapping(
    OfficialAnkiProjectionSchema schema,
    OfficialAnkiMappingSuggestion suggestion,
  ) {
    final preview = _officialPreview;
    if (preview == null) return;
    preview.suggestions[schema.notetypeId] = suggestion;
    preview.confirmedNotetypes.add(schema.notetypeId);
    preview.skippedNotetypes.remove(schema.notetypeId);
    refreshOfficialPreviewNeedsMapping(preview);
    _persistStagingMappings(preview);
    notifyListeners();
  }

  void skipOfficialNotetype(OfficialAnkiProjectionSchema schema) {
    final preview = _officialPreview;
    if (preview == null) return;
    preview.skippedNotetypes.add(schema.notetypeId);
    preview.confirmedNotetypes.remove(schema.notetypeId);
    refreshOfficialPreviewNeedsMapping(preview);
    _persistStagingMappings(preview);
    notifyListeners();
  }

  // ─── Commit / cancel / reset ────────────────────────────────────────

  /// Commits the active preview. Single-flight: repeated calls while a
  /// commit is running are no-ops (maintainability plan §10.9).
  Future<void> commit() async {
    if (_commitInFlight) return;
    final current = _state;
    if (current is! AnkiImportPreviewing) return;
    final preview = current.preview;
    if (preview is OfficialAnkiImportPreviewModel &&
        _hasOfficialBlockingRecognition(preview)) {
      preview.needsMapping = true;
      notifyListeners();
      return;
    }

    _commitInFlight = true;
    _cancelRequested = false;
    _committingPlan = preview.plan;
    final op = ++_operation;
    _emit(AnkiImportCommitting(
      message: preview is OfficialAnkiImportPreviewModel
          ? AppStrings.ankiAssemblingCourse
          : AppStrings.ankiPreparingImport,
    ));
    try {
      switch (preview) {
        case OfficialAnkiImportPreviewModel():
          final result = await _commitOfficial(preview);
          if (_stale(op)) return;
          if (result.needsMapping) {
            _committingPlan = null;
            _emit(AnkiImportPreviewing(preview: preview));
            return;
          }
          await completion.complete(
            courseProvider: _deps.courseProvider,
            importId: preview.sourceId,
            summary: result.summary,
          );
          if (_stale(op)) return;
          _finishCommit(result.summary);
      }
    } on OfficialAnkiException catch (error) {
      if (_stale(op)) return;
      _committingPlan = null;
      _emit(AnkiImportFailed(
        message: mapOfficialErrorToHuman(error),
        returnState: AnkiImportPreviewing(preview: preview),
      ));
    } catch (error) {
      if (_stale(op)) return;
      _committingPlan = null;
      debugPrint('[AnkiImport] commit failed: $error');
      _emit(AnkiImportFailed(
        message: AppStrings.ankiImportFailed(error),
        returnState: AnkiImportPreviewing(preview: preview),
      ));
    } finally {
      _commitInFlight = false;
    }
  }

  void _finishCommit(AnkiImportSummary summary) {
    _committingPlan = null;
    _emit(AnkiImportCompleted(summary: summary));
  }

  /// Cancel the active long operation. Persist discard intent and ask the
  /// staging saga to abort; the live Collection is not touched in P1.
  void cancel() {
    _cancelRequested = true;
    OfficialAnkiCompositionRoot.stagingDiscardRequested = true;
    unawaited(OfficialAnkiCompositionRoot.stagingEngineFromSession()?.cancel());
    unawaited(_cancelStagingSaga());
    final current = _state;
    if (current is AnkiImportParsing) {
      _parsingPlan = null;
      _operation++;
      _emit(const AnkiImportSelecting());
    }
  }

  /// Discards the current preview and returns to Selecting.
  Future<void> reset() async {
    _operation++;
    _cancelRequested = true;
    OfficialAnkiCompositionRoot.stagingDiscardRequested = true;
    unawaited(OfficialAnkiCompositionRoot.stagingEngineFromSession()?.cancel());
    await _cancelStagingSaga();
    _parsingPlan = null;
    _committingPlan = null;
    _emit(const AnkiImportSelecting());
  }

  /// Unsubscribes the page. Does not discard an in-flight saga.
  Future<void> disposeAsync() async {
    _operation++;
    _disposed = true;
    dispose();
  }

  Future<void> _cancelStagingSaga() async {
    final catalog = OfficialAnkiCompositionRoot.readOnlyCatalog;
    final paths = OfficialAnkiCompositionRoot.locatorPaths;
    if (catalog == null || paths == null) {
      try {
        await OfficialAnkiCompositionRoot.stagingEngineFromSession()?.cancel();
      } catch (suppressed) {
        debugPrint('[AnkiImport] staging cancel: $suppressed');
      }
      return;
    }
    await OfficialAnkiImportSaga(
      sources: OfficialAnkiSourceDao(catalog),
      attempts: OfficialAnkiImportAttemptDao(catalog),
      paths: paths,
    ).cancelActive();
  }

  // Kept for pre-P1 unfinished live imports; staging cancel uses
  // OfficialAnkiImportSaga.cancelActive instead.
  // ignore: unused_element
  Future<void> _discardDurable(String sourceId) async {
    final catalog = OfficialAnkiCompositionRoot.readOnlyCatalog;
    final engine = OfficialAnkiCompositionRoot.engine;
    final paths = OfficialAnkiCompositionRoot.locatorPaths;
    if (catalog == null || engine == null || paths == null) return;
    final attempts = OfficialAnkiImportAttemptDao(catalog);
    final unfinished = attempts
        .unfinished()
        .where((row) => row.sourceId == sourceId);
    if (unfinished.isEmpty) return;
    final orch = OfficialAnkiImportOrchestrator(
      engine: engine,
      sources: OfficialAnkiSourceDao(catalog),
      attempts: attempts,
      paths: paths,
    );
    await OfficialAnkiImportSagaCoordinator(orch)
        .requestDiscard(unfinished.first.attemptId);
  }

  // ─── Recognition triage (shared with the preview widgets) ───────────

  bool _hasOfficialBlockingRecognition(OfficialAnkiImportPreviewModel preview) {
    return preview.schemas.any(
      (schema) => officialRecognitionTriage(preview, schema).blocking,
    );
  }

  // ─── Helpers ────────────────────────────────────────────────────────

  /// The active preview of type [T], also visible through a Failed
  /// state's return state.
  T? _previewOf<T extends AnkiImportPreviewModel>() {
    for (final candidate in [
      if (_state is AnkiImportPreviewing)
        (_state as AnkiImportPreviewing).preview,
      if (_state is AnkiImportFailed &&
          (_state as AnkiImportFailed).returnState is AnkiImportPreviewing)
        ((_state as AnkiImportFailed).returnState as AnkiImportPreviewing)
            .preview,
    ]) {
      if (candidate is T) return candidate;
    }
    return null;
  }

  OfficialAnkiImportPreviewModel? get _officialPreview =>
      _previewOf<OfficialAnkiImportPreviewModel>();

  void _persistStagingMappings(OfficialAnkiImportPreviewModel preview) {
    try {
      final catalog = OfficialAnkiCompositionRoot.readOnlyCatalog;
      if (catalog == null) return;
      final unfinished = OfficialAnkiImportAttemptDao(catalog)
          .unfinished()
          .where((row) => row.sourceId == preview.sourceId);
      if (unfinished.isEmpty) return;
      final stagingPath = unfinished.first.stagingPath;
      if (stagingPath == null || stagingPath.isEmpty) return;
      final dir = Directory(stagingPath);
      if (!dir.existsSync()) return;
      File('${dir.path}/mapping.json').writeAsStringSync(
        jsonEncode({
          'confirmed': preview.confirmedNotetypes.toList(),
          'skipped': preview.skippedNotetypes.toList(),
          'suggestions': {
            for (final entry in preview.suggestions.entries)
              '${entry.key}': entry.value.toJson(),
          },
        }),
      );
    } catch (suppressed) {
      debugPrint('[AnkiImport] staging mapping.json: $suppressed');
    }
  }

  bool _stale(int op) => _disposed || op != _operation;

  void _failToSelect(String message) => _emit(AnkiImportFailed(
        message: message,
        returnState: const AnkiImportSelecting(),
      ));

  String _humanizePlanFailure(AnkiImportExecutionPlan plan) =>
      plan.reason == 'colpkg_not_supported_until_official_backend'
          ? AppStrings.ankiColpkgUnsupported
          : AppStrings.ankiImportUnavailable(plan.reason);

  /// Official-first saga → schema preview. No Dart apkg parse.
  Future<OfficialAnkiImportPreviewModel> _importThenPreview(
    String path, {
    required AnkiImportExecutionPlan plan,
  }) async {
    if (!plan.isOfficialFirst) {
      throw const OfficialAnkiException(
        code: OfficialAnkiErrorCode.invalidState,
        messageKey: 'official_anki.flag_fail_closed',
        debugDetails: 'import_plan_missing',
      );
    }
    final preview = await _deps.officialFirst.importThenPreview(
      filePath: path,
      plan: plan,
      course: _deps.courseDatabase,
    );
    return OfficialAnkiImportPreviewModel(
      plan: plan,
      filePath: path,
      sourceId: preview.sourceId,
      sourceHash: preview.sourceHash,
      cardCount: preview.cardCount,
      noteCount: preview.noteCount,
      decks: preview.decks,
      schemas: preview.schemas,
      suggestions: preview.suggestions,
      service: preview.service,
    );
  }

  /// Writes live Collection, promotes staging mappings, then projects.
  Future<_OfficialFirstCommitResult> _commitOfficial(
    OfficialAnkiImportPreviewModel preview,
  ) async {
    final service = preview.service;
    for (final schema in preview.schemas) {
      if (preview.skippedNotetypes.contains(schema.notetypeId)) continue;
      if (preview.confirmedNotetypes.contains(schema.notetypeId)) continue;
      preview.suggestions[schema.notetypeId] =
          preview.suggestions[schema.notetypeId] ?? service.suggestFor(schema);
      preview.confirmedNotetypes.add(schema.notetypeId);
    }

    final catalog = OfficialAnkiCompositionRoot.readOnlyCatalog;
    final paths = OfficialAnkiCompositionRoot.locatorPaths;
    OfficialAnkiImportSaga? saga;
    OfficialAnkiImportResult? imported;
    if (catalog != null && paths != null) {
      saga = OfficialAnkiImportSaga(
        sources: OfficialAnkiSourceDao(catalog),
        attempts: OfficialAnkiImportAttemptDao(catalog),
        paths: paths,
      );
      imported = await saga.commitLive(
        sourceId: preview.sourceId,
        packagePath: preview.filePath,
        projection: service,
        suggestions: preview.suggestions,
        confirmedNotetypes: preview.confirmedNotetypes,
        skippedNotetypes: preview.skippedNotetypes,
      );
      if (imported.alreadyImported) {
        await saga.finishCommit(
          sourceId: imported.sourceId,
          attemptId: imported.attemptId,
          published: true,
        );
        return _OfficialFirstCommitResult(
          summary: AnkiImportSummary(
            importId: imported.sourceId,
            sectionCount: 0,
            unitCount: 0,
            lessonCount: 0,
            cardCount: imported.cardCount,
            wordEntryCount: imported.cardCount,
            sourceCardCount: imported.cardCount,
          ),
          needsMapping: false,
        );
      }
    }

    var notetypeIds = preview.schemas.map((s) => s.notetypeId).toList();
    if (catalog != null) {
      final fromReceipt =
          OfficialAnkiSourceMetadataDao(catalog).notetypeIds(preview.sourceId);
      if (fromReceipt.isNotEmpty) notetypeIds = fromReceipt;
    }
    final result = await _deps.officialFirst.projectAndPublish(
      service: service,
      sourceId: preview.sourceId,
      sourceHash: preview.sourceHash,
      notetypeIds: notetypeIds,
    );
    if (result.needsMapping) {
      preview.needsMapping = true;
      await saga?.finishCommit(
        sourceId: preview.sourceId,
        attemptId: imported?.attemptId ?? preview.sourceId,
        published: false,
      );
      return _OfficialFirstCommitResult(
        summary: AnkiImportSummary(
          importId: preview.sourceId,
          sectionCount: 0,
          unitCount: 0,
          lessonCount: 0,
          cardCount: 0,
          wordEntryCount: 0,
        ),
        needsMapping: true,
      );
    }
    if (result.failed) {
      await saga?.finishCommit(
        sourceId: preview.sourceId,
        attemptId: imported?.attemptId ?? preview.sourceId,
        published: false,
      );
      throw OfficialAnkiException(
        code: OfficialAnkiErrorCode.invalidState,
        messageKey: 'official_anki.projection_failed',
        debugDetails: result.errorCode ?? 'unknown',
      );
    }

    await saga?.finishCommit(
      sourceId: preview.sourceId,
      attemptId: imported?.attemptId ?? preview.sourceId,
      published: true,
    );
    final projection =
        await _deps.readOfficialProjectionSummary(preview.sourceId);
    return _OfficialFirstCommitResult(
      summary: AnkiImportSummary(
        importId: preview.sourceId,
        sectionCount: projection.sectionIds.length,
        unitCount: 0,
        lessonCount: projection.lessonCount,
        cardCount: result.itemCount,
        wordEntryCount: result.itemCount,
        sourceCardCount: preview.cardCount,
      ),
      needsMapping: false,
    );
  }
}
