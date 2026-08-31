import 'package:turna/application/anki_official/engine/official_anki_engine.dart';
import 'package:turna/application/anki_official/lifecycle/official_anki_lifecycle_models.dart';
import 'package:turna/application/anki_official/lifecycle/official_anki_maintenance.dart';
import 'package:turna/application/anki_official/official_anki_composition.dart';
import 'package:turna/application/anki_official/official_anki_paths.dart';
import 'package:turna/application/anki_official/storage/official_anki_database.dart';
import 'package:turna/data/course_database.dart';
import 'package:turna/di/injection.dart';

/// Result of a user-initiated database optimize (doc 41 §12.4 forceCompact).
class OfficialStorageOptimizeResult {
  const OfficialStorageOptimizeResult({
    required this.ok,
    this.completedJobs = 0,
    this.errorCode,
  });

  final bool ok;
  final int completedJobs;
  final String? errorCode;
}

/// Enqueues compact jobs and runs them with [forceCompact] so storage-page
/// "optimize" ignores freelist thresholds.
class OfficialStorageOptimizeService {
  const OfficialStorageOptimizeService();

  Future<OfficialStorageOptimizeResult> runForceCompact({
    OfficialAnkiDatabase? catalog,
    OfficialAnkiPaths? paths,
    CourseDatabase? course,
    OfficialAnkiEngine? engine,
  }) async {
    final resolvedCatalog =
        catalog ?? OfficialAnkiCompositionRoot.readOnlyCatalog;
    final resolvedPaths = paths ?? OfficialAnkiCompositionRoot.locatorPaths;
    if (resolvedCatalog == null || resolvedPaths == null) {
      return const OfficialStorageOptimizeResult(
        ok: false,
        errorCode: 'capability_missing',
      );
    }
    final resolvedCourse = course ?? _registeredCourse();
    final resolvedEngine = engine ?? OfficialAnkiCompositionRoot.engine;
    final now = DateTime.now().millisecondsSinceEpoch;
    final jobs = OfficialAnkiMaintenanceJobDao(resolvedCatalog);
    final profileId = resolvedPaths.profileId;
    jobs.enqueue(
      profileId: profileId,
      kind: OfficialAnkiMaintenanceKind.compactCollection,
      nowMillis: now,
    );
    jobs.enqueue(
      profileId: profileId,
      kind: OfficialAnkiMaintenanceKind.compactCatalog,
      nowMillis: now,
    );
    jobs.enqueue(
      profileId: profileId,
      kind: OfficialAnkiMaintenanceKind.compactCourse,
      nowMillis: now,
    );
    final completed = await OfficialAnkiMaintenanceRunner(
      catalog: resolvedCatalog,
      paths: resolvedPaths,
      engine: resolvedEngine,
      course: resolvedCourse,
      forceCompact: true,
    ).runPending(profileId: profileId);
    return OfficialStorageOptimizeResult(ok: true, completedJobs: completed);
  }

  static CourseDatabase? _registeredCourse() {
    if (!getIt.isRegistered<CourseDatabase>()) return null;
    return getIt<CourseDatabase>();
  }
}
