import 'package:turna/application/anki_official/migration/official_anki_joined_evidence_reader.dart';
import 'package:turna/application/anki_official/migration/official_anki_production_router.dart';
import 'package:turna/application/anki_official/migration/official_anki_source_reconciler.dart';
import 'package:turna/application/anki_official/official_anki_ids.dart';
import 'package:turna/application/anki_official/storage/official_anki_database.dart';
import 'package:turna/data/course_database.dart';

/// Boot-time read-only census (doc 34 W3).
///
/// [collect] never mutates Drift or Collection. [persistScannedJournals]
/// writes reconciliation journal `scanned` rows only — no owner switch.
class OfficialAnkiStartupCensus {
  const OfficialAnkiStartupCensus({
    this.census = const OfficialAnkiSourceCensusService(),
  });

  final OfficialAnkiSourceCensusService census;

  /// Last report from [run] in this process. Tests may read it; production
  /// treats it as a diagnostic snapshot (no card text).
  static OfficialAnkiSourceCensusReport? lastReport;

  Future<OfficialAnkiSourceCensusReport> collect({
    required CourseDatabase course,
    OfficialAnkiDatabase? catalog,
    String profileId = OfficialAnkiProductionRouter.defaultProfileId,
    int? nowMillis,
  }) {
    return census.collect(
      reader: JoinedOfficialAnkiSourceEvidenceReader(
        course: course,
        catalog: catalog,
      ),
      profileId: profileId,
      nowMillis: nowMillis,
    );
  }

  /// Insert `scanned` journal rows for new evidence hashes. Idempotent.
  int persistScannedJournals({
    required OfficialAnkiDatabase catalog,
    required OfficialAnkiSourceCensusReport report,
    String profileId = OfficialAnkiProductionRouter.defaultProfileId,
    int? nowMillis,
  }) {
    final dao = OfficialAnkiReconciliationJournalDao(catalog);
    final now = nowMillis ?? DateTime.now().millisecondsSinceEpoch;
    var inserted = 0;
    for (final row in report.rows) {
      final existing = dao.findByEvidenceHash(
        profileId: profileId,
        evidenceHash: row.decision.evidenceHash,
      );
      if (existing != null) continue;
      beginReconciliationJournal(
        dao: dao,
        evidence: row.evidence,
        decision: row.decision,
        operationId: newOfficialAnkiId('rec'),
        nowMillis: now,
      );
      inserted++;
    }
    return inserted;
  }

  Future<OfficialAnkiSourceCensusReport> run({
    required CourseDatabase course,
    OfficialAnkiDatabase? catalog,
    String profileId = OfficialAnkiProductionRouter.defaultProfileId,
    int? nowMillis,
  }) async {
    final report = await collect(
      course: course,
      catalog: catalog,
      profileId: profileId,
      nowMillis: nowMillis,
    );
    lastReport = report;
    if (catalog != null) {
      persistScannedJournals(
        catalog: catalog,
        report: report,
        profileId: profileId,
        nowMillis: nowMillis,
      );
    }
    return report;
  }
}
