import 'dart:async';

import 'package:path/path.dart' as p;
import 'package:turna/application/anki_import/anki_import_wizard_state.dart';
import 'package:turna/application/anki_official/contract/official_anki_errors.dart';
import 'package:turna/application/anki_official/import/anki_import_execution_plan.dart';
import 'package:turna/application/anki_official/import/official_anki_official_first_service.dart';
import 'package:turna/application/anki_official/import/official_anki_source_hasher.dart';
import 'package:turna/application/anki_official/official_anki_composition.dart';
import 'package:turna/application/anki_official/official_anki_paths.dart';
import 'package:turna/application/anki_official/projection/official_anki_mapping_suggestion.dart';
import 'package:turna/application/anki_official/storage/official_anki_database.dart';
import 'package:turna/application/anki_official/v2/official_anki_v2_import_service.dart';
import 'package:turna/data/course_database.dart';
import 'package:turna/l10n/app_strings.dart';

class OfficialFirstCommitResult {
  const OfficialFirstCommitResult({
    required this.summary,
    required this.needsMapping,
  });

  final AnkiImportSummary summary;
  final bool needsMapping;
}

/// Official-first saga → schema preview. No Dart apkg parse.
Future<OfficialAnkiImportPreviewModel> importOfficialThenPreview({
  required String path,
  required AnkiImportExecutionPlan plan,
  required OfficialAnkiOfficialFirstService officialFirst,
  required CourseDatabase course,
  required bool includeMedia,
  OfficialAnkiSourceDigest? digest,
}) async {
  if (!plan.isOfficialFirst) {
    throw const OfficialAnkiException(
      code: OfficialAnkiErrorCode.invalidState,
      messageKey: 'official_anki.flag_fail_closed',
      debugDetails: 'import_plan_missing',
    );
  }
  final preview = await officialFirst.importThenPreview(
    filePath: path,
    plan: plan,
    course: course,
    digest: digest,
    withMedia: includeMedia,
  );
  return OfficialAnkiImportPreviewModel(
    plan: plan,
    filePath: path,
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
  );
}

/// Writes live Collection, promotes staging mappings, then projects via v2.
Future<OfficialFirstCommitResult> commitOfficialPreview(
  OfficialAnkiImportPreviewModel preview, {
  required CourseDatabase course,
}) async {
  for (final schema in preview.schemas) {
    if (preview.skippedNotetypes.contains(schema.notetypeId)) continue;
    if (preview.confirmedNotetypes.contains(schema.notetypeId)) continue;
    preview.suggestions[schema.notetypeId] =
        preview.suggestions[schema.notetypeId] ??
            officialAnkiSuggestMapping(schema);
    preview.confirmedNotetypes.add(schema.notetypeId);
  }

  final catalog = OfficialAnkiCompositionRoot.readOnlyCatalog;
  final paths = OfficialAnkiCompositionRoot.locatorPaths;
  if (catalog != null && paths != null) {
    return _commitOfficialV2(preview, catalog, paths, course);
  }
  throw const OfficialAnkiException(
    code: OfficialAnkiErrorCode.capabilityMissing,
    messageKey: 'official_anki.catalog_missing',
  );
}

Future<OfficialFirstCommitResult> _commitOfficialV2(
  OfficialAnkiImportPreviewModel preview,
  OfficialAnkiDatabase catalog,
  OfficialAnkiPaths paths,
  CourseDatabase course,
) async {
  final result = await OfficialAnkiV2ImportService(
    catalog: catalog,
    paths: paths,
    course: course,
  ).commit(
    sourceId: preview.sourceId,
    packagePath: preview.filePath,
    displayName: p.basename(preview.filePath),
    suggestions: preview.suggestions,
    confirmedNotetypes: preview.confirmedNotetypes,
    skippedNotetypes: preview.skippedNotetypes,
    excludedDeckIds: {
      for (final deck in preview.decks)
        if (!preview.includedDeckIds.contains(deck.deckId)) deck.deckId,
    },
    includeMedia: preview.includeMedia,
  );
  return OfficialFirstCommitResult(
    summary: AnkiImportSummary(
      importId: preview.sourceId,
      sectionCount: result.sectionCount,
      lessonCount: result.lessonCount,
      cardCount: result.cardCount,
      wordEntryCount: result.cardCount,
      sourceCardCount: preview.cardCount,
      newNoteCount: result.newNoteCount,
      duplicateNoteCount: result.duplicateNoteCount,
      partCount: result.partCount,
      includeMedia: result.includeMedia,
    ),
    needsMapping: false,
  );
}

String ankiImportStageLabel(String raw, {required bool committing}) {
  switch (raw) {
    case 'extracting':
    case 'file':
    case 'media':
      return committing
          ? AppStrings.ankiProgressWriting
          : AppStrings.ankiProgressUnpack;
    case 'gathering':
      return AppStrings.ankiProgressReading;
    case 'notes':
      return committing
          ? AppStrings.ankiProgressWriting
          : AppStrings.ankiProgressRecognize;
    case 'idle':
    case 'course':
      return committing ? AppStrings.ankiProgressCourse : '';
    default:
      return raw;
  }
}

/// Polls engine latestProgress onto Parsing/Committing. Stops when [stale]
/// or the wizard leaves those steps.
Future<void> pollAnkiImportProgress({
  required int op,
  required bool Function(int op) stale,
  required AnkiImportWizardState Function() readState,
  required void Function(AnkiImportWizardState next) emit,
}) async {
  while (!stale(op)) {
    await Future<void>.delayed(const Duration(milliseconds: 700));
    if (stale(op)) return;
    final current = readState();
    final engine = switch (current) {
      AnkiImportParsing() =>
        OfficialAnkiCompositionRoot.stagingEngineFromSession(),
      AnkiImportCommitting() =>
        OfficialAnkiCompositionRoot.projectionEngineFromSession(),
      _ => null,
    };
    if (current is! AnkiImportParsing && current is! AnkiImportCommitting) {
      return;
    }
    if (engine == null) continue;
    try {
      final progress = await engine.latestProgress();
      if (stale(op)) return;
      final raw = progress.stage;
      if (raw.isEmpty) continue;
      final latest = readState();
      final committing = latest is AnkiImportCommitting;
      if (raw == 'idle' && !committing) continue;
      final label = ankiImportStageLabel(raw, committing: committing);
      if (label.isEmpty) continue;
      final shown = progress.current == null
          ? label
          : AppStrings.ankiProgressCount(label, progress.current!);
      if (latest is AnkiImportParsing) {
        emit(latest.copyWith(
          stage: shown,
          progressCurrent: progress.current,
          progressTotal: progress.total,
          clearProgress: true,
        ));
      } else if (latest is AnkiImportCommitting) {
        emit(latest.copyWith(
          stage: shown,
          progressCurrent: progress.current,
          progressTotal: progress.total,
          clearProgress: true,
        ));
      }
    } catch (_) {/* 进度是 best-effort——查询失败不影响主流程 */}
  }
}
