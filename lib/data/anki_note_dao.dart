// Dart imports:
import 'dart:convert';

// Package imports:
import 'package:drift/drift.dart';
import 'package:injectable/injectable.dart';

// Project imports:
import 'dart:io';

import 'package:turna/application/anki/anki_models.dart';
import 'package:turna/application/anki_official/migration/official_anki_engine_kind.dart';
import 'package:turna/application/anki_official/migration/official_anki_migration_dao.dart';
import 'package:turna/application/anki_official/migration/official_anki_migration_state.dart';
import 'package:turna/application/anki_official/migration/official_anki_write_owner.dart';
import 'package:turna/application/anki_official/official_anki_composition.dart';
import 'package:turna/application/anki_official/storage/official_anki_database.dart';
import 'package:turna/data/course_database.dart';

/// Data access object for the Anki NoteStore tables (`anki_notetypes`,
/// `anki_notes`, `anki_cards_meta`) added in schema v9.
///
/// Stores the source-of-truth notetype templates + css + raw note fields so
/// the fidelity track can re-render cards from the original Anki templates
/// without re-parsing the .apkg (deep-adaptation plan §3.2.1 / §5.1).
/// Scheduling state is NOT stored here - it lives in `srs_states` keyed by the
/// card-level `wordId` (`anki-<importId>-c<cardId>`, decision 2).
///
/// Row types are the `*Row` classes (renamed via `@DataClassName` on each
/// table) to avoid colliding with the in-memory [AnkiNotetype] / [AnkiNote]
/// models in `anki_models.dart`.
@lazySingleton
class AnkiNoteDao {
  final CourseDatabase _db;

  AnkiNoteDao(this._db);

  // ----------------------- deck index / diagnostics -----------------------

  Future<void> replaceDeckIndex(
    String importId,
    Iterable<AnkiDeckIndexRecord> records,
  ) async {
    await _db.customStatement(
      'DELETE FROM anki_decks WHERE import_id = ?',
      [importId],
    );
    for (final record in records) {
      await _db.customStatement('''
        INSERT INTO anki_decks
          (import_id, did, name, parent_did, card_count, recovered)
        VALUES (?, ?, ?, ?, ?, ?)
      ''', [
        importId,
        record.did,
        record.name,
        record.parentDid,
        record.cardCount,
        record.recovered ? 1 : 0,
      ]);
    }
  }

  Future<void> replaceImportIssues(
    String importId,
    Iterable<AnkiImportIssueRecord> issues,
  ) async {
    await _db.customStatement(
      'DELETE FROM anki_import_issues WHERE import_id = ?',
      [importId],
    );
    for (final issue in issues) {
      await _db.customStatement('''
        INSERT INTO anki_import_issues
          (import_id, severity, code, entity_type, entity_id, message,
           details_json, resolved)
        VALUES (?, ?, ?, ?, ?, ?, ?, ?)
      ''', [
        importId,
        issue.severity,
        issue.code,
        issue.entityType,
        issue.entityId,
        issue.message,
        jsonEncode(issue.details),
        issue.resolved ? 1 : 0,
      ]);
    }
  }

  Future<void> replacePracticeProjections(
    String importId,
    Iterable<AnkiPracticeProjectionRecord> projections,
  ) async {
    await _db.customStatement(
      'DELETE FROM anki_practice_projections WHERE import_id = ?',
      [importId],
    );
    for (final projection in projections) {
      await _db.customStatement('''
        INSERT INTO anki_practice_projections
          (import_id, card_id, kind, status, confidence, evidence_json,
           payload_json, source_fingerprint, updated_at)
        VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)
      ''', [
        importId,
        projection.cardId,
        projection.kind,
        projection.status,
        projection.confidence,
        jsonEncode(projection.evidence),
        jsonEncode(projection.payload),
        projection.sourceFingerprint,
        projection.updatedAt,
      ]);
    }
  }

  Future<Set<int>> deckIdsIncludingDescendants(
    String importId,
    int rootDid,
  ) async {
    final rows = await _db.customSelect(
      'SELECT did, parent_did FROM anki_decks WHERE import_id = ?',
      variables: [Variable.withString(importId)],
    ).get();
    final children = <int, List<int>>{};
    for (final row in rows) {
      final did = row.read<int>('did');
      final parent = row.read<int>('parent_did');
      children.putIfAbsent(parent, () => []).add(did);
    }
    final result = <int>{rootDid};
    final pending = <int>[rootDid];
    while (pending.isNotEmpty) {
      final parent = pending.removeLast();
      for (final child in children[parent] ?? const <int>[]) {
        if (result.add(child)) pending.add(child);
      }
    }
    return result;
  }

