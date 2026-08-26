import 'package:turna/application/anki/anki_card_adapter.dart';
import 'package:turna/application/anki/anki_deck_assembler.dart';
import 'package:turna/application/anki/anki_models.dart';
import 'package:turna/application/anki/legacy_anki_import_executor.dart';
import 'package:turna/application/anki/anki_organization_resolver.dart';
import 'package:turna/application/anki/card_recognition_pipeline.dart';
import 'package:turna/application/anki_official/contract/official_anki_dto.dart';
import 'package:turna/application/anki_official/import/anki_import_execution_plan.dart';
import 'package:turna/application/anki_official/projection/official_anki_projection_mapper.dart';
import 'package:turna/application/anki_official/projection/official_anki_projection_service.dart';
import 'package:turna/data/anki_import_dao.dart' show AnkiImportRecord;

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

/// Parsing (Legacy) or running the official-first saga. Exactly one long
/// operation may be active; a cancel request is visible to the executor
/// through the controller.
final class AnkiImportParsing extends AnkiImportWizardState {
  const AnkiImportParsing({
    required this.isSample,
    this.progress = 0,
    this.message = '',
  });

  final bool isSample;
  final double progress;
  final String message;

  @override
  int get step => 1;

  AnkiImportParsing copyWith({double? progress, String? message}) =>
      AnkiImportParsing(
        isSample: isSample,
        progress: progress ?? this.progress,
        message: message ?? this.message,
      );
}

/// Committing either flow. Constructing this twice from the same preview
/// is impossible at the API level (commit is single-flight).
final class AnkiImportCommitting extends AnkiImportWizardState {
  const AnkiImportCommitting({
    this.progress = 0,
    this.message = '',
  });

  final double progress;
  final String message;

  @override
  int get step => 3;

  AnkiImportCommitting copyWith({double? progress, String? message}) =>
      AnkiImportCommitting(
        progress: progress ?? this.progress,
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

/// Preview payload — exactly one variant is ever active (§10.3).
sealed class AnkiImportPreviewModel {
  const AnkiImportPreviewModel();

  /// The pick-time execution plan stays frozen for the whole flow
  /// (doc 34 W0-03): later stages never re-read flags.
  AnkiImportExecutionPlan get plan;
  String get filePath;
}

final class LegacyAnkiImportPreviewModel extends AnkiImportPreviewModel {
  LegacyAnkiImportPreviewModel({
    required this.plan,
    required this.filePath,
    required this.collection,
    required this.sourceHash,
    required this.isSample,
    required this.mappings,
    required this.recognitionResults,
    required this.organizationPreview,
    required this.newCount,
    required this.existingCount,
    required this.existingImport,
    this.strategy = ImportStrategy.merge,
    this.smartGrouping = true,
    this.sectionBeta = false,
    this.importLearningProgress = false,
    this.showAllRecognition = false,
    this.isAiIdentifying = false,
  });

  @override
  final AnkiImportExecutionPlan plan;
  @override
  final String filePath;
  final AnkiCollection collection;
  final String sourceHash;
  final bool isSample;
  Map<int, NotetypeMapping> mappings;
  Map<int, CardRecognitionResult> recognitionResults;
  AnkiOrganizationPreview? organizationPreview;
  final int newCount;
  final int existingCount;
  final AnkiImportRecord? existingImport;

  // Draft options — mutated through controller intents only.
  ImportStrategy strategy;
  bool smartGrouping;
  bool sectionBeta;
  bool importLearningProgress;
  bool showAllRecognition;
  bool isAiIdentifying;

  LegacyAnkiImportPreviewModel copyWith({
    Map<int, NotetypeMapping>? mappings,
    Map<int, CardRecognitionResult>? recognitionResults,
    AnkiOrganizationPreview? organizationPreview,
    ImportStrategy? strategy,
    bool? smartGrouping,
    bool? sectionBeta,
    bool? importLearningProgress,
    bool? showAllRecognition,
    bool? isAiIdentifying,
  }) {
    final next = LegacyAnkiImportPreviewModel(
      plan: plan,
      filePath: filePath,
      collection: collection,
      sourceHash: sourceHash,
      isSample: isSample,
      mappings: mappings ?? this.mappings,
      recognitionResults: recognitionResults ?? this.recognitionResults,
      organizationPreview: organizationPreview ?? this.organizationPreview,
      newCount: newCount,
      existingCount: existingCount,
      existingImport: existingImport,
      strategy: strategy ?? this.strategy,
      smartGrouping: smartGrouping ?? this.smartGrouping,
      sectionBeta: sectionBeta ?? this.sectionBeta,
      importLearningProgress:
          importLearningProgress ?? this.importLearningProgress,
      showAllRecognition: showAllRecognition ?? this.showAllRecognition,
      isAiIdentifying: isAiIdentifying ?? this.isAiIdentifying,
    );
    return next;
  }
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
