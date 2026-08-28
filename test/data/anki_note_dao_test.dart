// Tests for AnkiNoteDao: NoteStore CRUD + cascade delete (schema v9,
// deep-adaptation plan §3.2.1). Verifies notetypes (with templates + css +
// allowJs), raw note fields (HTML preserved, not stripped), and card meta
// (card-level wordId, decision 2) round-trip through the DAO, and that
// deleteByImport clears all three tables (deck uninstall cascade, 阶段 1d).

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

  setUp(() async {
    db = emptyInMemoryCourseDatabase();
    importDao = AnkiImportDao(db);
    noteDao = AnkiNoteDao(db);
    // Parent import row must exist first (FK anki_notetypes/notes/cards_meta
    // -> anki_imports).
    await importDao.upsert(const AnkiImportRecord(
      importId: 'imp1',
      sourcePath: '/tmp/x.apkg',
      sourceHash: 'hash1',
      importedAt: 1700000000,
    ));
  });

  test('notetype round-trips with templates + css + allowJs', () async {
    await noteDao.upsertNotetype(AnkiNotetypeRecord(
      importId: 'imp1',
      mid: 1,
      name: 'Basic',
      isCloze: false,
      fieldNames: const ['Front', 'Back'],
      templates: const [
        AnkiTemplate(
          name: 'Card 1',
          qfmt: '{{Front}}',
          afmt: '{{Front}}<hr id="answer">{{Back}}',
        ),
      ],
      css: '.card{font-size:20px}',
      allowJs: true,
    ));

    final nt = await noteDao.notetype('imp1', 1);
    expect(nt, isNotNull);
    expect(nt!.name, 'Basic');
    expect(nt.fieldNames, ['Front', 'Back']);
    expect(nt.templates, hasLength(1));
    expect(nt.templates.first.qfmt, '{{Front}}');
    expect(nt.templates.first.afmt, '{{Front}}<hr id="answer">{{Back}}');
    expect(nt.css, '.card{font-size:20px}');
    expect(nt.allowJs, isTrue);

    expect(await noteDao.notetypesFor('imp1'), hasLength(1));
    expect(await noteDao.notetype('imp1', 999), isNull);
  });

  test('canonical v2 stores deck diagnostics and reconciles counts', () async {
    await noteDao.upsertCardMeta(const AnkiCardMetaRecord(
      importId: 'imp1',
      cardId: 10,
      noteId: 20,
      did: 30,
      wordId: 'anki-imp1-c10',
    ));
    await noteDao.replaceDeckIndex('imp1', const [
      AnkiDeckIndexRecord(
        did: 30,
        name: 'Recovered deck 30',
        cardCount: 1,
        recovered: true,
      ),
    ]);
    await noteDao.replaceImportIssues('imp1', const [
      AnkiImportIssueRecord(
        severity: 'warning',
        code: 'DECK_METADATA_RECOVERED',
        entityType: 'deck',
        entityId: '30',
        message: 'Recovered missing deck metadata.',
      ),
    ]);
    await importDao.markComplete(
      'imp1',
      sourceCardCount: 1,
      indexedCardCount: 1,
      importedScheduling: false,
    );

    final record = await importDao.getById('imp1');
    expect(record!.status, 'complete');
    expect(record.sourceCardCount, 1);
    expect(record.storedCardCount, 1);
    expect(record.indexedCardCount, 1);
    final decks = await db.customSelect(
      'SELECT recovered FROM anki_decks WHERE import_id = ?',
      variables: [Variable.withString('imp1')],
    ).get();
    expect(decks.single.read<int>('recovered'), 1);
    final issues = await db.customSelect(
      'SELECT code FROM anki_import_issues WHERE import_id = ?',
      variables: [Variable.withString('imp1')],
    ).get();
    expect(issues.single.read<String>('code'), 'DECK_METADATA_RECOVERED');
  });

  test('count mismatch cannot be marked complete', () async {
    await expectLater(
      importDao.markComplete(
        'imp1',
        sourceCardCount: 1,
        indexedCardCount: 1,
        importedScheduling: false,
      ),
      throwsStateError,
    );
  });

  test('practice projection exposes per-card recognition evidence', () async {
    await noteDao.replacePracticeProjections('imp1', const [
      AnkiPracticeProjectionRecord(
        cardId: 10,
        kind: 'canonical',
        status: 'fallback',
        confidence: 1,
        evidence: {
          'mappingType': 'multipleChoice',
          'renderMode': 'structured',
        },
        sourceFingerprint: 'source-v1',
        updatedAt: 1700000000,
      ),
    ]);

    final projection = await noteDao.projectionForCard('imp1', 10);
    expect(projection, isNotNull);
    expect(projection!.kind, 'canonical');
    expect(projection.status, 'fallback');
    expect(projection.evidence['mappingType'], 'multipleChoice');
    expect(projection.sourceFingerprint, 'source-v1');
    expect(await noteDao.projectionForCard('imp1', 999), isNull);
  });

  test('findByHash returns the newest import when hashes are duplicated',
      () async {
    await importDao.upsert(const AnkiImportRecord(
      importId: 'imp2',
      sourcePath: '/tmp/x.apkg',
      sourceHash: 'hash1',
      importedAt: 1800000000,
    ));

    final match = await importDao.findByHash('hash1');
    expect(match?.importId, 'imp2');
  });

  test('note round-trips with raw HTML fields preserved (not stripped)',
      () async {
    await noteDao.upsertNote(AnkiNoteRecord(
      importId: 'imp1',
      noteId: 100,
      mid: 1,
      tags: 'vocab::greet',
      fields: const ['<b>merhaba</b>', 'hello'],
      sfld: 'merhaba',
    ));

    final n = await noteDao.note('imp1', 100);
    expect(n, isNotNull);
    expect(n!.tags, 'vocab::greet');
    // HTML is preserved verbatim - the fidelity track renders from these.
    expect(n.fields, ['<b>merhaba</b>', 'hello']);
    expect(n.sfld, 'merhaba');
  });

  test('card meta round-trips and resolves by wordId', () async {
    await noteDao.upsertCardMeta(AnkiCardMetaRecord(
      importId: 'imp1',
      cardId: 200,
      noteId: 100,
      ord: 0,
      did: 1,
      wordId: 'anki-imp1-c200',
      renderMode: 'fidelity',
    ));

    final cm = await noteDao.cardMeta('imp1', 200);
    expect(cm, isNotNull);
    expect(cm!.wordId, 'anki-imp1-c200');
    expect(cm.renderMode, 'fidelity');
    expect(cm.noteId, 100);

    final byWord = await noteDao.cardMetaByWordId('anki-imp1-c200');
    expect(byWord, isNotNull);
    expect(byWord!.cardId, 200);
  });

  test('wordIdsForDecks returns word ids for cards in the given decks only',
      () async {
    await noteDao.upsertCardMeta(const AnkiCardMetaRecord(
      importId: 'imp1',
      cardId: 1,
      noteId: 1,
      did: 10,
      wordId: 'w-1',
    ));
    await noteDao.upsertCardMeta(const AnkiCardMetaRecord(
      importId: 'imp1',
      cardId: 2,
      noteId: 2,
      did: 11,
      wordId: 'w-2',
    ));
    await noteDao.upsertCardMeta(const AnkiCardMetaRecord(
      importId: 'imp1',
      cardId: 3,
      noteId: 3,
      did: 99,
      wordId: 'w-3',
    ));

    final inSubtree = await noteDao.wordIdsForDecks('imp1', {10, 11});
    expect(inSubtree, {'w-1', 'w-2'});
    // Empty deck set short-circuits with no query.
    expect(await noteDao.wordIdsForDecks('imp1', const <int>{}), isEmpty);
  });

  test('card state supports suspend, bury, mark, flag and browser filters',
      () async {
    await noteDao.upsertNote(AnkiNoteRecord(
      importId: 'imp1',
      noteId: 100,
      mid: 1,
      fields: const ['front text', 'back text'],
      sfld: 'front text',
    ));
    await noteDao.upsertCardMeta(AnkiCardMetaRecord(
      importId: 'imp1',
      cardId: 200,
      noteId: 100,
      wordId: 'anki-imp1-c200',
    ));

    await noteDao.setCardState(
      'imp1',
      200,
      suspended: true,
      buriedUntil: DateTime.now().millisecondsSinceEpoch - 1,
      marked: true,
      flag: 3,
    );
    final state = await noteDao.cardMeta('imp1', 200);
    expect(state?.suspended, isTrue);
    expect(state?.buriedUntil, isNotNull);
    expect(state?.marked, isTrue);
    expect(state?.flag, 3);
    expect((await noteDao.searchNotes('imp1', 'front', marked: true)),
        hasLength(1));
    expect((await noteDao.searchNotes('imp1', 'front', flag: 2)), isEmpty);

    final expired = await noteDao.clearBuriedBefore(
      DateTime.now().millisecondsSinceEpoch,
    );
    expect(expired.map((r) => r.cardId), [200]);
    expect((await noteDao.cardMeta('imp1', 200))?.buriedUntil, isNull);
  });

  test('searchNotes treats % and _ in the query as literals, not wildcards',
      () async {
    // Note whose fields contain literal LIKE wildcard characters.
    await noteDao.upsertNote(AnkiNoteRecord(
      importId: 'imp1',
      noteId: 300,
      mid: 1,
      fields: const ['discount 50% off', 'a_b'],
      sfld: 'discount 50% off',
    ));
    await noteDao.upsertCardMeta(const AnkiCardMetaRecord(
      importId: 'imp1',
      cardId: 300,
      noteId: 300,
      wordId: 'anki-imp1-c300',
    ));
    // Decoy that would falsely match if %/_ stayed wildcards (50->500X,
    // a_b->aXb), and would be the only match if the escape were inert.
    await noteDao.upsertNote(AnkiNoteRecord(
      importId: 'imp1',
      noteId: 301,
      mid: 1,
      fields: const ['discount 500X off', 'aXb'],
      sfld: 'discount 500X off',
    ));
    await noteDao.upsertCardMeta(const AnkiCardMetaRecord(
      importId: 'imp1',
      cardId: 301,
      noteId: 301,
      wordId: 'anki-imp1-c301',
    ));

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
      await noteDao.upsertNote(AnkiNoteRecord(
        importId: 'imp1',
        noteId: i,
        mid: 1,
        fields: ['front $i', 'back'],
        sfld: 'front $i',
      ));
      await noteDao.upsertCardMeta(AnkiCardMetaRecord(
        importId: 'imp1',
        cardId: i,
        noteId: i,
        wordId: 'anki-imp1-c$i',
      ));
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
    await noteDao.upsertNotetype(
        AnkiNotetypeRecord(importId: 'imp1', mid: 1, name: 'Basic'));
    await noteDao
        .upsertNote(AnkiNoteRecord(importId: 'imp1', noteId: 100, mid: 1));
    await noteDao.upsertCardMeta(AnkiCardMetaRecord(
      importId: 'imp1',
      cardId: 200,
      noteId: 100,
      wordId: 'anki-imp1-c200',
    ));

    expect(await noteDao.notetypesFor('imp1'), hasLength(1));
    expect(await noteDao.note('imp1', 100), isNotNull);
    expect(await noteDao.cardMeta('imp1', 200), isNotNull);

    await noteDao.deleteByImport('imp1');

    expect(await noteDao.notetypesFor('imp1'), isEmpty);
    expect(await noteDao.note('imp1', 100), isNull);
    expect(await noteDao.cardMeta('imp1', 200), isNull);
  });

  test('deleteByImport also clears deck index, issues and projections',
      () async {
    await noteDao.upsertNote(AnkiNoteRecord(importId: 'imp1', noteId: 1, mid: 1));
    await noteDao.upsertCardMeta(const AnkiCardMetaRecord(
      importId: 'imp1',
      cardId: 2,
      noteId: 1,
      wordId: 'anki-imp1-c2',
    ));
    await noteDao.replaceDeckIndex('imp1', const [
      AnkiDeckIndexRecord(did: 7, name: 'Deck', cardCount: 1),
    ]);
    await noteDao.replaceImportIssues('imp1', const [
      AnkiImportIssueRecord(severity: 'warn', code: 'x', message: 'm'),
    ]);
    await noteDao.replacePracticeProjections('imp1', const [
      AnkiPracticeProjectionRecord(cardId: 2, kind: 'k', status: 'ok'),
    ]);

    await noteDao.deleteByImport('imp1');

    Future<int> countOf(String table) async {
      final rows = await db.customSelect(
        'SELECT COUNT(*) AS n FROM $table WHERE import_id = ?',
        variables: [Variable.withString('imp1')],
      ).get();
      return rows.first.read<int>('n');
    }

    expect(await countOf('anki_decks'), 0);
    expect(await countOf('anki_import_issues'), 0);
    expect(await countOf('anki_practice_projections'), 0);
  });
}