  // ----------------------------- notetypes -----------------------------

  /// Insert or update a notetype snapshot.
  Future<void> upsertNotetype(AnkiNotetypeRecord r) async {
    await _db.into(_db.ankiNotetypes).insertOnConflictUpdate(
          AnkiNotetypesCompanion.insert(
            importId: r.importId,
            mid: r.mid,
            name: Value(r.name),
            isCloze: Value(r.isCloze),
            fieldNamesJson: Value(jsonEncode(r.fieldNames)),
            templatesJson:
                Value(jsonEncode(r.templates.map((t) => t.toJson()).toList())),
            css: Value(r.css),
            allowJs: Value(r.allowJs),
          ),
        );
  }

  /// Get a single notetype by (importId, mid).
  Future<AnkiNotetypeRecord?> notetype(String importId, int mid) async {
    final row = await (_db.select(_db.ankiNotetypes)
          ..where((t) => t.importId.equals(importId) & t.mid.equals(mid)))
        .getSingleOrNull();
    return row == null ? null : _toNotetypeRecord(row);
  }

  /// All notetype snapshots for an import.
  Future<List<AnkiNotetypeRecord>> notetypesFor(String importId) async {
    final rows = await (_db.select(_db.ankiNotetypes)
          ..where((t) => t.importId.equals(importId)))
        .get();
    return rows.map(_toNotetypeRecord).toList();
  }

  // ------------------------------- notes -------------------------------

  /// Insert or update a raw note (fields kept as HTML).
  Future<void> upsertNote(AnkiNoteRecord r) async {
    await _db.into(_db.ankiNotes).insertOnConflictUpdate(
          AnkiNotesCompanion.insert(
            importId: r.importId,
            noteId: r.noteId,
            mid: r.mid,
            tags: Value(r.tags),
            fieldsJson: Value(jsonEncode(r.fields)),
            sfld: Value(r.sfld),
            guid: Value(r.guid),
            mod: Value(r.mod),
          ),
        );
  }

  /// Get a single note by (importId, noteId).
  Future<AnkiNoteRecord?> note(String importId, int noteId) async {
    final row = await (_db.select(_db.ankiNotes)
          ..where((t) => t.importId.equals(importId) & t.noteId.equals(noteId)))
        .getSingleOrNull();
    return row == null ? null : _toNoteRecord(row);
  }

  // ----------------------------- cards meta ----------------------------

  /// Insert or update a card-meta row.
  /// Insert or update a card-meta row.
  Future<void> upsertCardMeta(AnkiCardMetaRecord r) async {
    final existed = await _db.customSelect(
      'SELECT 1 FROM anki_cards_meta '
      'WHERE import_id = ? AND card_id = ? LIMIT 1',
      variables: [
        Variable.withString(r.importId),
        Variable.withInt(r.cardId),
      ],
    ).get();
    await _db.into(_db.ankiCardsMeta).insertOnConflictUpdate(
          AnkiCardsMetaCompanion.insert(
            importId: r.importId,
            cardId: r.cardId,
            noteId: r.noteId,
            ord: Value(r.ord),
            did: Value(r.did),
            wordId: r.wordId,
            renderMode: Value(r.renderMode),
            schedulingJson: Value(r.schedulingJson),
          ),
        );
    if (existed.isEmpty) {
      await setCardState(
        r.importId,
        r.cardId,
        suspended: r.suspended,
        buriedUntil: r.buriedUntil,
        marked: r.marked,
        flag: r.flag,
      );
    }
  }
  /// Get card meta by (importId, cardId).
  Future<AnkiCardMetaRecord?> cardMeta(String importId, int cardId) async {
    final row = await (_db.select(_db.ankiCardsMeta)
          ..where((t) => t.importId.equals(importId) & t.cardId.equals(cardId)))
        .getSingleOrNull();
    return row == null ? null : _withState(_toCardMetaRecord(row));
  }

