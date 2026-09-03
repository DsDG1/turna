import 'package:turna/application/anki_official/import/official_anki_import_orchestrator.dart';
import 'package:turna/application/anki_official/lifecycle/official_anki_lifecycle_models.dart';
import 'package:turna/application/anki_official/lifecycle/official_anki_maintenance.dart';
import 'package:turna/application/anki_official/official_anki_paths.dart';
import 'package:turna/application/anki_official/storage/official_anki_database.dart';
import 'package:turna/application/anki_official/v2/official_anki_v2_retire_service.dart';
import 'package:turna/data/course_database.dart';
import 'package:flutter/foundation.dart' show debugPrint;

/// Production executor for the startup repair pass: drives pending v2
/// retire sequences to completion and drains pending maintenance jobs.
class OfficialAnkiRepairExecutor {
  const OfficialAnkiRepairExecutor();

  Future<OfficialAnkiRepairReport> run({
    required CourseDatabase course,
    required OfficialAnkiDatabase catalog,
    required OfficialAnkiImportOrchestrator orchestrator,
    OfficialAnkiPaths? paths,
    dynamic uninstall,
    String profileId = 'profile-default-01',
    String? maintenanceLeaseOwnerToken,
  }) async {
    var cleanups = 0;
    if (paths != null) {
      final retireService = OfficialAnkiV2RetireService(
        catalog: catalog,
        paths: paths,
        course: course,
        engine: orchestrator.engine,
      );
      final pending = orchestrator.sources
          .listSources(profileId)
          .where((row) =>
              row.state == 'pending_cleanup' || row.state == 'retiring');
      for (final source in pending) {
        try {
          await retireService.runRetireJob(sourceId: source.sourceId);
          cleanups++;
        } catch (error) {
          debugPrint('[OfficialAnkiRepair] cleanup ${source.sourceId}: $error');
        }
      }
    }
    var maintenance = 0;
    if (paths != null) {
      maintenance = await OfficialAnkiMaintenanceRunner(
        catalog: catalog,
        paths: paths,
        engine: orchestrator.engine,
        course: course,
      ).runPending(
        profileId: profileId,
        leaseOwnerToken: maintenanceLeaseOwnerToken,
      );
    }
    return OfficialAnkiRepairReport(
      censusRows: 0,
      recoveredAttempts: 0,
      resumedCleanups: cleanups,
      maintenanceJobs: maintenance,
    );
  }
}

class OfficialAnkiRepairReport {
  const OfficialAnkiRepairReport({
    required this.censusRows,
    required this.recoveredAttempts,
    required this.resumedCleanups,
    required this.maintenanceJobs,
  });

  final int censusRows;
  final int recoveredAttempts;
  final int resumedCleanups;
  final int maintenanceJobs;
}

class OfficialAnkiImportSagaCoordinator {
  OfficialAnkiImportSagaCoordinator(this.orchestrator);

  final OfficialAnkiImportOrchestrator orchestrator;

  Future<void> requestDiscard(String attemptId) async {
    orchestrator.attempts.setUserIntent(
      attemptId: attemptId,
      intent: OfficialAnkiUserIntent.discard,
      nowMillis: DateTime.now().millisecondsSinceEpoch,
    );
    await orchestrator.engine.cancel();
    final attempt = orchestrator.attempts.find(attemptId);
    if (attempt == null) return;
    if (!attempt.state.contains('preview') &&
        attempt.state != 'indexing_cards' &&
        attempt.state != 'indexing_notes' &&
        attempt.state != 'importing_official' &&
        attempt.state != 'backing_up' &&
        attempt.state != 'preparing') {
      return;
    }
    await orchestrator.rollbackAttempt(attempt);
  }

  Future<void> requestContinue(String attemptId) async {
    orchestrator.attempts.setUserIntent(
      attemptId: attemptId,
      intent: OfficialAnkiUserIntent.continueImport,
      nowMillis: DateTime.now().millisecondsSinceEpoch,
    );
  }
}
