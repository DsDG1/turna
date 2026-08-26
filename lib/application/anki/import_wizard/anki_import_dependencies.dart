import 'package:turna/application/ai/engine/ai_engine.dart';
import 'package:turna/application/ai/engine/ai_engine_config_holder.dart';
import 'package:turna/application/anki/anki_deck_manager.dart';
import 'package:turna/application/anki/anki_importer.dart';
import 'package:turna/application/anki/card_recognition_pipeline.dart';
import 'package:turna/application/anki/legacy_anki_import_executor.dart';
import 'package:turna/application/anki_official/import/anki_import_execution_plan.dart';
import 'package:turna/application/anki_official/official_anki_feature_flags.dart';
import 'package:turna/application/anki_official/import/anki_import_facade.dart';
import 'package:turna/application/anki_official/import/official_anki_official_first_service.dart';
import 'package:turna/application/anki_official/projection/official_anki_projection_store.dart';
import 'package:turna/application/audio_controller.dart';
import 'package:turna/application/course_provider.dart';
import 'package:turna/application/mistake_provider.dart';
import 'package:turna/application/settings_provider.dart';
import 'package:turna/application/srs_provider.dart';
import 'package:turna/data/anki_import_dao.dart' show AnkiImportRecord;
import 'package:turna/data/course_database.dart';
import 'package:turna/data/review_history_dao.dart';
import 'package:turna/di/injection.dart';
import 'package:turna/utils/validated_file_picker.dart';

/// Explicit constructor-injected dependencies for the import wizard
/// (maintainability plan §10.1). The widget never assembles business
/// dependencies itself; tests construct this directly with fakes.
class AnkiImportDependencies {
  const AnkiImportDependencies({
    required this.planFor,
    required this.pickFilePath,
    required this.importer,
    required this.legacyExecutorFactory,
    required this.officialFirst,
    required this.recognitionPipelineFactory,
    required this.courseDatabase,
    required this.findExistingImportByHash,
    required this.readOfficialProjectionSummary,
    required this.srsProvider,
    required this.courseProvider,
    required this.aiConfigHolder,
    required this.resolveAiEngine,
    required this.ankiLiteThreshold,
    required this.dailyNewLimit,
  });

  /// Pick-time plan resolver (doc 34 W0-03). Production maps straight to
  /// [AnkiImportFacade.planFor]; tests may inject a legacyOnly haemostasis
  /// resolver to exercise the Legacy flow.
  final AnkiImportExecutionPlan Function({
    required OfficialAnkiFeatureFlags flags,
    required bool isSample,
    required String filePath,
  }) planFor;

  /// File-picker abstraction returning ONE path (or null on cancel).
  final Future<String?> Function({
    required List<String> allowedExtensions,
    required String dialogTitle,
  }) pickFilePath;

  final AnkiImporter importer;
  final LegacyAnkiImportExecutor Function() legacyExecutorFactory;
  final OfficialAnkiOfficialFirstService officialFirst;

  /// Recognition pipeline factory: the no-engine variant runs at preview
  /// time, the AI variant only on explicit identify.
  final CardRecognitionPipeline Function({AiEngine? engine})
      recognitionPipelineFactory;

  final CourseDatabase courseDatabase;
  final Future<AnkiImportRecordForHashLookup?> Function(String hash)
      findExistingImportByHash;

  /// Reads the projection summary for the official done page.
  final Future<OfficialProjectionSummarySnapshot> Function(String sourceId)
      readOfficialProjectionSummary;

  final SrsProvider srsProvider;
  final CourseProvider courseProvider;
  final AiEngineConfigHolder aiConfigHolder;
  final AiEngine? Function() resolveAiEngine;
  final int ankiLiteThreshold;
  final int dailyNewLimit;

  /// Production wiring resolved once at page init. Provider-backed values
  /// (settings thresholds) are captured here as a snapshot — the wizard is
  /// a short-lived modal flow.
  static AnkiImportDependencies production({
    AnkiImporter? importerForTest,
    required CourseProvider courseProvider,
    required SrsProvider srsProvider,
    required SettingsProvider settings,
    required AiEngineConfigHolder aiConfigHolder,
  }) {
    return AnkiImportDependencies(
      planFor: ({required flags, required isSample, required filePath}) =>
          AnkiImportFacade.planFor(
        flags,
        isSample: isSample,
        filePath: filePath,
      ),
      pickFilePath: ({
        required allowedExtensions,
        required dialogTitle,
      }) =>
          ValidatedFilePicker.pickFiles(
        allowedExtensions: allowedExtensions,
        dialogTitle: dialogTitle,
      ).then((result) {
        if (result == null || result.files.isEmpty) return null;
        return result.files.single.path;
      }),
      importer: importerForTest ?? AnkiImporter(),
      legacyExecutorFactory: () => LegacyAnkiImportExecutor(
        database: getIt<CourseDatabase>(),
        srsProvider: srsProvider,
        reviewHistoryDao: getIt<ReviewHistoryDao>(),
        mistakeProvider: getIt<MistakeProvider>(),
        audioController: getIt<AudioController>(),
      ),
      officialFirst: const OfficialAnkiOfficialFirstService(),
      recognitionPipelineFactory: ({AiEngine? engine}) =>
          CardRecognitionPipeline(engine: engine),
      courseDatabase: getIt<CourseDatabase>(),
      findExistingImportByHash: (hash) =>
          LegacyAnkiImportInspector(getIt<CourseDatabase>())
              .findExistingByHash(hash),
      readOfficialProjectionSummary: (sourceId) =>
          OfficialProjectionSummaryReader.read(sourceId),
      srsProvider: srsProvider,
      courseProvider: courseProvider,
      aiConfigHolder: aiConfigHolder,
      resolveAiEngine: () =>
          getIt.isRegistered<AiEngine>() ? getIt<AiEngine>() : null,
      ankiLiteThreshold: settings.ankiLiteThreshold,
      dailyNewLimit: getIt<AnkiDeckManager>().dailyNewLimit,
    );
  }
}

/// Record shape for the existing-import lookup (avoids leaking the DAO
/// record type into the controller surface).
typedef AnkiImportRecordForHashLookup = AnkiImportRecord;

/// Summary shape for the official done page.
typedef OfficialProjectionSummarySnapshot = OfficialProjectionSummary;

/// Indirection over the projection store so tests don't need the real DB.
class OfficialProjectionSummaryReader {
  OfficialProjectionSummaryReader._();

  static Future<OfficialProjectionSummarySnapshot> read(String sourceId) {
    return OfficialAnkiCourseProjectionStore(
      getIt<CourseDatabase>(),
    ).readOfficialProjectionSummary(sourceId);
  }
}
