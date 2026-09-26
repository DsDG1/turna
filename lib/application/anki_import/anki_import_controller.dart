import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:turna/application/anki_import/anki_import_official_flow.dart';
import 'package:turna/application/anki_import/official_import_error_messages.dart';
import 'package:turna/application/anki_import/anki_import_completion_coordinator.dart';
import 'package:turna/application/anki_import/anki_import_dependencies.dart';
import 'package:turna/application/anki_import/anki_import_wizard_state.dart';
import 'package:turna/application/anki_import/recognition/official_recognition_triage.dart';
import 'package:turna/application/anki_official/contract/official_anki_dto.dart';
import 'package:turna/application/anki_official/contract/official_anki_errors.dart';
import 'package:turna/application/anki_official/import/anki_import_execution_plan.dart';
import 'package:turna/application/anki_official/anki_deck_manager.dart';
import 'package:turna/application/anki_official/import/official_anki_source_hasher.dart';
import 'package:turna/application/anki_official/lifecycle/official_anki_lifecycle_models.dart';
import 'package:turna/application/anki_official/official_anki_composition.dart';
import 'package:turna/application/anki_official/official_anki_feature_flags.dart';
import 'package:turna/application/anki_official/import/official_anki_import_saga.dart';
import 'package:turna/application/anki_official/storage/official_anki_import_attempt_dao.dart';
import 'package:turna/application/anki_official/storage/official_anki_source_dao.dart';
import 'package:turna/application/anki_official/projection/official_anki_mapping_suggestion.dart';
import 'package:turna/core/logger.dart';
import 'package:turna/di/injection.dart';
import 'package:turna/l10n/app_strings.dart';
import 'package:turna/service/remote_backup/remote_backup_busy_gate.dart';
import 'package:turna/utils/validated_file_picker.dart';

