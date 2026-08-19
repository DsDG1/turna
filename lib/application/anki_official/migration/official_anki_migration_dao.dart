import 'package:sqlite3/sqlite3.dart';
import 'package:turna/application/anki_official/contract/official_anki_errors.dart';
import 'package:turna/application/anki_official/migration/official_anki_dry_run_matcher.dart';
import 'package:turna/application/anki_official/migration/official_anki_migration_state.dart';
import 'package:turna/application/anki_official/storage/official_anki_database.dart';

class LegacyAnkiMigrationRow {
  const LegacyAnkiMigrationRow({
    required this.migrationId,
    required this.profileId,
    required this.legacyImportId,
    required this.state,
    required this.schedulingPolicy,
    required this.legacyCardCount,
    required this.matchedCardCount,
    required this.unresolvedCardCount,
    required this.officialMutationCountAtCutover,
    required this.startedAtMillis,
    required this.updatedAtMillis,
    this.officialSourceId,
    this.sourceHash,
    this.backupId,
    this.backupManifestHash,
    this.cursorLegacyCardId,
    this.completedAtMillis,
    this.recordedKind,
  });

  final String migrationId;
  final String profileId;
  final String legacyImportId;
  final String? officialSourceId;
  final LegacyAnkiMigrationState state;
  final LegacyAnkiSchedulingPolicy schedulingPolicy;
  final String? sourceHash;
  final String? backupId;
  final String? backupManifestHash;
  final int legacyCardCount;
  final int matchedCardCount;
  final int unresolvedCardCount;
  final int? cursorLegacyCardId;
  final int officialMutationCountAtCutover;
  final int startedAtMillis;
  final int updatedAtMillis;
  final int? completedAtMillis;
  final String? recordedKind;
}

class OfficialAnkiMigrationDao {
  OfficialAnkiMigrationDao(this._database);

  final OfficialAnkiDatabase _database;
  Database get _db => _database.handle;

  void insertDetected({
    required String migrationId,
    required String profileId,
    required String legacyImportId,
    required LegacyAnkiSchedulingPolicy policy,
    required int nowMillis,
    String? sourceHash,
    int legacyCardCount = 0,
  }) {
    _db.execute(
      '''
INSERT INTO legacy_anki_migrations (
  migration_id, profile_id, legacy_import_id, state, scheduling_policy,
  source_hash, legacy_card_count, started_at_millis, updated_at_millis
) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)
''',
      [
        migrationId,
        profileId,
        legacyImportId,
        LegacyAnkiMigrationState.detected.name,
        policy.name,
        sourceHash,
        legacyCardCount,
        nowMillis,
        nowMillis,
      ],
    );
  }

  LegacyAnkiMigrationRow? findByLegacyImport({
    required String profileId,
    required String legacyImportId,
  }) {
    final rows = _db.select(
      'SELECT * FROM legacy_anki_migrations '
      'WHERE profile_id = ? AND legacy_import_id = ?',
      [profileId, legacyImportId],
    );
    if (rows.isEmpty) return null;
    return _row(rows.first);
  }

  List<LegacyAnkiMigrationRow> listMigrations({required String profileId}) {
    return _db
        .select(
          'SELECT * FROM legacy_anki_migrations WHERE profile_id = ? '
          'ORDER BY updated_at_millis DESC',
          [profileId],
        )
        .map(_row)
        .toList();
  }

  List<LegacyAnkiMigrationRow> listFixtureMigrations({
    required String profileId,
  }) {
    return _db
        .select(
          "SELECT * FROM legacy_anki_migrations "
          "WHERE profile_id = ? AND legacy_import_id LIKE 'p5c-fixture-%' "
          'ORDER BY updated_at_millis DESC',
          [profileId],
        )
        .map(_row)
        .toList();
  }

  LegacyAnkiMigrationRow? findObservingFixture({required String profileId}) {
    final rows = _db.select(
      "SELECT * FROM legacy_anki_migrations "
      "WHERE profile_id = ? AND state = 'observing' "
      "AND legacy_import_id LIKE 'p5c-fixture-%' "
      'ORDER BY updated_at_millis DESC LIMIT 1',
      [profileId],
    );
    if (rows.isEmpty) return null;
    return _row(rows.first);
  }