  /// Look up card meta by its SRS `wordId` (`anki-<importId>-c<cardId>`).
  /// Used by the fidelity review path to resolve which note/template to render.
  Future<AnkiCardMetaRecord?> cardMetaByWordId(String wordId) async {
    final row = await (_db.select(_db.ankiCardsMeta)
          ..where((t) => t.wordId.equals(wordId)))
        .getSingleOrNull();
    return row == null ? null : _withState(_toCardMetaRecord(row));
  }

  /// Word ids of every card whose deck is in [deckIds] - a single batched
  /// query (chunked to stay under SQLite's variable limit) used to filter due
  /// candidates to a deck subtree without an N+1 `cardMetaByWordId` lookup per
  /// candidate. Cards with no word_id are skipped.
  Future<Set<String>> wordIdsForDecks(
    String importId,
    Iterable<int> deckIds,
  ) async {
    final deckList = deckIds.toList();
    if (deckList.isEmpty) return const <String>{};
    final result = <String>{};
    const chunkSize = 500;
    for (var i = 0; i < deckList.length; i += chunkSize) {
      final chunk = deckList.skip(i).take(chunkSize).toList();
      final placeholders = List.filled(chunk.length, '?').join(', ');
      final rows = await _db.customSelect(
        'SELECT word_id FROM anki_cards_meta '
        'WHERE import_id = ? AND did IN ($placeholders)',
        variables: [
          Variable.withString(importId),
          ...chunk.map(Variable.withInt),
        ],
      ).get();
      for (final row in rows) {
        final wordId = row.read<String?>('word_id');
        if (wordId != null && wordId.isNotEmpty) result.add(wordId);
      }
    }
    return result;
  }

  Future<void> setCardState(
    String importId,
    int cardId, {
    bool? suspended,
    int? buriedUntil,
    bool? marked,
    int? flag,
  }) async {
    _assertLegacyDaoWriteAllowed(importId);
    final updates = <String>[];
    final args = <Object?>[];
    if (suspended != null) {
      updates.add('suspended = ?');
      args.add(suspended ? 1 : 0);
    }
    if (buriedUntil != null) {
      updates.add('buried_until = ?');
      args.add(buriedUntil);
    }
    if (marked != null) {
      updates.add('marked = ?');
      args.add(marked ? 1 : 0);
    }
    if (flag != null) {
      updates.add('flag = ?');
      args.add(flag.clamp(0, 4));
    }
    if (updates.isEmpty) return;
    args
      ..add(importId)
      ..add(cardId);
    await _db.customStatement(
      'UPDATE anki_cards_meta SET ${updates.join(', ')} '
      'WHERE import_id = ? AND card_id = ?',
      args,
    );
  }

  void _assertLegacyDaoWriteAllowed(String importId) {
    try {
      final catalog = _resolveOfficialCatalogPath();
      if (catalog == null) return;
      final file = File(catalog);
      if (!file.existsSync()) return;
      final db = OfficialAnkiDatabase.file(file.path);
      try {
        final dao = OfficialAnkiMigrationDao(db);
        final row = dao.findByLegacyImport(
          profileId: 'profile-default-01',
          legacyImportId: importId,
        );
        if (row == null) return;
        const locked = {
          LegacyAnkiMigrationState.cutoverReady,
          LegacyAnkiMigrationState.cutover,
          LegacyAnkiMigrationState.observing,
          LegacyAnkiMigrationState.completed,
          LegacyAnkiMigrationState.noLegacyScheduleRollback,
        };
        if (!locked.contains(row.state)) return;
        const AnkiWriteGuard().assertAllowed(
          sourceEngine: AnkiEngineKind.official,
          owner: AnkiWriteOwner.legacyAnkiDao,
          operation: 'setCardState',
        );
      } finally {
        db.close();
      }
    } on AnkiWriteDenied {
      rethrow;
    } catch (_) {}
  }

