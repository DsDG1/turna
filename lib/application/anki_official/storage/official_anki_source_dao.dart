import 'package:sqlite3/sqlite3.dart';
import 'package:turna/application/anki_official/contract/official_anki_dto.dart';
import 'package:turna/application/anki_official/contract/official_anki_errors.dart';
import 'package:turna/application/anki_official/projection/official_anki_projection_paging.dart';
import 'package:turna/application/anki_official/storage/official_anki_database.dart';

export 'package:turna/application/anki_official/projection/official_anki_projection_paging.dart'
    show OfficialAnkiSourceCardPage;

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

  OfficialAnkiSourceCardPage pageSourceCardIds({
    required String sourceId,
    int? afterCardId,
    int limit = officialAnkiProjectionPageDefault,
  }) {
    if (limit < 1 || limit > officialAnkiProjectionPageMax) {
      throw const OfficialAnkiException(
        code: OfficialAnkiErrorCode.invalidArgument,
        messageKey: 'official_anki.invalid_argument',
        debugDetails: 'page limit must be 1..500',
      );
    }
    final after = afterCardId ?? 0;
    final rows = _db.select(
      'SELECT card_id FROM anki_source_cards '
      'WHERE source_id = ? AND card_id > ? '
      'ORDER BY card_id LIMIT ?',
      [sourceId, after, limit],
    );
    final ids = <int>[];
    var previous = after;
    for (final row in rows) {
      final id = (row['card_id'] as num).toInt();
      if (id <= previous) {
        throw const OfficialAnkiException(
          code: OfficialAnkiErrorCode.projectionSourceChanged,
          messageKey: 'official_anki.projection_source_changed',
          recoverable: true,
          debugDetails: 'card_id not strictly ascending',
        );
      }
      ids.add(id);
      previous = id;
    }
    return OfficialAnkiSourceCardPage(
      cardIds: ids,
      lastCardId: ids.isEmpty ? afterCardId : ids.last,
      hasMore: ids.length == limit,
    );
  }

  int cardCount(String sourceId) {
    final row = _db.select(
      'SELECT COUNT(*) AS n FROM anki_source_cards WHERE source_id = ?',
      [sourceId],
    ).first;
    return row['n'] as int;
  }

  /// Deletion-saga state: the official collection could not be cleaned
  /// (engine unavailable or deleteNotes failed). Every catalog row —
  /// including the migration link that maps legacy ids to this source —
  /// must stay so the cleanup can resume once the engine recovers;
  /// deleting them first would orphan the collection notes.
  void markPendingCleanup({
    required String sourceId,
    required int nowMillis,
    String state = 'pending_cleanup',
    String errorCode = 'pending_cleanup',
    String errorMessage =
        'collection delete deferred; owner rows kept for retry',
  }) {
    _db.execute(
      'UPDATE anki_sources SET state = ?, updated_at_millis = ?, '
      'last_error_code = ?, last_error_safe_message = ? '
      'WHERE source_id = ?',
      [state, nowMillis, errorCode, errorMessage, sourceId],
    );
  }

  /// Cards for [sourceId], or the source with [sourceHash] if the id is empty
  /// or not yet visible on this connection after a worker import.
  List<OfficialAnkiCardDescriptor> listCardsForImport({
    required String sourceId,
    required String profileId,
    String? sourceHash,
  }) {
    final first = listCards(sourceId);
    if (first.isNotEmpty) return first;
    if (sourceHash == null || sourceHash.isEmpty) return first;
    final byHash = findByHash(profileId, sourceHash);
    if (byHash == null || byHash.sourceId == sourceId) return first;
    return listCards(byHash.sourceId);
  }

  List<OfficialAnkiCardDescriptor> listCards(String sourceId) {
    return _db
        .select(
          'SELECT card_id, note_id, deck_id, note_guid, template_ord '
          'FROM anki_source_cards WHERE source_id = ? ORDER BY card_id',
          [sourceId],
        )
        .map(
          (row) => OfficialAnkiCardDescriptor(
            cardId: (row['card_id'] as num).toInt(),
            noteId: (row['note_id'] as num).toInt(),
            deckId: (row['deck_id'] as num).toInt(),
            templateOrd: (row['template_ord'] as num).toInt(),
            noteGuid: row['note_guid'] as String?,
          ),
        )
        .toList();
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

  /// P5F-31: catalog bookkeeping for one source. Deletes every catalog row
  /// owned by the source in foreign-key-safe order. The caller (hard
  /// uninstall) removes the source's notes/cards from the official Anki
  /// collection first, then drops these rows. Projection mappings are
  /// profile-wide per notetype and stay.
  /// Returns true when the source row existed.
  bool deleteSource({
    required String profileId,
    required String sourceId,
  }) {
    final existing = _db.select(
      'SELECT 1 FROM anki_sources WHERE source_id = ? AND profile_id = ?',
      [sourceId, profileId],
    );
    if (existing.isEmpty) return false;
    _db.execute('BEGIN');
    try {
      _db.execute(
        'DELETE FROM legacy_anki_card_map WHERE migration_id IN '
        '(SELECT migration_id FROM legacy_anki_migrations '
        ' WHERE official_source_id = ?)',
        [sourceId],
      );
      _db.execute(
        'DELETE FROM legacy_anki_migrations WHERE official_source_id = ?',
        [sourceId],
      );
      _db.execute(
        'DELETE FROM anki_import_attempt_notes WHERE attempt_id IN '
        '(SELECT attempt_id FROM anki_import_attempts WHERE source_id = ?)',
        [sourceId],
      );
      _db.execute(
        'DELETE FROM anki_import_attempts WHERE source_id = ?',
        [sourceId],
      );
      _db.execute(
        'DELETE FROM anki_projection_jobs WHERE source_id = ?',
        [sourceId],
      );
      _db.execute(
        'DELETE FROM anki_course_placement_overrides WHERE source_id = ?',
        [sourceId],
      );
      _db.execute(
        'DELETE FROM anki_source_projection_state WHERE source_id = ?',
        [sourceId],
      );
      _db.execute(
        'DELETE FROM anki_source_cards WHERE source_id = ?',
        [sourceId],
      );
      _db.execute(
        'DELETE FROM anki_sources WHERE source_id = ? AND profile_id = ?',
        [sourceId, profileId],
      );
      _db.execute('COMMIT');
    } catch (_) {
      _db.execute('ROLLBACK');
      rethrow;
    }
    return true;
  }
}
