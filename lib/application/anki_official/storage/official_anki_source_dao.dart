import 'package:sqlite3/sqlite3.dart';
import 'package:turna/application/anki_official/contract/official_anki_dto.dart';
import 'package:turna/application/anki_official/contract/official_anki_errors.dart';
import 'package:turna/application/anki_official/projection/official_anki_projection_paging.dart';
import 'package:turna/application/anki_official/storage/official_anki_database.dart';
import 'package:flutter/foundation.dart' show debugPrint;

export 'package:turna/application/anki_official/projection/official_anki_projection_paging.dart'
    show OfficialAnkiSourceCardPage;

class OfficialAnkiSourceRow {
  const OfficialAnkiSourceRow({
    required this.sourceId,
    required this.profileId,
    required this.sourceHash,
    required this.state,
    required this.displayName,
    this.chain = 'v1',
  });

  final String sourceId;
  final String profileId;
  final String sourceHash;
  final String state;
  final String displayName;

  /// 'v1' | 'v2' (catalog v13): which import chain wrote this source. The
  /// read path serves both generations; the flag only routes new imports.
  final String chain;

  bool get isV2 => chain == 'v2';
}

class OfficialAnkiSourceDao {
  OfficialAnkiSourceDao(this._database);

  final OfficialAnkiDatabase _database;
  OfficialAnkiDatabase get database => _database;
  Database get _db => _database.handle;

  OfficialAnkiSourceRow? findByHash(String profileId, String hash) {
    final rows = _db.select(
      'SELECT source_id, profile_id, source_hash, state, display_name, chain '
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
      chain: (row['chain'] as String?) ?? 'v1',
    );
  }

