import 'package:sqlite3/sqlite3.dart';
import 'package:turna/application/anki_official/contract/official_anki_dto.dart';
import 'package:turna/application/anki_official/storage/official_anki_database.dart';

class OfficialAnkiSourceMetadataDao {
  OfficialAnkiSourceMetadataDao(this._database);

  final OfficialAnkiDatabase _database;
  Database get _db => _database.handle;

  void replaceAssociations({
    required String sourceId,
    required List<OfficialAnkiCardDescriptor> cards,
    String schemaFingerprint = '',
  }) {
    final notetypeIds = <int>{};
    final deckIds = <int>{};
    for (final card in cards) {
      final notetypeId = card.notetypeId;
      if (notetypeId != null && notetypeId > 0) {
        notetypeIds.add(notetypeId);
      }
      if (card.deckId > 0) deckIds.add(card.deckId);
    }
    _db.execute('BEGIN');
    try {
      _db.execute(
        'DELETE FROM anki_source_notetypes WHERE source_id = ?',
        [sourceId],
      );
      _db.execute(
        'DELETE FROM anki_source_decks WHERE source_id = ?',
        [sourceId],
      );
      final nt = _db.prepare(
        'INSERT OR REPLACE INTO anki_source_notetypes '
        '(source_id, notetype_id, schema_fingerprint) VALUES (?, ?, ?)',
      );
      try {
        for (final id in notetypeIds) {
          nt.execute([sourceId, id, schemaFingerprint]);
        }
      } finally {
        nt.dispose();
      }
      final decks = _db.prepare(
        'INSERT OR REPLACE INTO anki_source_decks '
        '(source_id, deck_id) VALUES (?, ?)',
      );
      try {
        for (final id in deckIds) {
          decks.execute([sourceId, id]);
        }
      } finally {
        decks.dispose();
      }
      _db.execute('COMMIT');
    } catch (_) {
      _db.execute('ROLLBACK');
      rethrow;
    }
  }

  List<int> notetypeIds(String sourceId) {
    return _db
        .select(
          'SELECT notetype_id FROM anki_source_notetypes WHERE source_id = ?',
          [sourceId],
        )
        .map((row) => (row['notetype_id'] as num).toInt())
        .toList();
  }

  List<int> deckIds(String sourceId) {
    return _db
        .select(
          'SELECT deck_id FROM anki_source_decks WHERE source_id = ?',
          [sourceId],
        )
        .map((row) => (row['deck_id'] as num).toInt())
        .toList();
  }

  int mappingRefCount({
    required String profileId,
    required int notetypeId,
  }) {
    final row = _db.select(
      'SELECT COUNT(*) AS n FROM anki_source_notetypes n '
      'JOIN anki_sources s ON s.source_id = n.source_id '
      'WHERE n.notetype_id = ? AND s.profile_id = ?',
      [notetypeId, profileId],
    ).first;
    return row['n'] as int;
  }

  /// Drop profile mappings that no remaining source references and whose
  /// Collection use count is zero ([collectionUseCount] returns 0).
  int pruneOrphanMappings({
    required String profileId,
    required int Function(int notetypeId) collectionUseCount,
  }) {
    final rows = _db.select(
      'SELECT notetype_id FROM anki_projection_mappings WHERE profile_id = ?',
      [profileId],
    );
    var removed = 0;
    for (final row in rows) {
      final notetypeId = (row['notetype_id'] as num).toInt();
      if (mappingRefCount(profileId: profileId, notetypeId: notetypeId) > 0) {
        continue;
      }
      if (collectionUseCount(notetypeId) > 0) continue;
      _db.execute(
        'DELETE FROM anki_projection_mappings '
        'WHERE profile_id = ? AND notetype_id = ?',
        [profileId, notetypeId],
      );
      removed += _db.updatedRows;
    }
    return removed;
  }
}
