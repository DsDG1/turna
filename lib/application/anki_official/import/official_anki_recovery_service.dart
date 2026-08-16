import 'package:turna/application/anki_official/engine/official_anki_engine.dart';
import 'package:turna/application/anki_official/import/official_anki_import_orchestrator.dart';
import 'package:turna/application/anki_official/import/official_anki_import_state.dart';
import 'package:turna/application/anki_official/storage/official_anki_import_attempt_dao.dart';
import 'package:turna/application/anki_official/storage/official_anki_source_dao.dart';

class OfficialAnkiRecoveryService {
  OfficialAnkiRecoveryService({
    required this.sources,
    required this.attempts,
    required this.engine,
    required this.orchestrator,
  });

  final OfficialAnkiSourceDao sources;
  final OfficialAnkiImportAttemptDao attempts;
  final OfficialAnkiEngine engine;
  final OfficialAnkiImportOrchestrator orchestrator;

  OfficialAnkiRecoveryDecision decide(OfficialAnkiAttemptRow attempt) {
    return decideOfficialAnkiRecovery(attempt);
  }

  Future<OfficialAnkiImportResult> recover(OfficialAnkiAttemptRow attempt) {
    return orchestrator.recoverAttempt(attempt);
  }

  Future<List<OfficialAnkiImportResult>> recoverUnfinished() async {
    final results = <OfficialAnkiImportResult>[];
    for (final attempt in attempts.unfinished()) {
      results.add(await recover(attempt));
    }
    return results;
  }
}