  void transition({
    required String migrationId,
    required LegacyAnkiMigrationState expected,
    required LegacyAnkiMigrationState next,
    required int nowMillis,
    String? errorCode,
    String? errorMessage,
    int? matchedCardCount,
    int? unresolvedCardCount,
    String? officialSourceId,
  }) {
    if (!legacyAnkiMigrationAllowsTransition(from: expected, to: next)) {
      throw OfficialAnkiException(
        code: OfficialAnkiErrorCode.invalidState,
        messageKey: 'official_anki.illegal_migration_transition',
        debugDetails: '${expected.name}->${next.name}',
      );
    }
    _db.execute(
      '''
UPDATE legacy_anki_migrations
SET state = ?, updated_at_millis = ?, last_error_code = ?,
    last_error_safe_message = ?,
    matched_card_count = COALESCE(?, matched_card_count),
    unresolved_card_count = COALESCE(?, unresolved_card_count),
    official_source_id = COALESCE(?, official_source_id),
    completed_at_millis = CASE WHEN ? IN ('completed','rolledBackLegacy')
      THEN ? ELSE completed_at_millis END
WHERE migration_id = ? AND state = ?
''',
      [
        next.name,
        nowMillis,
        errorCode,
        errorMessage,
        matchedCardCount,
        unresolvedCardCount,
        officialSourceId,
        next.name,
        nowMillis,
        migrationId,
        expected.name,
      ],
    );
    if (_db.updatedRows != 1) {
      throw OfficialAnkiException(
        code: OfficialAnkiErrorCode.invalidState,
        messageKey: 'official_anki.migration_cas_failed',
        debugDetails: '$migrationId expected ${expected.name}',
      );
    }
  }

  void setCursor({
    required String migrationId,
    required int? cursorLegacyCardId,
    required int nowMillis,
    int? matchedCardCount,
    int? unresolvedCardCount,
  }) {
    _db.execute(
      '''
UPDATE legacy_anki_migrations
SET cursor_legacy_card_id = ?, updated_at_millis = ?,
    matched_card_count = COALESCE(?, matched_card_count),
    unresolved_card_count = COALESCE(?, unresolved_card_count)
WHERE migration_id = ?
''',
      [
        cursorLegacyCardId,
        nowMillis,
        matchedCardCount,
        unresolvedCardCount,
        migrationId,
      ],
    );
  }

  void upsertCardMapRows({
    required String migrationId,
    required List<LegacyAnkiCardMapDraft> rows,
  }) {
    final stmt = _db.prepare(
      '''
INSERT OR REPLACE INTO legacy_anki_card_map (
  migration_id, legacy_card_id, legacy_word_id, legacy_note_id, note_guid,
  template_ord, official_card_id, match_method, match_state, content_fingerprint
) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
''',
    );
    try {
      for (final row in rows) {
        stmt.execute([
          migrationId,
          row.legacyCardId,
          row.legacyWordId,
          row.legacyNoteId,
          row.noteGuid,
          row.templateOrd,
          row.officialCardId,
          row.matchMethod.name,
          row.matchState.name,
          row.contentFingerprint,
        ]);
      }
    } finally {
      stmt.dispose();
    }
  }

  void replaceDryRunMap({
    required String migrationId,
    required LegacyAnkiDryRunResult result,
  }) {
    _db.execute('BEGIN');
    try {
      _db.execute(
        'DELETE FROM legacy_anki_card_map WHERE migration_id = ?',
        [migrationId],
      );
      final stmt = _db.prepare(
        '''
INSERT INTO legacy_anki_card_map (
  migration_id, legacy_card_id, legacy_word_id, legacy_note_id, note_guid,
  template_ord, official_card_id, match_method, match_state, content_fingerprint
) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
''',
      );
      for (final row in result.rows) {
        stmt.execute([
          migrationId,
          row.legacyCardId,
          row.legacyWordId,
          row.legacyNoteId,
          row.noteGuid,
          row.templateOrd,
          row.officialCardId,
          row.matchMethod.name,
          row.matchState.name,
          row.contentFingerprint,
        ]);
      }
      stmt.dispose();
      _db.execute('COMMIT');
    } catch (_) {
      _db.execute('ROLLBACK');
      rethrow;
    }
  }

  List<LegacyAnkiCardMapDraft> listCardMap(String migrationId) {
    return _db
        .select(
          'SELECT * FROM legacy_anki_card_map WHERE migration_id = ? '
          'ORDER BY legacy_card_id',
          [migrationId],
        )
        .map(
          (row) => LegacyAnkiCardMapDraft(
            legacyCardId: (row['legacy_card_id'] as num).toInt(),
            legacyWordId: row['legacy_word_id'] as String,
            legacyNoteId: (row['legacy_note_id'] as num?)?.toInt(),
            noteGuid: row['note_guid'] as String?,
            templateOrd: (row['template_ord'] as num).toInt(),
            officialCardId: (row['official_card_id'] as num?)?.toInt(),
            matchMethod: parseLegacyAnkiMatchMethod(row['match_method'] as String?),
            matchState: parseLegacyAnkiMatchState(row['match_state'] as String?),
            contentFingerprint: row['content_fingerprint'] as String?,
          ),
        )
        .toList();
  }

