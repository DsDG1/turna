import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:turna/application/anki/anki_card_adapter.dart';
import 'package:turna/application/anki/anki_organization_resolver.dart';
import 'package:turna/application/anki/import_wizard/anki_import_view_helpers.dart';
import 'package:turna/application/anki/anki_deck_assembler.dart';
import 'package:turna/application/anki/anki_importer.dart';
import 'package:turna/application/anki/legacy_anki_import_executor.dart';
import 'package:turna/application/anki/card_recognition_pipeline.dart';
import 'package:turna/application/anki/import_wizard/anki_import_completion_coordinator.dart';
import 'package:turna/application/anki/import_wizard/anki_import_dependencies.dart';
import 'package:turna/application/anki/import_wizard/anki_import_wizard_state.dart';
import 'package:turna/application/anki/import_wizard/legacy_anki_import_flow.dart';
import 'package:turna/application/anki/import_wizard/notetype_mapping_util.dart';
import 'package:turna/application/anki/import_wizard/official_first_anki_import_flow.dart';
import 'package:turna/application/anki_official/contract/official_anki_dto.dart';
import 'package:turna/application/anki_official/contract/official_anki_errors.dart';
import 'package:turna/application/anki_official/import/anki_import_execution_plan.dart';
import 'package:turna/application/anki_official/official_anki_feature_flags.dart';
import 'package:turna/application/anki_official/projection/official_anki_projection_mapper.dart';
import 'package:turna/l10n/app_strings.dart';
import 'package:turna/utils/validated_file_picker.dart';

/// File extensions accepted by the Anki import wizard.
/// `.colpkg` is unsupported until an Official backend exists (doc 34 W4-08).
const List<String> kAnkiImportExtensions = ['apkg'];

/// Wizard state-machine owner (maintainability plan §10.1/§10.2).
///
/// The page renders [state] and forwards user intents here; every long
/// operation is single-flight and tagged with an operation generation, so
/// a stale async result from an abandoned pick can never overwrite the
/// user's next selection. Temp extraction dirs created by the active
/// operation are cleaned up on cancel/reset/dispose.
class AnkiImportController extends ChangeNotifier {
  AnkiImportController({required AnkiImportDependencies deps})
      : _deps = deps,
        legacyFlow = LegacyAnkiImportFlow(deps),
        officialFlow = OfficialFirstAnkiImportFlow(deps);