  String? _resolveOfficialCatalogPath() {
    try {
      final paths = OfficialAnkiCompositionRoot.locatorPaths;
      return paths?.catalogFile.path;
    } catch (_) {
      return null;
    }
  }
  /// Clear expired buried cards and leave future buries untouched.
  /// Clear expired buried cards and leave future buries untouched.
  Future<List<AnkiCardMetaRecord>> clearBuriedBefore(int timestamp) async {
    final expired = await _db.customSelect(
      'SELECT import_id, card_id, note_id, ord, did, word_id, render_mode, '
      'scheduling_json, suspended, buried_until, marked, flag '
      'FROM anki_cards_meta '
      'WHERE buried_until IS NOT NULL AND buried_until <= ?',
      variables: [Variable.withInt(timestamp)],
    ).get();
    await _db.customStatement(
      'UPDATE anki_cards_meta SET buried_until = NULL '
      'WHERE buried_until IS NOT NULL AND buried_until <= ?',
      [timestamp],
    );
    return expired.map(_recordFromRaw).toList();
  }
  Future<List<AnkiCardMetaRecord>> flaggedCards(String importId,
      {int? flag}) async {
    final rows = await _db.customSelect(
      'SELECT import_id, card_id, note_id, ord, did, word_id, render_mode, '
      'scheduling_json, suspended, buried_until, marked, flag '
      'FROM anki_cards_meta '
      'WHERE import_id = ? '
      '${flag == null ? '' : 'AND flag = ?'} '
      'ORDER BY card_id',
      variables: flag == null
          ? [Variable.withString(importId)]
          : [Variable.withString(importId), Variable.withInt(flag.clamp(0, 4))],
    ).get();
    return rows.map(_recordFromRaw).toList();
  }
  /// Search raw note fields within one imported deck. The JSON column is
  /// intentionally searched as text; the browser strips HTML only for display.
  Future<List<AnkiCardBrowserRecord>> searchNotes(
    String importId,
    String query, {
    int? flag,
    bool? suspended,
    bool? marked,
    int limit = 50,
    int offset = 0,
  }) async {
    final joined = _db.select(_db.ankiNotes).join([
      innerJoin(
        _db.ankiCardsMeta,
        _db.ankiCardsMeta.importId.equalsExp(_db.ankiNotes.importId) &
            _db.ankiCardsMeta.noteId.equalsExp(_db.ankiNotes.noteId),
      ),
    ])
      ..where(_db.ankiNotes.importId.equals(importId));
    final trimmed = query.trim();
    if (trimmed.isNotEmpty) {
      // Escape LIKE wildcards so the user's query is matched literally. The
      // backslash is escaped first (it is the ESCAPE char), then `%` and `_`.
      // `_LikeWithEscape` emits `col LIKE ? ESCAPE '\'` with the pattern bound
      // as a SQL parameter (no injection risk) - drift's `like()` has no
      // escape support.
      final escaped = trimmed
          .replaceAll(r'\', r'\\')
          .replaceAll('%', r'\%')
          .replaceAll('_', r'\_');
      final like = '%$escaped%';
      Expression<bool> escapedLike(Expression<String> col) =>
          _LikeWithEscape(col, Variable.withString(like), r'\');
      joined.where(
        escapedLike(_db.ankiNotes.fieldsJson) |
            escapedLike(_db.ankiNotes.sfld) |
            escapedLike(_db.ankiNotes.tags),
      );
    }
    joined
      ..orderBy([OrderingTerm.asc(_db.ankiNotes.noteId)])
      ..limit((offset + limit) * 4);
    final rows = await joined.get();
    if (rows.isEmpty) return const <AnkiCardBrowserRecord>[];
    // Fetch user-facing state for every candidate card in one chunked query
    // instead of one _withState SELECT per row (N+1 -> 2 queries).
    final baseCards = [
      for (final row in rows) _toCardMetaRecord(row.readTable(_db.ankiCardsMeta)),
    ];
    final cards = await _applyStateBatch(importId, baseCards);
    final result = <AnkiCardBrowserRecord>[];
    for (var i = 0; i < rows.length; i++) {
      final card = cards[i];
      if (flag != null && card.flag != flag) continue;
      if (suspended != null && card.suspended != suspended) continue;
      if (marked != null && card.marked != marked) continue;
      result.add(AnkiCardBrowserRecord(
        note: _toNoteRecord(rows[i].readTable(_db.ankiNotes)),
        card: card,
      ));
    }
    return result.skip(offset).take(limit).toList();
  }

  /// Apply user-facing state (suspended/buried/marked/flag) to [records] in a
  /// single chunked query, instead of one [_withState] SELECT per row. All
  /// records must share [importId] (the card browser is single-import).
  Future<List<AnkiCardMetaRecord>> _applyStateBatch(
    String importId,
    List<AnkiCardMetaRecord> records,
  ) async {
    if (records.isEmpty) return records;
    final stateByCardId =
        <int, ({bool suspended, int? buriedUntil, bool marked, int flag})>{};
    final cardIds = records.map((r) => r.cardId).toSet().toList();
    const chunkSize = 500;
    for (var i = 0; i < cardIds.length; i += chunkSize) {
      final chunk = cardIds.skip(i).take(chunkSize).toList();
      final placeholders = List.filled(chunk.length, '?').join(', ');
      final rows = await _db.customSelect(
        'SELECT card_id, suspended, buried_until, marked, flag '
        'FROM anki_cards_meta '
        'WHERE import_id = ? AND card_id IN ($placeholders)',
        variables: [
          Variable.withString(importId),
          ...chunk.map(Variable.withInt),
        ],
      ).get();
      for (final row in rows) {
        stateByCardId[row.read<int>('card_id')] = (
          suspended: row.read<int>('suspended') == 1,
          buriedUntil: row.read<int?>('buried_until'),
          marked: row.read<int>('marked') == 1,
          flag: row.read<int>('flag'),
        );
      }
    }
    return [
      for (final r in records)
        stateByCardId.containsKey(r.cardId)
            ? r.copyWith(
                suspended: stateByCardId[r.cardId]!.suspended,
                buriedUntil: stateByCardId[r.cardId]!.buriedUntil,
                marked: stateByCardId[r.cardId]!.marked,
                flag: stateByCardId[r.cardId]!.flag,
              )
            : r,
    ];
  }

  /// Return the explainability record for a derived practice card. A null
  /// result means the card predates Canonical Store v2 or intentionally has
  /// no structured projection; the canonical Anki card remains authoritative.
  Future<AnkiPracticeProjectionRecord?> projectionForCard(
    String importId,
    int cardId,
  ) async {
    final rows = await _db.customSelect('''
      SELECT card_id, kind, status, confidence, evidence_json, payload_json,
             source_fingerprint, updated_at
      FROM anki_practice_projections
      WHERE import_id = ? AND card_id = ?
      LIMIT 1
    ''', variables: [
      Variable.withString(importId),
      Variable.withInt(cardId),
    ]).get();
    if (rows.isEmpty) return null;
    final row = rows.first;
    Map<String, Object?> decodeMap(String column) {
      try {
        final value = jsonDecode(row.read<String>(column));
        return value is Map
            ? Map<String, Object?>.from(value)
            : const <String, Object?>{};
      } catch (_) {
        return const <String, Object?>{};
      }
    }

    return AnkiPracticeProjectionRecord(
      cardId: row.read<int>('card_id'),
      kind: row.read<String>('kind'),
      status: row.read<String>('status'),
      confidence: row.read<double>('confidence'),
      evidence: decodeMap('evidence_json'),
      payload: decodeMap('payload_json'),
      sourceFingerprint: row.read<String>('source_fingerprint'),
      updatedAt: row.read<int>('updated_at'),
    );
  }

  // --------------------------- batch (import) --------------------------

  Future<void> upsertNotetypeBatch(List<AnkiNotetypeRecord> rows) async {
    if (rows.isEmpty) return;
    await _db.batch((b) {
      for (final r in rows) {
        b.insert(
          _db.ankiNotetypes,
          AnkiNotetypesCompanion.insert(
            importId: r.importId,
            mid: r.mid,
            name: Value(r.name),
            isCloze: Value(r.isCloze),
            fieldNamesJson: Value(jsonEncode(r.fieldNames)),
            templatesJson:
                Value(jsonEncode(r.templates.map((t) => t.toJson()).toList())),
            css: Value(r.css),
            allowJs: Value(r.allowJs),
          ),
          mode: InsertMode.insertOrReplace,
        );
      }
    });
  }

  Future<void> upsertNoteBatch(List<AnkiNoteRecord> rows) async {
    if (rows.isEmpty) return;
    await _db.batch((b) {
      for (final r in rows) {
        b.insert(
          _db.ankiNotes,
          AnkiNotesCompanion.insert(
            importId: r.importId,
            noteId: r.noteId,
            mid: r.mid,
            tags: Value(r.tags),
            fieldsJson: Value(jsonEncode(r.fields)),
            sfld: Value(r.sfld),
            guid: Value(r.guid),
            mod: Value(r.mod),
          ),
          mode: InsertMode.insertOrReplace,
        );
      }
    });
  }

  Future<void> upsertCardMetaBatch(List<AnkiCardMetaRecord> rows) async {
    if (rows.isEmpty) return;
    final existing = <String>{};
    final idsByImport = <String, Set<int>>{};
    for (final row in rows) {
      idsByImport.putIfAbsent(row.importId, () => <int>{}).add(row.cardId);
    }
    // Probe existing cards in chunks with bound parameters (avoids a single
    // multi-thousand-element literal IN list).
    const chunkSize = 500;
    for (final entry in idsByImport.entries) {
      final ids = entry.value.toList();
      for (var i = 0; i < ids.length; i += chunkSize) {
        final chunk = ids.skip(i).take(chunkSize).toList();
        final placeholders = List.filled(chunk.length, '?').join(', ');
        final found = await _db.customSelect(
          'SELECT card_id FROM anki_cards_meta '
          'WHERE import_id = ? AND card_id IN ($placeholders)',
          variables: [
            Variable.withString(entry.key),
            ...chunk.map(Variable.withInt),
          ],
        ).get();
        existing.addAll(
          found.map((row) => '${entry.key}:${row.read<int>('card_id')}'),
        );
      }
    }
    await _db.batch((b) {
      for (final r in rows) {
        final companion = AnkiCardsMetaCompanion.insert(
          importId: r.importId,
          cardId: r.cardId,
          noteId: r.noteId,
          ord: Value(r.ord),
          did: Value(r.did),
          wordId: r.wordId,
          renderMode: Value(r.renderMode),
          schedulingJson: Value(r.schedulingJson),
        );
        b.insert(
          _db.ankiCardsMeta,
          companion,
          onConflict: DoUpdate((_) => companion),
        );
      }
      // Apply user-facing state for newly-inserted cards inside the same batch
      // (one transaction, bound parameters) instead of N sequential setCardState
      // round-trips that each auto-commit.
      for (final r in rows) {
        if (existing.contains('${r.importId}:${r.cardId}')) continue;
        b.customStatement(
          'UPDATE anki_cards_meta SET suspended = ?, buried_until = ?, '
          'marked = ?, flag = ? WHERE import_id = ? AND card_id = ?',
          [
            r.suspended ? 1 : 0,
            r.buriedUntil,
            r.marked ? 1 : 0,
            r.flag.clamp(0, 4),
            r.importId,
            r.cardId,
          ],
        );
      }
    });
  }
  // ------------------------- delete (unload) ---------------------------

  /// Delete all NoteStore rows for an import. Called on deck unload to
  /// cascade-clean notetypes/notes/cards_meta (srs_states are cleaned
  /// separately by the `anki-<importId>-` prefix).
  Future<void> deleteByImport(String importId) async {
    await (_db.delete(_db.ankiNotetypes)
          ..where((t) => t.importId.equals(importId)))
        .go();
    await (_db.delete(_db.ankiNotes)..where((t) => t.importId.equals(importId)))
        .go();
    await (_db.delete(_db.ankiCardsMeta)
          ..where((t) => t.importId.equals(importId)))
        .go();
  }

  // --------------------- prerendered cache ----------------------------
  // "智能去解密": JS-fidelity cards are decrypted once in the WebView on first
  // review; the captured plain HTML is cached here so later reviews need no
  // JS / network / sandbox (deep-adaptation plan §6).

  /// Cache the decrypted HTML for one face of a JS-fidelity card. Either
  /// [front] or [back] is set per capture; the row is upserted so the two
  /// faces accumulate across the front-then-back review flow.
  Future<void> upsertPrerenderedFace(
    String wordId, {
    String? front,
    String? back,
  }) async {
    // Atomic upsert: only the captured face is written (Value.absent for the
    // other), so concurrent front/back captures can't clobber each other via a
    // stale read-then-write. On conflict the uncaptured column is left as-is.
    await _db.into(_db.ankiPrerenderedHtml).insertOnConflictUpdate(
          AnkiPrerenderedHtmlCompanion.insert(
            wordId: wordId,
            frontHtml: front == null
                ? const Value<String?>.absent()
                : Value<String?>(front),
            backHtml: back == null
                ? const Value<String?>.absent()
                : Value<String?>(back),
            capturedAt: Value(DateTime.now().millisecondsSinceEpoch),
          ),
        );
  }

  /// Read the cached decrypted HTML for a card (null if not yet captured).
  Future<AnkiPrerenderedHtmlRecord?> prerendered(String wordId) async {
    final row = await (_db.select(_db.ankiPrerenderedHtml)
          ..where((t) => t.wordId.equals(wordId)))
        .getSingleOrNull();
    return row == null
        ? null
        : AnkiPrerenderedHtmlRecord(
            wordId: row.wordId,
            frontHtml: row.frontHtml,
            backHtml: row.backHtml,
          );
  }

  /// Delete cached pre-rendered HTML for an import (deck unload). [prefix] is
  /// the `anki-<importId>-` wordId prefix.
  Future<void> deletePrerenderedByPrefix(String prefix) async {
    await (_db.delete(_db.ankiPrerenderedHtml)
          ..where((t) => t.wordId.like('$prefix%')))
        .go();
  }

  // --------------------------- row -> record ---------------------------

  AnkiNotetypeRecord _toNotetypeRecord(AnkiNotetypeRow row) {
    return AnkiNotetypeRecord(
      importId: row.importId,
      mid: row.mid,
      name: row.name,
      isCloze: row.isCloze,
      fieldNames: (jsonDecode(row.fieldNamesJson) as List)
          .map((e) => e.toString())
          .toList(),
      templates: (jsonDecode(row.templatesJson) as List)
          .map((e) => AnkiTemplate.fromJson(e as Map<String, dynamic>))
          .toList(),
      css: row.css,
      allowJs: row.allowJs,
    );
  }

  AnkiNoteRecord _toNoteRecord(AnkiNoteRow row) {
    return AnkiNoteRecord(
      importId: row.importId,
      noteId: row.noteId,
      mid: row.mid,
      tags: row.tags,
      fields: (jsonDecode(row.fieldsJson) as List)
          .map((e) => e.toString())
          .toList(),
      sfld: row.sfld,
      guid: row.guid,
      mod: row.mod,
    );
  }

  AnkiCardMetaRecord _toCardMetaRecord(AnkiCardMetaRow row) {
    return AnkiCardMetaRecord(
      importId: row.importId,
      cardId: row.cardId,
      noteId: row.noteId,
      ord: row.ord,
      did: row.did,
      wordId: row.wordId,
      renderMode: row.renderMode,
      schedulingJson: row.schedulingJson,
    );
  }

  Future<AnkiCardMetaRecord> _withState(AnkiCardMetaRecord record) async {
    final rows = await _db.customSelect(
      'SELECT suspended, buried_until, marked, flag '
      'FROM anki_cards_meta '
      'WHERE import_id = ? AND card_id = ?',
      variables: [
        Variable.withString(record.importId),
        Variable.withInt(record.cardId),
      ],
    ).get();
    if (rows.isEmpty) return record;
    final row = rows.first;
    return record.copyWith(
      suspended: row.read<int>('suspended') == 1,
      buriedUntil: row.read<int?>('buried_until'),
      marked: row.read<int>('marked') == 1,
      flag: row.read<int>('flag'),
    );
  }
  AnkiCardMetaRecord _recordFromRaw(dynamic row) {
    return AnkiCardMetaRecord(
      importId: row.read<String>('import_id'),
      cardId: row.read<int>('card_id'),
      noteId: row.read<int>('note_id'),
      ord: row.read<int>('ord'),
      did: row.read<int>('did'),
      wordId: row.read<String>('word_id'),
      renderMode: row.read<String>('render_mode'),
      schedulingJson: row.read<String>('scheduling_json'),
      suspended: row.read<int>('suspended') == 1,
      buriedUntil: row.read<int?>('buried_until'),
      marked: row.read<int>('marked') == 1,
      flag: row.read<int>('flag'),
    );
  }

}

/// `col LIKE ? ESCAPE '\'` - drift's [Expression.like] has no escape support,
/// so this emits the ESCAPE clause manually. The pattern is bound as a SQL
/// variable (no injection risk); the escape character is a constant.
class _LikeWithEscape extends Expression<bool> {
  _LikeWithEscape(this.target, this.pattern, this.escape);

  final Expression<String> target;
  final Variable<String> pattern;
  final String escape;

  @override
  Precedence get precedence => Precedence.comparisonEq;

  @override
  void writeInto(GenerationContext context) {
    writeInner(context, target);
    context.buffer.write(' LIKE ');
    writeInner(context, pattern);
    context.buffer.write(" ESCAPE '");
    context.buffer.write(escape);
    context.buffer.write("'");
  }

  @override
  int get hashCode => Object.hash(target, pattern, escape);

  @override
  bool operator ==(Object other) =>
      other is _LikeWithEscape &&
      other.target == target &&
      other.pattern == pattern &&
      other.escape == escape;
}

class AnkiDeckIndexRecord {
  final int did;
  final String name;
  final int parentDid;
  final int cardCount;
  final bool recovered;

  const AnkiDeckIndexRecord({
    required this.did,
    required this.name,
    this.parentDid = 0,
    this.cardCount = 0,
    this.recovered = false,
  });
}

class AnkiImportIssueRecord {
  final String severity;
  final String code;
  final String entityType;
  final String entityId;
  final String message;
  final Map<String, Object?> details;
  final bool resolved;

  const AnkiImportIssueRecord({
    required this.severity,
    required this.code,
    this.entityType = '',
    this.entityId = '',
    required this.message,
    this.details = const {},
    this.resolved = false,
  });
}

class AnkiPracticeProjectionRecord {
  final int cardId;
  final String kind;
  final String status;
  final double confidence;
  final Map<String, Object?> evidence;
  final Map<String, Object?> payload;
  final String sourceFingerprint;
  final int updatedAt;

  const AnkiPracticeProjectionRecord({
    required this.cardId,
    required this.kind,
    required this.status,
    this.confidence = 0,
    this.evidence = const {},
    this.payload = const {},
    this.sourceFingerprint = '',
    this.updatedAt = 0,
  });
}

/// Plain data class for an Anki notetype row (decoupled from the Drift row).
class AnkiNotetypeRecord {
  final String importId;
  final int mid;
  final String name;
  final bool isCloze;
  final List<String> fieldNames;
  final List<AnkiTemplate> templates;
  final String css;
  final bool allowJs;

  const AnkiNotetypeRecord({
    required this.importId,
    required this.mid,
    this.name = '',
    this.isCloze = false,
    this.fieldNames = const [],
    this.templates = const [],
    this.css = '',
    this.allowJs = false,
  });
}

/// Plain data class for an Anki note row (decoupled from the Drift row).
class AnkiNoteRecord {
  final String importId;
  final int noteId;
  final int mid;
  final String tags;
  final List<String> fields;
  final String sfld;
  final String guid;
  final int mod;

  const AnkiNoteRecord({
    required this.importId,
    required this.noteId,
    required this.mid,
    this.tags = '',
    this.fields = const [],
    this.sfld = '',
    this.guid = '',
    this.mod = 0,
  });
}

/// Plain data class for an Anki card-meta row (decoupled from the Drift row).
class AnkiCardMetaRecord {
  final String importId;
  final int cardId;
  final int noteId;
  final int ord;
  final int did;
  final String wordId;
  final String renderMode;
  final String schedulingJson;
  final bool suspended;
  final int? buriedUntil;
  final bool marked;
  final int flag;

  const AnkiCardMetaRecord({
    required this.importId,
    required this.cardId,
    required this.noteId,
    this.ord = 0,
    this.did = 0,
    required this.wordId,
    this.renderMode = 'hybrid',
    this.schedulingJson = '{}',
    this.suspended = false,
    this.buriedUntil,
    this.marked = false,
    this.flag = 0,
  });

  AnkiCardMetaRecord copyWith({
    bool? suspended,
    int? buriedUntil,
    bool? marked,
    int? flag,
  }) {
    return AnkiCardMetaRecord(
      importId: importId,
      cardId: cardId,
      noteId: noteId,
      ord: ord,
      did: did,
      wordId: wordId,
      renderMode: renderMode,
      schedulingJson: schedulingJson,
      suspended: suspended ?? this.suspended,
      buriedUntil: buriedUntil ?? this.buriedUntil,
      marked: marked ?? this.marked,
      flag: flag ?? this.flag,
    );
  }
}

class AnkiCardBrowserRecord {
  final AnkiNoteRecord note;
  final AnkiCardMetaRecord card;

  const AnkiCardBrowserRecord({required this.note, required this.card});
}

/// Plain data class for a cached pre-rendered (decrypted) HTML row.
class AnkiPrerenderedHtmlRecord {
  final String wordId;
  final String? frontHtml;
  final String? backHtml;

  const AnkiPrerenderedHtmlRecord({
    required this.wordId,
    this.frontHtml,
    this.backHtml,
  });

  /// True once both faces have been captured (front on first view, back on
  /// reveal) - the card can then be reviewed with JS disabled.
  bool get isComplete =>
      (frontHtml?.isNotEmpty ?? false) && (backHtml?.isNotEmpty ?? false);
}
