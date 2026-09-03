// Tests for the surviving AnkiNoteDao surface (doc 38 P1-B: the write side
// is deleted; the browser/fidelity read path stays). Seeding is raw drift
// SQL — the retired writer methods must not come back to power tests.

// Dart imports:
import 'dart:convert';

// Project imports:
import 'package:drift/drift.dart' show Variable;
import 'package:flutter_test/flutter_test.dart';
import 'package:turna/data/anki_import_dao.dart';
import 'package:turna/data/anki_note_dao.dart';
import 'package:turna/data/course_database.dart';

import '../helpers/in_memory_course_db.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  ensureSqliteLibForTestHost();

  late CourseDatabase db;
  late AnkiImportDao importDao;
  late AnkiNoteDao noteDao;

  // Raw SQL seeders: the parent import row and NoteStore rows must exist for
  // the read path, but the writer methods that used to create them are gone.
  Future<void> seedImport(String importId,
      {String hash = 'hash1', int importedAt = 1700000000}) {
    return db.customStatement(
      "INSERT INTO anki_imports (import_id, source_path, source_hash, "
      "imported_at) VALUES (?, '/tmp/x.apkg', ?, ?)",
      [importId, hash, importedAt],
    );
  }

  Future<void> seedNote(
    String importId,
    int noteId, {
    int mid = 1,
    String tags = '',
    List<String> fields = const ['front text', 'back text'],
    String sfld = 'front text',
  }) {
    return db.customStatement(
      'INSERT INTO anki_notes (import_id, note_id, mid, tags, fields_json, '
      'sfld) VALUES (?, ?, ?, ?, ?, ?)',
      [importId, noteId, mid, tags, jsonEncode(fields), sfld],
    );
  }

  Future<void> seedCard(
    String importId,
    int cardId,
    int noteId, {
    int ord = 0,
    int did = 1,
    String wordId = '',
  }) {
    return db.customStatement(
      'INSERT INTO anki_cards_meta (import_id, card_id, note_id, ord, did, '
      'word_id) VALUES (?, ?, ?, ?, ?, ?)',
      [importId, cardId, noteId, ord, did, wordId],
    );
  }

  Future<int> countOf(String table, String importId) async {
    final rows = await db.customSelect(
      'SELECT COUNT(*) AS n FROM $table WHERE import_id = ?',
      variables: [Variable.withString(importId)],
    ).get();
    return rows.first.read<int>('n');
  }

  setUp(() async {
    db = emptyInMemoryCourseDatabase();
    importDao = AnkiImportDao(db);
    noteDao = AnkiNoteDao(db);
    // Parent import row must exist first (FK anki_notetypes/notes/cards_meta
    // -> anki_imports).
    await seedImport('imp1');
  });

  test('findByHash returns the newest import when hashes are duplicated',
      () async {
    await seedImport('imp2', importedAt: 1800000000);

    final match = await importDao.findByHash('hash1');
    expect(match?.importId, 'imp2');
  });

  test('card state supports suspend, bury, mark, flag and browser filters',
      () async {
    await seedNote('imp1', 100);
    await seedCard('imp1', 200, 100, wordId: 'anki-imp1-c200');

    await noteDao.setCardState(
      'imp1',
      200,
      suspended: true,
      buriedUntil: DateTime.now().millisecondsSinceEpoch - 1,
      marked: true,
      flag: 3,
    );
    expect((await noteDao.searchNotes('imp1', 'front', marked: true)),
        hasLength(1));
    expect((await noteDao.searchNotes('imp1', 'front', flag: 2)), isEmpty);
    expect((await noteDao.searchNotes('imp1', 'front', suspended: true)),
        hasLength(1));
  });

  test('searchNotes treats % and _ in the query as literals, not wildcards',
      () async {
    // Note whose fields contain literal LIKE wildcard characters.
    await seedNote('imp1', 300,
        fields: const ['discount 50% off', 'a_b'], sfld: 'discount 50% off');
    await seedCard('imp1', 300, 300, wordId: 'anki-imp1-c300');
    // Decoy that would falsely match if %/_ stayed wildcards (50->500X,
    // a_b->aXb), and would be the only match if the escape were inert.
    await seedNote('imp1', 301,
        fields: const ['discount 500X off', 'aXb'], sfld: 'discount 500X off');
    await seedCard('imp1', 301, 301, wordId: 'anki-imp1-c301');

    // Literal '%' matches the 50% card only (not 500X); a bare wildcard '%'
    // would match both, and the old inert escape matched neither.
    expect(await noteDao.searchNotes('imp1', '50%'), hasLength(1));
    // Literal '_' matches the a_b card only (not aXb); a bare wildcard '_'
    // would match both.
    expect(await noteDao.searchNotes('imp1', 'a_b'), hasLength(1));
  });

  test('searchNotes paginates the filtered set without loss or duplicates',
      () async {
    // 10 cards ordered by noteId; the first 8 are suspended, so only cards
    // 9 and 10 survive the filter — and they sit at the END of the SQL
    // ordering. The old `(offset+limit)*4` window over unfiltered rows
    // fetched only the first 8 (all suspended) and returned an empty page.
    for (var i = 1; i <= 10; i++) {
      await seedNote('imp1', i, fields: ['front $i', 'back'], sfld: 'front $i');
      await seedCard('imp1', i, i, wordId: 'anki-imp1-c$i');
      if (i <= 8) {
        await noteDao.setCardState('imp1', i, suspended: true);
      }
    }

    final page1 =
        await noteDao.searchNotes('imp1', 'front', suspended: false, limit: 1);
    final page2 = await noteDao.searchNotes('imp1', 'front',
        suspended: false, limit: 1, offset: 1);
    final past = await noteDao.searchNotes('imp1', 'front',
        suspended: false, limit: 1, offset: 2);

    expect(page1.map((r) => r.card.cardId), [9]);
    expect(page2.map((r) => r.card.cardId), [10]);
    expect(past, isEmpty);

    // Without filters, offset+limit must page the full set exactly once.
    final all = <int>[];
    for (var offset = 0; offset < 12; offset += 4) {
      all.addAll((await noteDao.searchNotes('imp1', 'front',
              limit: 4, offset: offset))
          .map((r) => r.card.cardId));
    }
    expect(all, [for (var i = 1; i <= 10; i++) i]);
  });

  test('per-deck daily limits round-trip independently of generated rows',
      () async {
    await importDao.setDailyLimits('imp1', newLimit: 12, reviewLimit: 34);
    expect(await importDao.dailyNewLimitFor('imp1'), 12);
    expect(await importDao.dailyReviewLimitFor('imp1'), 34);
    await importDao.setDailyLimits('imp1');
    expect(await importDao.dailyNewLimitFor('imp1'), isNull);
    expect(await importDao.dailyReviewLimitFor('imp1'), isNull);
  });

  test('deleteByImport cascades across all three NoteStore tables', () async {
    await seedNote('imp1', 100);
    await seedCard('imp1', 200, 100, wordId: 'anki-imp1-c200');
    expect(await countOf('anki_notes', 'imp1'), 1);
    expect(await countOf('anki_cards_meta', 'imp1'), 1);

    await noteDao.deleteByImport('imp1');

    expect(await countOf('anki_notetypes', 'imp1'), 0);
    expect(await countOf('anki_notes', 'imp1'), 0);
    expect(await countOf('anki_cards_meta', 'imp1'), 0);
  });


}
