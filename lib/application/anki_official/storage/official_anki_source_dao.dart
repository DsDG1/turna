import 'package:sqlite3/sqlite3.dart';
import 'package:turna/application/anki_official/contract/official_anki_dto.dart';
import 'package:turna/application/anki_official/storage/official_anki_database.dart';

class OfficialAnkiSourceRow {
  const OfficialAnkiSourceRow({
    required this.sourceId,
    required this.profileId,
    required this.sourceHash,
    required this.state,
    required this.displayName,
  });

  final String sourceId;
  final String profileId;
  final String sourceHash;
  final String state;
  final String displayName;
}

class OfficialAnkiSourceDao {
  OfficialAnkiSourceDao(this._database);

  final OfficialAnkiDatabase _database;
  Database get _db => _database.handle;

  OfficialAnkiSourceRow? findByHash(String profileId, String hash) {
    final rows = _db.select(
      'SELECT source_id, profile_id, source_hash, state, display_name '
      'FROM anki_sources WHERE profile_id = ? AND source_hash = ?',
      [profileId, hash],
    );
    if (rows.isEmpty) return null;
    final row = rows.first;
    return OfficialAnkiSourceRow(
      sourceId: row['source_id'] as String,
      profileId: row['profile_id'] as String,
      sourceHash: row['source_hash'] as String,
      state: row['state'] as String,
      displayName: row['display_name'] as String,
    );
  }

  OfficialAnkiSourceRow? findById(String sourceId) {
    final rows = _db.select(
      'SELECT source_id, profile_id, source_hash, state, display_name '
      'FROM anki_sources WHERE source_id = ?',
      [sourceId],
    );
    if (rows.isEmpty) return null;
    final row = rows.first;
    return OfficialAnkiSourceRow(
      sourceId: row['source_id'] as String,
      profileId: row['profile_id'] as String,
      sourceHash: row['source_hash'] as String,
      state: row['state'] as String,
      displayName: row['display_name'] as String,
    );
  }

  void upsertSource({
    required String sourceId,
    required String profileId,
    required String sourceHash,
    required int sourceSize,
    required String displayName,
    required String state,
    required String backendCommit,
    required int nowMillis,
    String importOptionsJson = '{}',
    String? originalUri,
    String? activeAttemptId,
  }) {
    _db.execute(
      '''
INSERT INTO anki_sources (
  source_id, profile_id, source_hash, source_size, display_name, original_uri,
  state, backend_commit, contract_major, contract_minor, import_options_json,
  active_attempt_id, created_at_millis, updated_at_millis
) VALUES (?, ?, ?, ?, ?, ?, ?, ?, 1, 0, ?, ?, ?, ?)
ON CONFLICT(source_id) DO UPDATE SET
  state = excluded.state,
  active_attempt_id = excluded.active_attempt_id,
  updated_at_millis = excluded.updated_at_millis
''',
      [
        sourceId,
        profileId,
        sourceHash,
        sourceSize,
        displayName,
        originalUri,
        state,
        backendCommit,
        importOptionsJson,
        activeAttemptId,
        nowMillis,
        nowMillis,
      ],
    );
  }

  void transitionSource({
    required String sourceId,
    required String expectedState,
    required String nextState,
    required int nowMillis,
    String? errorCode,
    String? errorMessage,
    int? importedAtMillis,
  }) {
    _db.execute(
      '''
UPDATE anki_sources
SET state = ?, updated_at_millis = ?, last_error_code = ?,
    last_error_safe_message = ?, imported_at_millis = COALESCE(?, imported_at_millis)
WHERE source_id = ? AND state = ?
''',
      [
        nextState,
        nowMillis,
        errorCode,
        errorMessage,
        importedAtMillis,
        sourceId,
        expectedState,
      ],
    );
    if (_db.updatedRows != 1) {
      throw StateError('source $sourceId was not in $expectedState');
    }
  }

  void replaceCards({
    required String sourceId,
    required List<OfficialAnkiCardDescriptor> cards,
  }) {
    _db.execute('BEGIN');
    try {
      _db.execute('DELETE FROM anki_source_cards WHERE source_id = ?', [sourceId]);
      final stmt = _db.prepare(
        'INSERT INTO anki_source_cards '
        '(source_id, card_id, note_id, deck_id, note_guid, template_ord) '
        'VALUES (?, ?, ?, ?, ?, ?)',
      );
      for (final card in cards) {
        stmt.execute([
          sourceId,
          card.cardId,
          card.noteId,
          card.deckId,
          card.noteGuid,
          card.templateOrd,
        ]);
      }
      stmt.dispose();
      _db.execute('COMMIT');
    } catch (_) {
      _db.execute('ROLLBACK');
      rethrow;
    }
  }

  void upsertCardBatch({
    required String sourceId,
    required List<OfficialAnkiCardDescriptor> cards,
  }) {
    _db.execute('BEGIN');
    try {
      final stmt = _db.prepare(
        'INSERT OR REPLACE INTO anki_source_cards '
        '(source_id, card_id, note_id, deck_id, note_guid, template_ord) '
        'VALUES (?, ?, ?, ?, ?, ?)',
      );
      for (final card in cards) {
        stmt.execute([
          sourceId,
          card.cardId,
          card.noteId,
          card.deckId,
          card.noteGuid,
          card.templateOrd,
        ]);
      }
      stmt.dispose();
      _db.execute('COMMIT');
    } catch (_) {
      _db.execute('ROLLBACK');
      rethrow;
    }
  }

  int cardCount(String sourceId) {
    final row = _db.select(
      'SELECT COUNT(*) AS n FROM anki_source_cards WHERE source_id = ?',
      [sourceId],
    ).first;
    return row['n'] as int;
  }

  List<OfficialAnkiSourceRow> listSources(String profileId) {
    return _db
        .select(
          'SELECT source_id, profile_id, source_hash, state, display_name '
          'FROM anki_sources WHERE profile_id = ?',
          [profileId],
        )
        .map(
          (row) => OfficialAnkiSourceRow(
            sourceId: row['source_id'] as String,
            profileId: row['profile_id'] as String,
            sourceHash: row['source_hash'] as String,
            state: row['state'] as String,
            displayName: row['display_name'] as String,
          ),
        )
        .toList();
  }
}