/// File extensions accepted by the Anki import wizard.
/// `.colpkg` is picked and routes to human guidance (doc 34 W4-08).
const List<String> kAnkiImportExtensions = ['apkg', 'colpkg'];

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

  /// Backup mutual-exclusion scope for the parse/commit work (plan P0).
  static const _activityScope = 'anki_import';

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
  bool _replacingExisting = false;
  bool includeMedia = true;
  OfficialAnkiSourceDigest? _pendingDigest;

  bool get isCancelRequested => _cancelRequested;

  void _emit(AnkiImportWizardState next) {
    if (_disposed) return;
    _state = next;
    notifyListeners();
  }

  /// Runs [body] inside the backup mutual-exclusion scope (plan P0): a
  /// running backup snapshot surfaces as a wizard failure via [onBlocked].
  Future<void> _withActivityScope(
    Future<void> Function() body, {
    required void Function(String message) onBlocked,
  }) =>
      runStudyActivityScope(_activityScope, body, onBlocked: onBlocked);

  // ─── Selection & parsing intents ────────────────────────────────────

  /// Opens the file picker; on a picked path continues with
  /// [proceedWithPath]. Picker failures surface on the select step.
  Future<void> pickFile() async {
    if (catalogHasUnfinishedOfficialImport()) {
      _failToSelect(unfinishedImportBlocksNewMessage());
      return;
    }
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
  Future<void> proceedWithPath(String path) =>
      _withActivityScope(() => _proceedWithPath(path),
          onBlocked: _failToSelect);

  Future<void> _proceedWithPath(String path) async {
    if (catalogHasUnfinishedOfficialImport()) {
      _failToSelect(unfinishedImportBlocksNewMessage());
      return;
    }
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
        if (!_replacingExisting) {
          try {
            final lookup = await _deps.officialFirst.lookupPackage(path);
            if (_stale(op)) return;
            _pendingDigest = lookup.digest;
            final active = lookup.active;
            if (active != null) {
              _parsingPlan = null;
              _emit(AnkiImportAlreadyImported(
                sourceId: active.sourceId,
                displayName: active.displayName,
                filePath: path,
              ));
              return;
            }
          } on OfficialAnkiException catch (error) {
            if (_stale(op)) return;
            _parsingPlan = null;
            _failToSelect(mapOfficialErrorToHuman(error));
            return;
          } catch (error) {
            if (_stale(op)) return;
            _parsingPlan = null;
            _failToSelect(mapGeneralErrorToHuman(error));
            return;
          }
        }
        _replacingExisting = false;
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
    unawaited(pollAnkiImportProgress(
      op: op,
      stale: _stale,
      readState: () => _state,
      emit: _emit,
    ));
    try {
      final digest = _pendingDigest;
      _pendingDigest = null;
      final preview = await importOfficialThenPreview(
        path: path,
        plan: plan,
        officialFirst: _deps.officialFirst,
        course: _deps.courseDatabase,
        includeMedia: includeMedia,
        digest: digest,
      );
      if (_stale(op)) return;
      _emit(AnkiImportPreviewing(preview: preview));
    } on OfficialAnkiException catch (error) {
      if (_stale(op)) return;
      _parsingPlan = null;
      _failToSelect(mapOfficialErrorToHuman(error));
    } catch (error) {
      if (_stale(op)) return;
      _parsingPlan = null;
      _failToSelect(
        catalogHasUnfinishedOfficialImport()
            ? unfinishedImportBlocksNewMessage()
            : mapGeneralErrorToHuman(error),
      );
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
    notifyListeners();
  }

  void setIncludeMedia(bool value) {
    includeMedia = value;
    final preview = _officialPreview;
    if (preview != null) {
      preview.includeMedia = value;
      notifyListeners();
    }
  }

  void applyUnconfirmedKinds(
    OfficialAnkiProjectionSchema schema,
    List<String> enabledKinds,
  ) {
    final preview = _officialPreview;
    if (preview == null) return;
    if (preview.confirmedNotetypes.contains(schema.notetypeId)) return;
    final current = preview.suggestions[schema.notetypeId] ??
        officialAnkiSuggestMapping(schema);
    preview.suggestions[schema.notetypeId] =
        current.copyWith(enabledKinds: enabledKinds);
    notifyListeners();
  }

  void setNotetypeStudyMode(
    OfficialAnkiProjectionSchema schema,
    List<String> enabledKinds,
  ) {
    final preview = _officialPreview;
    if (preview == null) return;
    final current = preview.suggestions[schema.notetypeId] ??
        officialAnkiSuggestMapping(schema);
    confirmOfficialMapping(
      schema,
      current.copyWith(
        enabledKinds: enabledKinds,
        status: OfficialAnkiMappingStatus.manual,
        userConfirmed: true,
      ),
    );
  }

  void toggleDeckIncluded(int deckId, bool included) {
    final preview = _officialPreview;
    if (preview == null) return;
    if (included) {
      preview.includedDeckIds.add(deckId);
    } else {
      preview.includedDeckIds.remove(deckId);
    }
    notifyListeners();
  }

  Future<void> loadSamples(OfficialAnkiProjectionSchema schema) async {
    final preview = _officialPreview;
    if (preview == null || schema.samples.isNotEmpty) return;
    final engine = OfficialAnkiCompositionRoot.stagingEngineFromSession();
    if (engine == null) return;
    final loaded = await engine.getProjectionSchemas(
      notetypeIds: [schema.notetypeId],
      includeSamples: true,
      sampleLimit: 30,
    );
    if (loaded.isEmpty) return;
    final index = preview.schemas.indexWhere(
      (item) => item.notetypeId == schema.notetypeId,
    );
    if (index < 0) return;
    preview.schemas[index] = loaded.first;
    notifyListeners();
  }

  Future<void> openExistingCourse() async {
    final current = _state;
    if (current is! AnkiImportAlreadyImported) return;
    await completion.complete(
      courseProvider: _deps.courseProvider,
      importId: current.sourceId,
      summary: AnkiImportSummary(
        importId: current.sourceId,
        sectionCount: 0,
        lessonCount: 0,
        cardCount: 0,
        wordEntryCount: 0,
      ),
    );
    _emit(AnkiImportCompleted(
      summary: AnkiImportSummary(
        importId: current.sourceId,
        sectionCount: 0,
        lessonCount: 0,
        cardCount: 0,
        wordEntryCount: 0,
      ),
    ));
  }

  Future<void> replaceExisting() async {
    final current = _state;
    if (current is! AnkiImportAlreadyImported) return;
    if (getIt.isRegistered<AnkiDeckManager>()) {
      await getIt<AnkiDeckManager>().uninstall(current.sourceId);
    }
    _replacingExisting = true;
    await proceedWithPath(current.filePath);
  }

  Future<void> continuePending(OfficialAnkiPendingImport item) =>
      _withActivityScope(() => _continuePending(item),
          onBlocked: _failToSelect);

  Future<void> _continuePending(OfficialAnkiPendingImport item) async {
    final op = ++_operation;
    _cancelRequested = false;
    _emit(AnkiImportParsing(message: AppStrings.ankiImportingOfficialFirst));
    final plan = _deps.planFor(
      flags: OfficialAnkiFeatureFlags.current,
      filePath: item.packagePath ?? 'resume.apkg',
    );
    _parsingPlan = plan;
    try {
      final preview = await _deps.officialFirst.resumePreview(
        sourceId: item.sourceId,
        plan: plan,
        course: _deps.courseDatabase,
      );
      if (_stale(op)) return;
      if (preview == null) {
        final path = item.packagePath;
        if (path != null && path.isNotEmpty) {
          await proceedWithPath(path);
          return;
        }
        _failToSelect(AppStrings.ankiPendingReparse);
        return;
      }
      _emit(AnkiImportPreviewing(
        preview: OfficialAnkiImportPreviewModel(
          plan: plan,
          filePath: item.packagePath ?? '',
          sourceId: preview.sourceId,
          sourceHash: preview.sourceHash,
          cardCount: preview.cardCount,
          noteCount: preview.noteCount,
          decks: preview.decks,
          cardCountByDeck: preview.cardCountByDeck,
          notetypeByDeck: preview.notetypeByDeck,
          includedDeckIds: {for (final deck in preview.decks) deck.deckId},
          includeMedia: includeMedia,
          schemas: preview.schemas,
          suggestions: preview.suggestions,
        ),
      ));
    } catch (error) {
      if (_stale(op)) return;
      _failToSelect(mapGeneralErrorToHuman(error));
    }
  }

  void skipOfficialNotetype(OfficialAnkiProjectionSchema schema) {
    final preview = _officialPreview;
    if (preview == null) return;
    preview.skippedNotetypes.add(schema.notetypeId);
    preview.confirmedNotetypes.remove(schema.notetypeId);
    refreshOfficialPreviewNeedsMapping(preview);
    notifyListeners();
  }

  // ─── Commit / cancel / reset ────────────────────────────────────────

  /// Commits the active preview. Single-flight: repeated calls while a
  /// commit is running are no-ops (maintainability plan §10.9).
  Future<void> commit() {
    final current = _state;
    if (current is! AnkiImportPreviewing) return _commit();
    return _withActivityScope(
      _commit,
      onBlocked: (message) =>
          _emit(AnkiImportFailed(message: message, returnState: current)),
    );
  }

  Future<void> _commit() async {
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
    unawaited(pollAnkiImportProgress(
      op: op,
      stale: _stale,
      readState: () => _state,
      emit: _emit,
    ));
    try {
      switch (preview) {
        case OfficialAnkiImportPreviewModel():
          final result = await commitOfficialPreview(
            preview,
            course: _deps.courseDatabase,
          );
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
      logger.w('[AnkiImport] commit failed: $error');
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
    // A2：commit 已进入 live 写——台账 abandon 会删掉正在提交的
    // source/attempt，而 importPackage 仍在跑。saga 侧（cancelActive 的
    // phase 过滤）同样跳过 committing 行，双保险。
    if (!_commitInFlight) {
      unawaited(_cancelStagingSaga());
    }
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
        logger.w('[AnkiImport] staging cancel: $suppressed');
      }
      return;
    }
    await OfficialAnkiImportSaga(
      sources: OfficialAnkiSourceDao(catalog),
      attempts: OfficialAnkiImportAttemptDao(catalog),
      paths: paths,
    ).cancelActive();
  }

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

  bool _stale(int op) => _disposed || op != _operation;

  void _failToSelect(String message) => _emit(AnkiImportFailed(
        message: message,
        returnState: const AnkiImportSelecting(),
      ));

  /// After discarding an interrupted import, drop the select-step failure.
  void clearSelectFailure() {
    final current = _state;
    if (current is AnkiImportFailed &&
        current.returnState is AnkiImportSelecting) {
      _emit(const AnkiImportSelecting());
    }
  }

  String _humanizePlanFailure(AnkiImportExecutionPlan plan) =>
      plan.reason == 'colpkg_not_supported_until_official_backend'
          ? AppStrings.ankiColpkgUnsupported
          : AppStrings.ankiImportUnavailable(plan.reason);
}
