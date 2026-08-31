import 'package:flutter/foundation.dart';
import 'package:turna/application/anki_official/anki_deck_manager.dart';
import 'package:turna/application/anki_official/import/official_anki_import_orchestrator.dart';
import 'package:turna/application/anki_official/lifecycle/official_anki_maintenance.dart';
import 'package:turna/application/anki_official/lifecycle/official_anki_repair_executor.dart';
import 'package:turna/application/anki_official/lifecycle/official_anki_uninstall_saga.dart';
import 'package:turna/application/anki_official/migration/official_first_reanchor.dart';
import 'package:turna/application/anki_official/official_anki_composition.dart';
import 'package:turna/application/anki_official/storage/official_anki_import_attempt_dao.dart';
import 'package:turna/application/anki_official/storage/official_anki_source_dao.dart';
import 'package:turna/data/course_database.dart';
import 'package:turna/di/injection.dart';
import 'package:turna/service/locator.dart';

/// Single Official startup entry (doc 42 P3): lease → repair/census →
/// re-anchor → pending cleanup. Achievements and orphan media stay separate.
class OfficialAnkiStartupRecovery {
  const OfficialAnkiStartupRecovery();

  static const ownerToken = 'startup-recovery';

  Future<void> run() async {
    final catalog = OfficialAnkiCompositionRoot.readOnlyCatalog;
    if (catalog == null) return;
    final paths = OfficialAnkiCompositionRoot.locatorPaths;
    final profileId = paths?.profileId ?? 'profile-default-01';
    final lease = OfficialAnkiMaintenanceLease(catalog);
    final now = DateTime.now().millisecondsSinceEpoch;
    if (!lease.tryAcquire(
      profileId: profileId,
      ownerToken: ownerToken,
      operationKind: 'startup_recovery',
      nowMillis: now,
    )) {
      return;
    }
    try {
      final engine = OfficialAnkiCompositionRoot.engine;
      if (engine != null && paths != null) {
        final orch = OfficialAnkiImportOrchestrator(
          engine: engine,
          sources: OfficialAnkiSourceDao(catalog),
          attempts: OfficialAnkiImportAttemptDao(catalog),
          paths: paths,
        );
        await const OfficialAnkiRepairExecutor().run(
          course: getIt<CourseDatabase>(),
          catalog: catalog,
          orchestrator: orch,
          paths: paths,
          uninstall: OfficialAnkiUninstallSaga(
            catalog: catalog,
            engine: engine,
            paths: paths,
          ),
        );
      }
      try {
        await OfficialFirstReanchor().runIfNeeded(getIt<AppPrefs>());
      } catch (e) {
        debugPrint('[OfficialAnki] P5F re-anchor skipped: $e');
      }
      try {
        final resumed =
            await getIt<AnkiDeckManager>().retryPendingOfficialCleanups();
        if (resumed > 0) {
          debugPrint('[OfficialAnki] resumed $resumed pending cleanups');
        }
      } catch (e) {
        debugPrint('[OfficialAnki] pending cleanup retry skipped: $e');
      }
    } finally {
      lease.release(profileId: profileId, ownerToken: ownerToken);
    }
  }
}
