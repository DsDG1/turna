// Dart imports:
import 'dart:convert';

// Package imports:
import 'package:drift/drift.dart';
import 'package:injectable/injectable.dart';

// Project imports:
import 'package:turna/data/anki_legacy_write_fence.dart';
import 'package:turna/data/course_database.dart';
import 'package:flutter/foundation.dart' show debugPrint;

/// Data access object for leftover Legacy NoteStore tables
/// (`anki_notetypes`, `anki_notes`, `anki_cards_meta`, schema v9).
///
/// Official fidelity renders from the Official Collection. These tables are
/// a read-only compatibility surface for still-Legacy-owned sources
/// (browser search, uninstall). New Official-first imports do not write them.
/// Scheduling is not stored here.
///
/// Row types are the `*Row` classes (renamed via `@DataClassName` on each
/// table) to avoid colliding with the retired parser-era in-memory models.
@lazySingleton
class AnkiNoteDao {
  final CourseDatabase _db;

  AnkiNoteDao(this._db);

  Future<void> setCardState(
    String importId,
    int cardId, {
    bool? suspended,
    int? buriedUntil,
    bool? marked,
    int? flag,
  }) async {
    LegacyWriteFence.instance
        .assertAllowed(importId: importId, operation: 'setCardState');
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
    // State filters are pushed into SQL (they live on the joined
    // anki_cards_meta rows) so LIMIT/OFFSET paginate the *filtered* set.
    // The previous in-memory filter + `(offset+limit)*4` window silently
    // dropped/duplicated rows on later pages whenever the window guess was
    // wrong (cloze decks exceed 4 cards per note; offsets counted unfiltered
    // rows). The values below are typed ints/bools, never user text.
    if (flag != null) {
      joined.where(
        CustomExpression<bool>('anki_cards_meta.flag = ${flag.clamp(0, 4)}'),
      );
    }
    if (suspended != null) {
      joined.where(
        CustomExpression<bool>(
          'anki_cards_meta.suspended = ${suspended ? 1 : 0}',
        ),
      );
    }
    if (marked != null) {
      joined.where(
        CustomExpression<bool>('anki_cards_meta.marked = ${marked ? 1 : 0}'),
      );
    }
    joined
      ..orderBy([OrderingTerm.asc(_db.ankiNotes.noteId)])
      ..limit(limit, offset: offset);
    final rows = await joined.get();
    if (rows.isEmpty) return const <AnkiCardBrowserRecord>[];
    // Fetch user-facing state for every candidate card in one chunked query
    // instead of one _withState SELECT per row (N+1 -> 2 queries).
    final baseCards = [
      for (final row in rows)
        _toCardMetaRecord(row.readTable(_db.ankiCardsMeta)),
    ];
    final cards = await _applyStateBatch(importId, baseCards);
    return [
      for (var i = 0; i < rows.length; i++)
        AnkiCardBrowserRecord(
          note: _toNoteRecord(rows[i].readTable(_db.ankiNotes)),
          card: cards[i],
        ),
    ];
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
      } catch (suppressed) {
        debugPrint('[AnkiNoteDao] suppressed error: $suppressed');
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


  // ------------------------- delete (unload) ---------------------------

  /// Delete all NoteStore rows for an import. Called on deck unload to
  /// clean notetypes/notes/cards_meta plus the per-import derived tables
  /// (deck index, import issues, practice projections) — previously those
  /// three leaked a full row set on every uninstall. srs_states are cleaned
  /// separately by the `anki-<importId>-` prefix.
  Future<void> deleteByImport(String importId) async {
    LegacyWriteFence.instance
        .assertAllowed(importId: importId, operation: 'deleteByImport');
    await _db.transaction(() async {
      await (_db.delete(_db.ankiNotetypes)
            ..where((t) => t.importId.equals(importId)))
          .go();
      await (_db.delete(_db.ankiNotes)
            ..where((t) => t.importId.equals(importId)))
          .go();
      await (_db.delete(_db.ankiCardsMeta)
            ..where((t) => t.importId.equals(importId)))
          .go();
      await _db.customStatement(
        'DELETE FROM anki_decks WHERE import_id = ?',
        [importId],
      );
      await _db.customStatement(
        'DELETE FROM anki_import_issues WHERE import_id = ?',
        [importId],
      );
      await _db.customStatement(
        'DELETE FROM anki_practice_projections WHERE import_id = ?',
        [importId],
      );
    });
  }

  // --------------------------- row -> record ---------------------------

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