  void setOfficialMutationCountAtCutover({
    required String migrationId,
    required int count,
    required int nowMillis,
  }) {
    _db.execute(
      '''
UPDATE legacy_anki_migrations
SET official_mutation_count_at_cutover = ?, updated_at_millis = ?
WHERE migration_id = ?
''',
      [count, nowMillis, migrationId],
    );
  }

  void insertObservingOfficial({
    required String migrationId,
    required String profileId,
    required String legacyImportId,
    required String officialSourceId,
    required String sourceHash,
    required int nowMillis,
    int cardCount = 0,
  }) {
    _db.execute(
      '''
INSERT INTO legacy_anki_migrations (
  migration_id, profile_id, legacy_import_id, official_source_id, state,
  scheduling_policy, source_hash, legacy_card_count, matched_card_count,
  recorded_kind, started_at_millis, updated_at_millis
) VALUES (?, ?, ?, ?, 'observing', 'preservePackageScheduling', ?, ?, ?,
  'official', ?, ?)
''',
      [
        migrationId,
        profileId,
        legacyImportId,
        officialSourceId,
        sourceHash,
        cardCount,
        cardCount,
        nowMillis,
        nowMillis,
      ],
    );
  }

  void setOfficialSourceAndRecordedKind({
    required String migrationId,
    required String officialSourceId,
    required String recordedKind,
    required int nowMillis,
  }) {
    _db.execute(
      '''
UPDATE legacy_anki_migrations
SET official_source_id = ?, recorded_kind = ?, updated_at_millis = ?
WHERE migration_id = ?
''',
      [officialSourceId, recordedKind, nowMillis, migrationId],
    );
  }

  void setRecordedKind({
    required String migrationId,
    required String? recordedKind,
    required int nowMillis,
  }) {
    _db.execute(
      '''
UPDATE legacy_anki_migrations
SET recorded_kind = ?, updated_at_millis = ?
WHERE migration_id = ?
''',
      [recordedKind, nowMillis, migrationId],
    );
  }

  String? recordedKindForSource({
    required String profileId,
    required String legacyImportId,
  }) {
    final row = findByLegacyImport(
      profileId: profileId,
      legacyImportId: legacyImportId,
    );
    return row?.recordedKind;
  }

  LegacyAnkiMigrationRow? findById(String migrationId) {
    final rows = _db.select(
      'SELECT * FROM legacy_anki_migrations WHERE migration_id = ?',
      [migrationId],
    );
    if (rows.isEmpty) return null;
    return _row(rows.first);
  }

  void setBackupInfo({
    required String migrationId,
    required String backupId,
    required String backupManifestHash,
    required int nowMillis,
  }) {
    _db.execute(
      '''
UPDATE legacy_anki_migrations
SET backup_id = ?, backup_manifest_hash = ?, updated_at_millis = ?
WHERE migration_id = ?
''',
      [backupId, backupManifestHash, nowMillis, migrationId],
    );
  }

  int? getCursor(String migrationId) {
    final rows = _db.select(
      'SELECT cursor_legacy_card_id FROM legacy_anki_migrations WHERE migration_id = ?',
      [migrationId],
    );
    if (rows.isEmpty) return null;
    return (rows.first['cursor_legacy_card_id'] as num?)?.toInt();
  }

  LegacyAnkiMigrationRow _row(Row row) {
    String? recordedKind;
    try {
      recordedKind = row['recorded_kind'] as String?;
    } catch (_) {
      recordedKind = null;
    }
    return LegacyAnkiMigrationRow(
      migrationId: row['migration_id'] as String,
      profileId: row['profile_id'] as String,
      legacyImportId: row['legacy_import_id'] as String,
      officialSourceId: row['official_source_id'] as String?,
      state: parseLegacyAnkiMigrationState(row['state'] as String?),
      schedulingPolicy:
          parseLegacyAnkiSchedulingPolicy(row['scheduling_policy'] as String?),
      sourceHash: row['source_hash'] as String?,
      backupId: row['backup_id'] as String?,
      backupManifestHash: row['backup_manifest_hash'] as String?,
      legacyCardCount: (row['legacy_card_count'] as num).toInt(),
      matchedCardCount: (row['matched_card_count'] as num).toInt(),
      unresolvedCardCount: (row['unresolved_card_count'] as num).toInt(),
      cursorLegacyCardId: (row['cursor_legacy_card_id'] as num?)?.toInt(),
      officialMutationCountAtCutover:
          (row['official_mutation_count_at_cutover'] as num).toInt(),
      startedAtMillis: (row['started_at_millis'] as num).toInt(),
      updatedAtMillis: (row['updated_at_millis'] as num).toInt(),
      completedAtMillis: (row['completed_at_millis'] as num?)?.toInt(),
      recordedKind: recordedKind,
    );
  }
}
