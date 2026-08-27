import 'package:turna/application/anki_official/anki_deck_manager.dart';
import 'package:turna/application/anki_official/import/anki_import_execution_plan.dart';
import 'package:turna/application/anki_official/official_anki_feature_flags.dart';
import 'package:turna/application/anki_official/import/anki_import_facade.dart';
import 'package:turna/application/anki_official/import/official_anki_official_first_service.dart';
import 'package:turna/application/anki_official/projection/official_anki_projection_store.dart';
import 'package:turna/application/course_provider.dart';
import 'package:turna/application/settings_provider.dart';
import 'package:turna/data/course_database.dart';
import 'package:turna/di/injection.dart';
import 'package:turna/utils/validated_file_picker.dart';

/// Explicit constructor-injected dependencies for the import wizard
/// (maintainability plan §10.1). The widget never assembles business
/// dependencies itself; tests construct this directly with fakes.
class AnkiImportDependencies {
  const AnkiImportDependencies({
    required this.planFor,
    required this.pickFilePath,
    required this.officialFirst,
    required this.courseDatabase,
    required this.readOfficialProjectionSummary,
    required this.courseProvider,
    required this.ankiLiteThreshold,
    required this.dailyNewLimit,
  });

  /// Pick-time plan resolver (doc 34 W0-03). Production maps straight to
  /// [AnkiImportFacade.planFor]; tests may inject a fail-closed resolver.
  final AnkiImportExecutionPlan Function({
    required OfficialAnkiFeatureFlags flags,
    required String filePath,
  }) planFor;

  /// File-picker abstraction returning ONE path (or null on cancel).
  final Future<String?> Function({
    required List<String> allowedExtensions,
    required String dialogTitle,
  }) pickFilePath;

  final OfficialAnkiOfficialFirstService officialFirst;

  final CourseDatabase courseDatabase;

  /// Reads the projection summary for the official done page.
  final Future<OfficialProjectionSummarySnapshot> Function(String sourceId)
      readOfficialProjectionSummary;

  final CourseProvider courseProvider;
  final int ankiLiteThreshold;
  final int dailyNewLimit;

  /// Production wiring resolved once at page init. Provider-backed values
  /// (settings thresholds) are captured here as a snapshot — the wizard is
  /// a short-lived modal flow.
  static AnkiImportDependencies production({
    required CourseProvider courseProvider,
    required SettingsProvider settings,
  }) {
    return AnkiImportDependencies(
      planFor: ({required flags, required filePath}) =>
          AnkiImportFacade.planFor(
        flags,
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
      officialFirst: const OfficialAnkiOfficialFirstService(),
      courseDatabase: getIt<CourseDatabase>(),
      readOfficialProjectionSummary: (sourceId) =>
          OfficialProjectionSummaryReader.read(sourceId),
      courseProvider: courseProvider,
      ankiLiteThreshold: settings.ankiLiteThreshold,
      dailyNewLimit: getIt<AnkiDeckManager>().dailyNewLimit,
    );
  }
}

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
