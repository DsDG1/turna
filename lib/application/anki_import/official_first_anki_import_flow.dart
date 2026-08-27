import 'package:turna/application/anki_import/anki_import_wizard_state.dart';
import 'package:turna/application/anki_import/anki_import_dependencies.dart';
import 'package:turna/application/anki_official/contract/official_anki_errors.dart';
import 'package:turna/application/anki_official/import/anki_import_execution_plan.dart';

/// Result of the official-first projection commit.
class OfficialFirstCommitResult {
  const OfficialFirstCommitResult({
    required this.summary,
    required this.needsMapping,
  });

  final AnkiImportSummary summary;
  final bool needsMapping;
}

/// Official-first (saga → schema preview → projection → publish) flow
/// owner (maintainability plan §10.4). Never touches the Legacy
/// NoteStore/SRS writers; the saga runs before any Turna-side write and a
/// failure produces zero Legacy rows.
class OfficialFirstAnkiImportFlow {
  OfficialFirstAnkiImportFlow(this._deps);

  final AnkiImportDependencies _deps;

  /// Saga + migration link + projection preview. No Dart apkg parse
  /// happens on this path.
  Future<OfficialAnkiImportPreviewModel> importThenPreview(
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

  /// Confirms the remaining suggested mappings (skipped notetypes stay
  /// skipped), projects the course tree and publishes placements.
  Future<OfficialFirstCommitResult> commit(
    OfficialAnkiImportPreviewModel preview,
  ) async {
    final service = preview.service;
    for (final schema in preview.schemas) {
      if (preview.skippedNotetypes.contains(schema.notetypeId)) continue;
      if (preview.confirmedNotetypes.contains(schema.notetypeId)) continue;
      final suggestion =
          preview.suggestions[schema.notetypeId] ?? service.suggestFor(schema);
      service.confirmMapping(schema: schema, suggestion: suggestion);
      preview.confirmedNotetypes.add(schema.notetypeId);
    }

    final result = await _deps.officialFirst.projectAndPublish(
      service: service,
      sourceId: preview.sourceId,
      sourceHash: preview.sourceHash,
    );
    if (result.needsMapping) {
      preview.needsMapping = true;
      return OfficialFirstCommitResult(
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
      throw OfficialAnkiException(
        code: OfficialAnkiErrorCode.invalidState,
        messageKey: 'official_anki.projection_failed',
        debugDetails: result.errorCode ?? 'unknown',
      );
    }

    final projection =
        await _deps.readOfficialProjectionSummary(preview.sourceId);
    return OfficialFirstCommitResult(
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
