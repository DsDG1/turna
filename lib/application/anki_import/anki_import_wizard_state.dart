import 'package:turna/application/anki_official/contract/official_anki_dto.dart';
import 'package:turna/application/anki_official/import/anki_import_execution_plan.dart';
import 'package:turna/application/anki_official/projection/official_anki_mapping_suggestion.dart';
import 'package:turna/application/anki_official/projection/official_anki_projection_service.dart';

/// Summary of a completed Anki import (legacy parser-era shape retained:
/// the official flow fills the same fields for the done step).
/// Doc 39 P5: the ten Legacy-parser-era fields (structuredCardCount,
/// fidelityCardCount, unknownTemplateCount, suspendedCardCount,
/// buriedCardCount, hasScheduling, hasReviewHistory, missingMediaCount,
/// failedMediaCount, platformDowngrades) were deleted — the official-first
/// flow never filled them, so every read was a constant default. The
/// zero-caller copyWith went with them.
class AnkiImportSummary {
  final String importId;
  final int sectionCount;
  final int unitCount;
  final int lessonCount;
  final int cardCount;
  final int wordEntryCount;
  final int sourceCardCount;

  const AnkiImportSummary({
    required this.importId,
    required this.sectionCount,
    required this.unitCount,
    required this.lessonCount,
    required this.cardCount,
    required this.wordEntryCount,
    this.sourceCardCount = 0,
  });
}

/// Sealed wizard state (maintainability plan §10.3). Every step is a
/// distinct type — invalid field combinations cannot be constructed, and
/// the page never infers the active flow from a nullable field.
sealed class AnkiImportWizardState {
  const AnkiImportWizardState();

  /// 0=select, 1=working, 2=preview, 3=committing, 4=done — kept only for
  /// the stepper UI.
  int get step;
}

final class AnkiImportSelecting extends AnkiImportWizardState {
  const AnkiImportSelecting({this.error});

  final String? error;

  @override
  int get step => 0;
}

/// Running the official-first saga. Exactly one long operation may be
/// active; a cancel request is visible to the flow through the
/// controller.
final class AnkiImportParsing extends AnkiImportWizardState {
  const AnkiImportParsing({this.message = ''});

  final String message;

  @override
  int get step => 1;

  // Doc 39 P5: the never-non-zero `progress` field went away — the
  // official flow never reports fractional progress.

  AnkiImportParsing copyWith({String? message}) => AnkiImportParsing(
        message: message ?? this.message,
      );
}

/// Committing the official flow. Constructing this twice from the same
/// preview is impossible at the API level (commit is single-flight).
final class AnkiImportCommitting extends AnkiImportWizardState {
  const AnkiImportCommitting({this.message = ''});

  final String message;

  @override
  int get step => 3;

  AnkiImportCommitting copyWith({String? message}) => AnkiImportCommitting(
        message: message ?? this.message,
      );
}

final class AnkiImportPreviewing extends AnkiImportWizardState {
  const AnkiImportPreviewing({required this.preview});

  final AnkiImportPreviewModel preview;

  @override
  int get step => 2;
}

final class AnkiImportCompleted extends AnkiImportWizardState {
  const AnkiImportCompleted({required this.summary});

  /// Unified summary — the page never assembles it ad hoc.
  final AnkiImportSummary summary;

  @override
  int get step => 4;
}

/// A structured failure with the state the wizard returns to. The page
/// renders the return state's UI plus the error surface (the legacy page
/// swapped `_error` + step; this encodes the same outcome in the type).
final class AnkiImportFailed extends AnkiImportWizardState {
  const AnkiImportFailed({required this.message, required this.returnState});

  final String message;
  final AnkiImportWizardState returnState;

  @override
  int get step => returnState.step;
}

/// Preview payload (doc 35 L1: the Legacy parser variant is deleted; the
/// official-first saga is the only flow).
sealed class AnkiImportPreviewModel {
  const AnkiImportPreviewModel();

  /// The pick-time execution plan stays frozen for the whole flow
  /// (doc 34 W0-03): later stages never re-read flags.
  AnkiImportExecutionPlan get plan;
  String get filePath;
}

final class OfficialAnkiImportPreviewModel extends AnkiImportPreviewModel {
  OfficialAnkiImportPreviewModel({
    required this.plan,
    required this.filePath,
    required this.sourceId,
    required this.sourceHash,
    required this.cardCount,
    required this.noteCount,
    required this.decks,
    required this.schemas,
    required this.suggestions,
    required this.service,
    Set<int>? confirmedNotetypes,
    Set<int>? skippedNotetypes,
    this.needsMapping = false,
    this.showAllRecognition = false,
  })  : // Mutable by design: mapping confirmations/skips fold into these
        // sets through controller intents.
        confirmedNotetypes = confirmedNotetypes ?? <int>{},
        skippedNotetypes = skippedNotetypes ?? <int>{};

  @override
  final AnkiImportExecutionPlan plan;
  @override
  final String filePath;
  final String sourceId;
  final String sourceHash;
  final int cardCount;
  final int noteCount;
  final List<OfficialAnkiDeckNode> decks;
  final List<OfficialAnkiProjectionSchema> schemas;
  final Map<int, OfficialAnkiMappingSuggestion> suggestions;
  final OfficialAnkiCourseProjectionService service;

  final Set<int> confirmedNotetypes;
  final Set<int> skippedNotetypes;

  bool needsMapping;
  bool showAllRecognition;
}
