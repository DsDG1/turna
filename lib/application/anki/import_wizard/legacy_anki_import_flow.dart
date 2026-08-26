import 'package:turna/application/ai/engine/ai_engine_config.dart';
import 'package:turna/application/anki/anki_card_adapter.dart';
import 'package:turna/application/anki/anki_models.dart';
import 'package:turna/application/anki/legacy_anki_import_executor.dart';
import 'package:turna/application/anki/anki_organization_resolver.dart';
import 'package:turna/application/anki/anki_sample_deck.dart';
import 'package:turna/application/anki/import_wizard/anki_import_dependencies.dart';
import 'package:turna/application/anki/import_wizard/anki_import_wizard_state.dart';
import 'package:turna/application/anki/import_wizard/notetype_mapping_util.dart';
import 'package:turna/application/anki_official/import/anki_import_execution_plan.dart';

/// Legacy (parse → preview → LegacyAnkiImportExecutor) flow owner
/// (maintainability plan §10.4). Pure orchestration: no navigation, no
/// widget dependencies; the controller maps results onto wizard states.
class LegacyAnkiImportFlow {
  LegacyAnkiImportFlow(this._deps);

  final AnkiImportDependencies _deps;

  /// Parses an .apkg into a preview model. The recognition pipeline runs
  /// WITHOUT the AI engine (persisted + deterministic rules only).
  Future<LegacyAnkiImportPreviewModel> parseFile(
    String path, {
    required AnkiImportExecutionPlan plan,
    required void Function(double progress, String message) onProgress,
    required bool Function() isCancelled,
  }) async {
    final collection = await _deps.importer.parse(
      path,
      onProgress: onProgress,
      isCancelled: isCancelled,
    );
    return _preparePreview(
      collection,
      sourcePath: path,
      isSample: false,
      plan: plan,
    );
  }

  /// The in-memory sample deck keeps the Legacy haemostasis semantics
  /// (doc 34): no Dart apkg file, plan must be legacyOnly.
  Future<LegacyAnkiImportPreviewModel> loadSample(
    AnkiImportExecutionPlan plan,
  ) async {
    final collection = AnkiSampleDeck.build();
    return _preparePreview(
      collection,
      sourcePath: AnkiSampleDeck.sourcePath,
      isSample: true,
      plan: plan,
    );
  }

  Future<LegacyAnkiImportPreviewModel> _preparePreview(
    AnkiCollection collection, {
    required String sourcePath,
    required bool isSample,
    required AnkiImportExecutionPlan plan,
  }) async {
    // Build a complete local recognition result before showing the
    // preview. An empty API key deliberately disables the remote AI branch
    // while still running persisted rules, deterministic rules and the
    // labeled fallback.
    final recognitionResults =
        await _deps.recognitionPipelineFactory(engine: null).recognizeAll(
              config: const AiEngineConfig(apiKey: ''),
              notetypes: collection.notetypes,
              notes: collection.notes,
            );
    final mappings = {
      for (final entry in recognitionResults.entries)
        entry.key: canonicalizeMapping(entry.value.mapping),
    };

    // Run the unit/lesson organization scan once (O(notes)) — the preview
    // rebuilds read the cached result.
    const orgResolver = AnkiOrganizationResolver();
    final orgPreview = orgResolver.preview(
      notes: collection.notes,
      notetypes: collection.notetypes,
    );

    // Real collision report: same file imported before (hash match) → the
    // deterministic word ids make notes already in the SRS queue
    // "existing"; otherwise everything is new.
    final hash = collection.sourceHash;
    final existingImport = await _deps.findExistingImportByHash(hash);
    var existingCount = 0;
    if (existingImport != null) {
      final srsIds = _deps.srsProvider.state.keys.toSet();
      final existingNids = <int>{
        for (final card in collection.cards)
          if (srsIds.contains('anki-${existingImport.importId}-c${card.id}'))
            card.nid,
      };
      existingCount =
          collection.notes.where((n) => existingNids.contains(n.id)).length;
    }

    return LegacyAnkiImportPreviewModel(
      plan: plan,
      filePath: sourcePath,
      collection: collection,
      sourceHash: hash,
      isSample: isSample,
      mappings: mappings,
      recognitionResults: recognitionResults,
      organizationPreview: orgPreview,
      newCount: collection.notes.length - existingCount,
      existingCount: existingCount,
      existingImport: existingImport,
    );
  }

  /// Runs the Legacy executor with the frozen pick-time plan. Repeated
  /// calls are the controller's responsibility (single-flight).
  Future<LegacyAnkiImportExecutionResult> commit(
    LegacyAnkiImportPreviewModel preview, {
    required void Function(double progress, String message) onProgress,
    required bool Function() isCancelled,
  }) {
    final executor = _deps.legacyExecutorFactory();
    return executor.execute(
      LegacyAnkiImportRequest(
        collection: preview.collection,
        filePath: preview.filePath,
        sourceHash: preview.sourceHash,
        plan: preview.plan,
        strategy: preview.strategy,
        mappingOverrides: Map<int, NotetypeMapping>.unmodifiable(
          preview.mappings,
        ),
        smartGrouping: preview.smartGrouping,
        sectionBetaGrouping: preview.sectionBeta,
        liteThreshold: _deps.ankiLiteThreshold,
        importLearningProgress: preview.importLearningProgress,
        dailyNewLimit: _deps.dailyNewLimit,
        isSample: preview.isSample,
        previous: preview.existingImport,
        isCancelled: isCancelled,
        onProgress: (stage, progress, detail) {
          onProgress(progress, detail);
        },
      ),
    );
  }
}