  OfficialAnkiSourceRow? findById(String sourceId) {
    final rows = _db.select(
      'SELECT source_id, profile_id, source_hash, state, display_name, chain '
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
      chain: (row['chain'] as String?) ?? 'v1',
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
      _db.execute(
          'DELETE FROM anki_source_cards WHERE source_id = ?', [sourceId]);
      final stmt = _db.prepare(
        'INSERT INTO anki_source_cards '
        '(source_id, card_id, note_id, deck_id, note_guid, template_ord, notetype_id) '
        'VALUES (?, ?, ?, ?, ?, ?, ?)',
      );
      for (final card in cards) {
        stmt.execute([
          sourceId,
          card.cardId,
          card.noteId,
          card.deckId,
          card.noteGuid,
          card.templateOrd,
          card.notetypeId,
        ]);
      }
      stmt.dispose();
      _db.execute('COMMIT');
    } catch (suppressed) {
      debugPrint('[OfficialAnkiSourceDao] suppressed error: $suppressed');
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
        '(source_id, card_id, note_id, deck_id, note_guid, template_ord, notetype_id) '
        'VALUES (?, ?, ?, ?, ?, ?, ?)',
      );
      for (final card in cards) {
        stmt.execute([
          sourceId,
          card.cardId,
          card.noteId,
          card.deckId,
          card.noteGuid,
          card.templateOrd,
          card.notetypeId,
        ]);
      }
      stmt.dispose();
      _db.execute('COMMIT');
    } catch (suppressed) {
      debugPrint('[OfficialAnkiSourceDao] suppressed error: $suppressed');
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
          'SELECT card_id, note_id, deck_id, note_guid, template_ord, notetype_id '
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
            notetypeId: (row['notetype_id'] as num?)?.toInt(),
          ),
        )
        .toList();
  }

  /// Ownership ids only (no descriptors). Used by v2 retire so a 100k
  /// source is not fully materialized before the first engine delete.
  List<int> listCardIdsPage(
    String sourceId, {
    required int offset,
    required int limit,
  }) {
    return [
      for (final row in _db.select(
        'SELECT card_id FROM anki_source_cards WHERE source_id = ? '
        'ORDER BY card_id LIMIT ? OFFSET ?',
        [sourceId, limit, offset],
      ))
        (row['card_id'] as num).toInt(),
    ];
  }

  /// Card ids associated with [sourceId] that are also associated with a
  /// sibling source. Source uninstall must retain these collection cards;
  /// the catalog's `(source_id, card_id)` key deliberately permits sharing.
  Set<int> sharedCardIds(String sourceId) {
    return retainingSharedCardIds(sourceId);
  }

  /// Sibling owners that still intend to keep the card. Retired / cancelled /
  /// pending_cleanup / rollback_pending sources do not protect it.
  Set<int> retainingSharedCardIds(String sourceId) {
    return _db
        .select(
          '''
SELECT DISTINCT mine.card_id FROM anki_source_cards mine
WHERE mine.source_id = ? AND EXISTS (
  SELECT 1 FROM anki_source_cards sibling
  JOIN anki_sources s ON s.source_id = sibling.source_id
  LEFT JOIN anki_import_attempts a ON a.attempt_id = s.active_attempt_id
  WHERE sibling.card_id = mine.card_id
    AND sibling.source_id <> mine.source_id
    AND (
      s.state IN ('active', 'repairing', 'selected', 'preview_ready',
                  'indexing_cards', 'indexing_notes', 'importing_official',
                  'preparing', 'backing_up')
      OR (s.state = 'staging' AND IFNULL(a.user_intent, 'undecided') <> 'discard')
    )
    AND s.state NOT IN (
      'retired', 'cancelled', 'failed_before_import', 'failed_after_import',
      'rollback_pending', 'pending_cleanup', 'quarantined', 'rolled_back'
    )
)
''',
          [sourceId],
        )
        .map((row) => (row['card_id'] as num).toInt())
        .toSet();
  }

  List<OfficialAnkiSourceRow> listSources(String profileId) {
    return _db
        .select(
          'SELECT source_id, profile_id, source_hash, state, display_name, chain '
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
            chain: (row['chain'] as String?) ?? 'v1',
          ),
        )
        .toList();
  }

  // ------------------------------------------------------------------
  // v2 chain (ADR 0043 D4/D6, step4.md B2/B5). The v2 path writes ONLY the
  // five ledger tables — these helpers never touch the other 13.
  // ------------------------------------------------------------------

  /// Marks a source as imported by the v2 chain. Idempotent.
  void markChainV2({required String sourceId, required int nowMillis}) {
    _db.execute(
      "UPDATE anki_sources SET chain = 'v2', updated_at_millis = ? "
      'WHERE source_id = ?',
      [nowMillis, sourceId],
    );
  }

  /// Sources on the v2 chain filtered by [states] (empty = all states).
  List<OfficialAnkiSourceRow> listV2Sources(
    String profileId, {
    Set<String> states = const {},
  }) {
    final rows = states.isEmpty
        ? _db.select(
            'SELECT source_id, profile_id, source_hash, state, display_name, chain '
            "FROM anki_sources WHERE profile_id = ? AND chain = 'v2' "
            'ORDER BY created_at_millis',
            [profileId],
          )
        : _db.select(
            'SELECT source_id, profile_id, source_hash, state, display_name, chain '
            "FROM anki_sources WHERE profile_id = ? AND chain = 'v2' "
            'AND state IN (${List.filled(states.length, '?').join(', ')}) '
            'ORDER BY created_at_millis',
            [profileId, ...states],
          );
    return rows
        .map(
          (row) => OfficialAnkiSourceRow(
            sourceId: row['source_id'] as String,
            profileId: row['profile_id'] as String,
            sourceHash: row['source_hash'] as String,
            state: row['state'] as String,
            displayName: row['display_name'] as String,
            chain: (row['chain'] as String?) ?? 'v1',
          ),
        )
        .toList();
  }

  /// Retiring entry point (D6 step ①): CAS active → retiring. The caller
  /// wraps this plus the delete-job enqueue in ONE catalog transaction so a
  /// kill between them is impossible.
  void markRetiring({required String sourceId, required int nowMillis}) {
    _db.execute(
      "UPDATE anki_sources SET state = 'retiring', updated_at_millis = ? "
      "WHERE source_id = ? AND state = 'active'",
      [nowMillis, sourceId],
    );
    if (_db.updatedRows != 1) {
      throw StateError('source $sourceId was not active');
    }
  }

  /// v2 final ledger delete (D6 step ③): touches only the three populated
  /// ledger tables of the five-table v2 set (jobs/leases are profile-wide).
  /// Idempotent: returns false when the source row is already gone.
  bool deleteSourceV2({required String sourceId}) {
    final existing = _db.select(
      'SELECT 1 FROM anki_sources WHERE source_id = ?',
      [sourceId],
    );
    if (existing.isEmpty) return false;
    _db.execute('BEGIN');
    try {
      _db.execute(
        'DELETE FROM anki_import_attempts WHERE source_id = ?',
        [sourceId],
      );
      _db.execute(
        'DELETE FROM anki_source_cards WHERE source_id = ?',
        [sourceId],
      );
      _db.execute('DELETE FROM anki_sources WHERE source_id = ?', [sourceId]);
      _db.execute('COMMIT');
    } catch (suppressed) {
      debugPrint('[OfficialAnkiSourceDao] suppressed error: $suppressed');
      _db.execute('ROLLBACK');
      rethrow;
    }
    return true;
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
    return deleteSourceV2(sourceId: sourceId);
  }
}