  final AnkiImportDependencies _deps;
  final LegacyAnkiImportFlow legacyFlow;
  final OfficialFirstAnkiImportFlow officialFlow;
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
  /// official-first saga or the Legacy parse. Unsupported / fail-closed
  /// plans produce zero sources and return to Selecting with the mapped
  /// error.
  Future<void> proceedWithPath(String path) async {
    final op = ++_operation;
    _cancelRequested = false;
    final plan = _deps.planFor(
      flags: OfficialAnkiFeatureFlags.current,
      isSample: false,
      filePath: path,
    );
    _parsingPlan = plan;
    _emit(
      AnkiImportParsing(
        isSample: false,
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
      case AnkiImportExecutionKind.legacyOnly:
        await _runLegacyParse(path, plan, op);
    }
  }

  /// The in-memory sample keeps the Legacy haemostasis semantics (doc 34).
  Future<void> loadSample() async {
    final op = ++_operation;
    _cancelRequested = false;
    final samplePlan = _deps.planFor(
      flags: OfficialAnkiFeatureFlags.current,
      isSample: true,
      filePath: 'sample.apkg',
    );
    _parsingPlan = samplePlan;
    if (samplePlan.kind != AnkiImportExecutionKind.legacyOnly) {
      _parsingPlan = null;
      _failToSelect(_humanizePlanFailure(samplePlan));
      return;
    }
    _emit(const AnkiImportParsing(isSample: true));
    try {
      final preview = await legacyFlow.loadSample(samplePlan);
      if (_stale(op)) return;
      _emit(AnkiImportPreviewing(preview: preview));
    } catch (error) {
      if (_stale(op)) return;
      _parsingPlan = null;
      _emit(AnkiImportFailed(
        message: AppStrings.ankiParseFailed(error),
        returnState: const AnkiImportSelecting(),
      ));
    }
  }

  Future<void> _runLegacyParse(
    String path,
    AnkiImportExecutionPlan plan,
    int op,
  ) async {
    try {
      final preview = await legacyFlow.parseFile(
        path,
        plan: plan,
        onProgress: (p, msg) {
          if (!_stale(op)) {
            _emit(( _state as AnkiImportParsing).copyWith(
              progress: p,
              message: msg,
            ));
          }
        },
        isCancelled: () => _cancelRequested,
      );
      if (_stale(op)) return;
      if (_cancelRequested) {
        _parsingPlan = null;
        _emit(const AnkiImportSelecting());
        return;
      }
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

  Future<void> _runOfficialFirst(
    String path,
    AnkiImportExecutionPlan plan,
    int op,
  ) async {
    try {
      final preview = await officialFlow.importThenPreview(path, plan: plan);
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

  void setStrategy(ImportStrategy value) {
    final preview = _legacyPreview;
    if (preview == null) return;
    preview.strategy = value;
    notifyListeners();
  }

  void setSmartGrouping(bool value) {
    final preview = _legacyPreview;
    if (preview == null) return;
    preview.smartGrouping = value;
    notifyListeners();
  }

  void setSectionBeta(bool value) {
    final preview = _legacyPreview;
    if (preview == null) return;
    preview.sectionBeta = value;
    // Re-run the O(notes) organization scan so the preview reflects the
    // section detections the toggle enables (off the build path).
    preview.organizationPreview = AnkiOrganizationResolver().preview(
      notes: preview.collection.notes,
      notetypes: preview.collection.notetypes,
      sectionBeta: value,
    );
    notifyListeners();
  }

  void setImportLearningProgress(bool value) {
    final preview = _legacyPreview;
    if (preview == null) return;
    preview.importLearningProgress = value;
    notifyListeners();
  }

  void toggleShowAllRecognition() {
    final legacy = _legacyPreview;
    if (legacy != null) {
      legacy.showAllRecognition = !legacy.showAllRecognition;
      notifyListeners();
      return;
    }
    final official = _officialPreview;
    if (official != null) {
      official.showAllRecognition = !official.showAllRecognition;
      notifyListeners();
    }
  }

  /// A user-confirmed mapping (from the editor dialog): written back into
  /// the preview and persisted as a reusable rule.
  Future<void> saveLegacyMapping(int mid, NotetypeMapping mapping) async {
    final preview = _legacyPreview;
    if (preview == null) return;
    preview.mappings[mid] = mapping;
    preview.recognitionResults[mid] = CardRecognitionResult(
      mapping: mapping,
      confidence: 1.0,
      source: CardRecognitionSource.persisted,
      evidence: '用户手动确认的映射（已保存为规则）',
    );
    notifyListeners();
    final notetype = preview.collection.notetypes[mid];
    if (notetype == null) return;
    unawaited(AnkiNotetypeRuleStore().save(
      NotetypeSignature.of(
        notetype,
        version: CardRecognitionPipeline.recognizerVersion,
      ).value,
      mapping,
    ));
  }

  /// AI notetype identification (optional; runs the recognition pipeline
  /// with the configured engine). Requires the engine config; returns
  /// false when the engine is not configured (the page shows the dialog).
  Future<bool> identifyWithAi() async {
    final preview = _legacyPreview;
    if (preview == null || preview.collection.notetypes.isEmpty) return false;
    final config = _deps.aiConfigHolder.config;
    if (!config.isComplete) return false;
    preview.isAiIdentifying = true;
    notifyListeners();
    final op = ++_operation;
    try {
      final engine = _deps.resolveAiEngine();
      final results = await _deps
          .recognitionPipelineFactory(engine: engine)
          .recognizeAll(
            config: config,
            notetypes: preview.collection.notetypes,
            notes: preview.collection.notes,
          );
      if (_stale(op)) return true;
      preview
        ..mappings = {
          for (final e in results.entries)
            e.key: canonicalizeMapping(e.value.mapping),
        }
        ..recognitionResults = results
        ..isAiIdentifying = false;
      notifyListeners();
    } catch (_) {
      if (_stale(op)) return true;
      preview.isAiIdentifying = false;
      notifyListeners();
    }
    return true;
  }

  void confirmOfficialMapping(
    OfficialAnkiProjectionSchema schema,
    OfficialAnkiMappingSuggestion suggestion,
  ) {
    final preview = _officialPreview;
    if (preview == null) return;
    preview.service.confirmMapping(schema: schema, suggestion: suggestion);
    preview.suggestions[schema.notetypeId] = suggestion;
    preview.confirmedNotetypes.add(schema.notetypeId);
    preview.skippedNotetypes.remove(schema.notetypeId);
    preview.needsMapping = false;
    notifyListeners();
  }

  void skipOfficialNotetype(OfficialAnkiProjectionSchema schema) {
    final preview = _officialPreview;
    if (preview == null) return;
    preview.service.skipNotetype(schema: schema);
    preview.skippedNotetypes.add(schema.notetypeId);
    preview.confirmedNotetypes.remove(schema.notetypeId);
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
    if (preview is LegacyAnkiImportPreviewModel &&
        _hasLegacyBlockingRecognition(preview)) {
      return;
    }
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
        case LegacyAnkiImportPreviewModel():
          final result = await legacyFlow.commit(
            preview,
            onProgress: (p, msg) {
              if (!_stale(op)) {
                _emit((_state as AnkiImportCommitting).copyWith(
                  progress: p,
                  message: msg,
                ));
              }
            },
            isCancelled: () => _cancelRequested,
          );
          if (_stale(op)) return;
          if (!result.noOp) {
            await completion.complete(
              courseProvider: _deps.courseProvider,
              importId: result.importId,
              summary: result.summary,
            );
          }
          if (_stale(op)) return;
          _finishCommit(preview, result.summary);
        case OfficialAnkiImportPreviewModel():
          final result = await officialFlow.commit(preview);
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
          _finishCommit(preview, result.summary);
      }
    } on AnkiImportCancelled {
      if (_stale(op)) return;
      _committingPlan = null;
      _emit(AnkiImportPreviewing(preview: preview));
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

  void _finishCommit(AnkiImportPreviewModel preview, AnkiImportSummary summary) {
    _committingPlan = null;
    _emit(AnkiImportCompleted(summary: summary));
    if (preview is LegacyAnkiImportPreviewModel) {
      unawaited(_persistRecognizedRules(preview));
    }
  }

  /// Cancel the active long operation. The executor observes
  /// [isCancelRequested]; parse cancel returns to Selecting, commit cancel
  /// returns to the preview.
  void cancel() {
    _cancelRequested = true;
    final current = _state;
    if (current is AnkiImportParsing) {
      _cleanupActiveCollection();
      _parsingPlan = null;
      _operation++;
      _emit(const AnkiImportSelecting());
    }
  }

  /// Discards the current preview and returns to Selecting, releasing the
  /// parse temp dir (maintainability plan §10.9).
  Future<void> reset() async {
    _operation++;
    _cancelRequested = true;
    _cleanupActiveCollection();
    _parsingPlan = null;
    _committingPlan = null;
    _emit(const AnkiImportSelecting());
  }

  /// Disposes heavy objects owned by the CURRENT operation only. Called
  /// from the page's dispose.
  Future<void> disposeAsync() async {
    _operation++;
    _cancelRequested = true;
    _cleanupActiveCollection();
    _disposed = true;
    dispose();
  }

  void _cleanupActiveCollection() {
    final preview = switch (_state) {
      AnkiImportPreviewing(:final preview) => preview,
      _ => null,
    };
    final mediaDir = preview is LegacyAnkiImportPreviewModel
        ? preview.collection.mediaDir
        : null;
    if (mediaDir != null && mediaDir.isNotEmpty) {
      AnkiImporter.cleanupExtractedDir(mediaDir);
    }
  }

  /// Persist the notetype rules for mappings the user accepted on import:
  /// AI verdicts and already-persisted rules (explicit edits save at edit
  /// time). Fallback results are never persisted.
  Future<void> _persistRecognizedRules(
    LegacyAnkiImportPreviewModel preview,
  ) async {
    if (preview.recognitionResults.isEmpty) return;
    final store = AnkiNotetypeRuleStore();
    for (final entry in preview.recognitionResults.entries) {
      final notetype = preview.collection.notetypes[entry.key];
      if (notetype == null) continue;
      final source = entry.value.source;
      if (source != CardRecognitionSource.ai &&
          source != CardRecognitionSource.persisted) {
        continue;
      }
      await store.save(
        NotetypeSignature.of(
          notetype,
          version: CardRecognitionPipeline.recognizerVersion,
        ).value,
        preview.mappings[entry.key] ?? entry.value.mapping,
      );
    }
  }

  // ─── Recognition attention (shared with the preview widgets) ────────

  bool _hasLegacyBlockingRecognition(LegacyAnkiImportPreviewModel preview) {
    return preview.collection.notetypes.entries.any(
      (entry) =>
          legacyRecognitionAttention(preview, entry.key, entry.value) ==
          ImportRecognitionAttention.blocking,
    );
  }

  bool _hasOfficialBlockingRecognition(OfficialAnkiImportPreviewModel preview) {
    return preview.schemas.any(
      (schema) =>
          officialRecognitionAttention(preview, schema) ==
          ImportRecognitionAttention.blocking,
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

  LegacyAnkiImportPreviewModel? get _legacyPreview =>
      _previewOf<LegacyAnkiImportPreviewModel>();

  OfficialAnkiImportPreviewModel? get _officialPreview =>
      _previewOf<OfficialAnkiImportPreviewModel>();

  bool _stale(int op) => _disposed || op != _operation;

  void _failToSelect(String message) => _emit(AnkiImportFailed(
        message: message,
        returnState: const AnkiImportSelecting(),
      ));

  String _humanizePlanFailure(AnkiImportExecutionPlan plan) =>
      plan.reason == 'colpkg_not_supported_until_official_backend'
          ? AppStrings.ankiColpkgUnsupported
          : AppStrings.ankiImportUnavailable(plan.reason);
}
