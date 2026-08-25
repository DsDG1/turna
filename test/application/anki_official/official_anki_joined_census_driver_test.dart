import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:turna/application/anki_official/engine/official_anki_operation_coordinator.dart';
import 'package:turna/application/anki_official/migration/official_anki_joined_evidence_reader.dart';
import 'package:turna/application/anki_official/migration/official_anki_migration_dao.dart';
import 'package:turna/application/anki_official/migration/official_anki_migration_state.dart';
import 'package:turna/application/anki_official/migration/official_anki_source_reconciler.dart';
import 'package:turna/application/anki_official/migration/official_anki_startup_census.dart';
import 'package:turna/application/anki_official/migration/official_legacy_migration_driver.dart';
import 'package:turna/application/anki_official/migration/official_legacy_source_migration_saga.dart';
import 'package:turna/application/anki_official/storage/official_anki_database.dart';
import 'package:turna/application/anki_official/storage/official_anki_source_dao.dart';
import 'package:turna/data/anki_import_dao.dart';
import 'package:turna/data/course_database.dart';

import '../../helpers/in_memory_course_db.dart';

const _profile = 'profile-default-01';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  ensureSqliteLibForTestHost();

  late CourseDatabase course;
  late OfficialAnkiDatabase catalog;

  setUp(() {
    course = CourseDatabase(NativeDatabase.memory());
    catalog = OfficialAnkiDatabase.memory();
  });

  tearDown(() async {
    catalog.close();
    await course.close();
  });

  Future<void> insertLegacyImport({
    required String importId,
    required String hash,
    int notes = 1,
    int cards = 1,
    bool withSrs = true,
  }) async {
    await AnkiImportDao(course).upsert(
      AnkiImportRecord(
        importId: importId,
        sourcePath: '/tmp/$importId.apkg',
        sourceHash: hash,
        importedAt: 1,
        noteCount: notes,
        cardCount: cards,
      ),
    );
    for (var i = 1; i <= notes; i++) {
      await course.customStatement(
        'INSERT INTO anki_notes (import_id, note_id, mid, tags, fields_json, '
        'sfld, guid, mod) VALUES (?, ?, 1, "", "[]", ?, ?, 0)',
        [importId, i, 'sfld-$i', 'guid-$importId-$i'],
      );
    }
    for (var i = 1; i <= cards; i++) {
      final wordId = 'anki-$importId-c$i';
      await course.customStatement(
        'INSERT INTO anki_cards_meta (import_id, card_id, note_id, ord, did, '
        'word_id, render_mode, scheduling_json) '
        "VALUES (?, ?, 1, 0, 0, ?, 'hybrid', '{}')",
        [importId, i, wordId],
      );
      if (withSrs) {
        await course.customStatement(
          'INSERT INTO srs_states (word_id, queue, due_at, interval_days, '
          'ease, reps, lapses, is_leech, is_suspended, is_buried, type) '
          "VALUES (?, 'srs', 1, 1, 2.5, 1, 0, 0, 0, 0, 'word')",
          [wordId],
        );
      }
    }
  }

  test('joined reader finds Drift-only cleanLegacy by hash, not display name',
      () async {
    await insertLegacyImport(importId: 'imp-a', hash: 'hash-a');
    await insertLegacyImport(importId: 'imp-b', hash: 'hash-b');

    final report = await const OfficialAnkiSourceCensusService().collect(
      reader: JoinedOfficialAnkiSourceEvidenceReader(
        course: course,
        catalog: catalog,
      ),
      profileId: _profile,
      nowMillis: 10,
    );
    expect(report.rows, hasLength(2));
    expect(
      report.rows.every(
        (r) =>
            r.decision.state == OfficialAnkiSourceReconcileState.cleanLegacy,
      ),
      isTrue,
    );
    final hashes = {for (final r in report.rows) r.evidence.sourceHash};
    expect(hashes, {'hash-a', 'hash-b'});
  });

  test('collect does not mutate Drift inventory or catalog journal', () async {
    await insertLegacyImport(importId: 'imp-ro', hash: 'hash-ro');
    final beforeImports = await course
        .customSelect('SELECT COUNT(*) AS n FROM anki_imports')
        .getSingle();
    final beforeJournal = catalog.handle
        .select(
          'SELECT COUNT(*) AS n FROM anki_source_reconciliation_journal',
        )
        .first['n'] as int;

    await const OfficialAnkiStartupCensus().collect(
      course: course,
      catalog: catalog,
      nowMillis: 11,
    );

    final afterImports = await course
        .customSelect('SELECT COUNT(*) AS n FROM anki_imports')
        .getSingle();
    expect(afterImports.read<int>('n'), beforeImports.read<int>('n'));
    final afterJournal = catalog.handle
        .select(
          'SELECT COUNT(*) AS n FROM anki_source_reconciliation_journal',
        )
        .first['n'] as int;
    expect(afterJournal, beforeJournal);
  });

  test('startup persist journals scanned rows idempotently', () async {
    await insertLegacyImport(importId: 'imp-j', hash: 'hash-j');
    const startup = OfficialAnkiStartupCensus();
    final report = await startup.collect(
      course: course,
      catalog: catalog,
      nowMillis: 12,
    );
    final first = startup.persistScannedJournals(
      catalog: catalog,
      report: report,
      nowMillis: 12,
    );
    expect(first, 1);
    final second = startup.persistScannedJournals(
      catalog: catalog,
      report: report,
      nowMillis: 13,
    );
    expect(second, 0);
    final open = OfficialAnkiReconciliationJournalDao(catalog).listOpen(
      profileId: _profile,
    );
    expect(open, hasLength(1));
    expect(open.single.currentStep, OfficialAnkiReconcileJournalStep.scanned);
    expect(
      open.single.beforeState,
      OfficialAnkiSourceReconcileState.cleanLegacy,
    );
  });

  test('W8 driver begins one cleanLegacy source after user policy confirm',
      () {
    // Use in-memory evidence via collect isn't needed — build a row.
    const evidence = OfficialAnkiSourceEvidence(
      profileId: _profile,
      importId: 'imp-drv',
      sourceHash: 'hash-drv',
      recordedOwner: OfficialAnkiPersistedOwner.legacy,
      legacyImportPresent: true,
      legacyNoteCount: 1,
      legacyCardCount: 1,
      legacySrsCount: 1,
    );
    final decision = const OfficialAnkiSourceReconciler().classify(evidence);
    expect(decision.state, OfficialAnkiSourceReconcileState.cleanLegacy);
    final report = OfficialAnkiSourceCensusReport(
      generatedAtMillis: 1,
      rows: [
        OfficialAnkiSourceCensusRow(evidence: evidence, decision: decision),
      ],
    );
    const driver = OfficialLegacyMigrationDriver();
    expect(driver.pendingCleanLegacy(report), hasLength(1));

    final dao = OfficialAnkiMigrationDao(catalog);
    final saga = OfficialLegacySourceMigrationSaga(
      dao: dao,
      coordinator: OfficialAnkiOperationCoordinator(),
    );
    driver.beginOne(
      saga: saga,
      row: report.rows.single,
      policy: LegacyAnkiSchedulingPolicy.resetAsNew,
      policyConfirmedByUser: true,
      migrationId: 'mig-drv',
      nowMillis: 20,
    );
    final row = dao.findByLegacyImport(
      profileId: _profile,
      legacyImportId: 'imp-drv',
    );
    expect(row, isNotNull);
    expect(row!.state, LegacyAnkiMigrationState.awaitingPackage);
  });

  test('joined merge uses source hash not display name', () async {
    await insertLegacyImport(importId: 'imp-same-name-1', hash: 'hash-1');
    OfficialAnkiSourceDao(catalog).upsertSource(
      sourceId: 'src-other',
      profileId: _profile,
      sourceHash: 'hash-2',
      sourceSize: 1,
      displayName: 'Turkish A1',
      state: 'active',
      backendCommit: 't',
      nowMillis: 1,
    );
    final rows = await JoinedOfficialAnkiSourceEvidenceReader(
      course: course,
      catalog: catalog,
    ).loadEvidence(profileId: _profile);
    expect(rows, hasLength(2));
  });
}
