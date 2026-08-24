import 'package:drift/drift.dart' show Variable;
import 'package:turna/application/anki/unified_anki_import_orchestrator.dart';
import 'package:turna/application/anki_official/official_anki_composition.dart';
import 'package:turna/application/anki_official/storage/official_anki_source_dao.dart';
import 'package:turna/data/course_database.dart';
import 'package:turna/di/injection.dart';
import 'package:turna/service/locator.dart';

/// P5F-41: one-shot startup task that re-anchors placement/presentation rows
/// of already-active official sources onto the projection index
/// ([UnifiedAnkiImportOrchestrator.publishFromProjection]). Sources without
/// a published projection (dual-write era imports that never projected) keep
/// their existing Dart-parse-anchored rows — re-anchoring them would change
/// card ids the ledger already references.
class OfficialFirstReanchor {
  static const prefKey = 'official_first_reanchor_v1';

  /// Test seam: run even when the pref says the task already ran.
  static bool debugForceRun = false;

  /// Returns the number of placements published this run.
  Future<int> runIfNeeded(AppPrefs prefs) async {
    final done =
        prefs.preferences.getBool(prefKey, defaultValue: false).getValue();
    if (done && !debugForceRun) return 0;
    await prefs.preferences.setBool(prefKey, true);
    final catalog = OfficialAnkiCompositionRoot.readOnlyCatalog;
    if (catalog == null) return 0;
    if (!getIt.isRegistered<CourseDatabase>()) return 0;
    final course = getIt<CourseDatabase>();
    final profileId = OfficialAnkiCompositionRoot.locatorPaths?.profileId ??
        'profile-default-01';
    var published = 0;
    for (final source
        in OfficialAnkiSourceDao(catalog).listSources(profileId)) {
      if (source.state != 'active') continue;
      final manifest = await course.customSelect(
        'SELECT 1 FROM official_anki_projection_manifest WHERE source_id = ?',
        variables: [Variable.withString(source.sourceId)],
      ).get();
      if (manifest.isEmpty) continue;
      final result =
          await UnifiedAnkiImportOrchestrator.instance.publishFromProjection(
        sourceId: source.sourceId,
        sourceHash: source.sourceHash,
      );
      published += result.placementCount;
    }
    return published;
  }
}
