import 'package:turna/application/anki_official/import/official_anki_import_orchestrator.dart';
import 'package:turna/application/anki_official/import/official_anki_recovery_service.dart';
import 'package:turna/application/anki_official/lifecycle/official_anki_lifecycle_models.dart';
import 'package:turna/application/anki_official/lifecycle/official_anki_maintenance.dart';
import 'package:turna/application/anki_official/lifecycle/official_anki_uninstall_saga.dart';
import 'package:turna/application/anki_official/migration/official_anki_startup_census.dart';
import 'package:turna/application/anki_official/official_anki_paths.dart';
import 'package:turna/application/anki_official/storage/official_anki_database.dart';
import 'package:turna/data/course_database.dart';
import 'package:flutter/foundation.dart' show debugPrint;

/// Production executor for census whitelist actions (doc 41 S8).
class OfficialAnkiRepairExecutor {
  const OfficialAnkiRepairExecutor();

  static const whitelist = <String>{
    'resumeImport',
    'resumeProjection',
    'commitAuthority',
    'retryCleanup',
    'enqueueMaintenance',
    'quarantine',
  };

  /// Doc 42 P3: census `restoreCheckpoint` is not executable; quarantine.
  static String effectiveAction(String action) =>
      action == 'restoreCheckpoint' ? 'quarantine' : action;

  Future<OfficialAnkiRepairReport> run({
    required CourseDatabase course,
    required OfficialAnkiDatabase catalog,
    required OfficialAnkiImportOrchestrator orchestrator,
    OfficialAnkiPaths? paths,
    OfficialAnkiUninstallSaga? uninstall,
    String profileId = 'profile-default-01',
  }) async {
    const census = OfficialAnkiStartupCensus();
    final report = await census.run(
      course: course,
      catalog: catalog,
      profileId: profileId,
    );
    final recovery = OfficialAnkiRecoveryService(
      sources: orchestrator.sources,
      attempts: orchestrator.attempts,
      engine: orchestrator.engine,
      orchestrator: orchestrator,
    );
    final recovered = await recovery.recoverUnfinished();
    var cleanups = 0;
    if (uninstall != null) {
      final pending = orchestrator.sources
          .listSources(profileId)
          .where((row) => row.state == 'pending_cleanup');
      for (final source in pending) {
        try {
          final result = await uninstall.run(source.sourceId);
          if (result.logicalDeleteComplete) cleanups++;
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
      ).runPending(profileId: profileId);
    }
    return OfficialAnkiRepairReport(
      censusRows: report.rows.length,
      recoveredAttempts: recovered.length,
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
