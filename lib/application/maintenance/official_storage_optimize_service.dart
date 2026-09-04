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
  const OfficialStorageOptimizeService({this.ensureEngine});

  /// Opens the live engine session when none exists yet. Compact of
  /// collection.anki2 must go through the engine (rslib's `COLLATE
  /// unicase` indexes), so a user-initiated optimize bootstraps the same
  /// session the home due sync opens instead of degrading to a raw-file
  /// VACUUM that cannot rebuild those indexes. Injectable for tests.
  final Future<OfficialAnkiEngine?> Function()? ensureEngine;

  Future<OfficialAnkiEngine?> _ensureEngine() async {
    await OfficialAnkiCompositionRoot.requireImporter();
    return OfficialAnkiCompositionRoot.engine;
  }

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
    var resolvedEngine = engine ?? OfficialAnkiCompositionRoot.engine;
    if (resolvedEngine == null) {
      try {
        resolvedEngine = await (ensureEngine ?? _ensureEngine)();
      } catch (_) {
        resolvedEngine = null;
      }
      if (resolvedEngine == null) {
        // Fail closed BEFORE enqueuing: compactCollection without an
        // engine would only land in retry_wait and linger as a zombie job.
        return const OfficialStorageOptimizeResult(
          ok: false,
          errorCode: 'importer_not_ready',
        );
      }
    }
    final now = DateTime.now().millisecondsSinceEpoch;
    final jobs = OfficialAnkiMaintenanceJobDao(resolvedCatalog);
    final profileId = resolvedPaths.profileId;
    // media_gc 排最前：压缩前先删无主媒体，VACUUM 之后 collection 与
    // 媒体目录的体积一次到位——手动优化即完整的手动回收路径。
    jobs.enqueue(
      profileId: profileId,
      kind: OfficialAnkiMaintenanceKind.mediaGc,
      nowMillis: now,
    );
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
