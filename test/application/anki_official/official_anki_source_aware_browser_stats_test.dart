import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:turna/application/anki_official/browser/official_anki_source_aware_browser.dart';
import 'package:turna/application/anki_official/engine/official_anki_engine_fake.dart';
import 'package:turna/application/anki_official/engine/official_anki_home_due.dart';
import 'package:turna/application/anki_official/migration/official_anki_engine_kind.dart';
import 'package:turna/application/anki_official/stats/official_anki_source_aware_stats.dart';
import 'package:turna/application/anki_official/storage/official_anki_database.dart';
import 'package:turna/application/anki_official/storage/official_anki_source_dao.dart';
import 'package:turna/data/anki_note_dao.dart';
import 'package:turna/data/course_database.dart';

void main() {
  test('pure Official source browser does not need Legacy NoteStore rows',
      () async {
    final catalog = OfficialAnkiDatabase.memory();
    addTearDown(catalog.close);
    final sources = OfficialAnkiSourceDao(catalog);
    sources.upsertSource(
      sourceId: 'src-official',
      profileId: 'profile-default-01',
      sourceHash: 'hash-o',
      sourceSize: 1,
      displayName: 'Official Only',
      state: 'active',
      backendCommit: 'x',
      nowMillis: 1,
    );
    catalog.handle.execute(
      'INSERT INTO anki_source_cards '
      '(source_id, card_id, note_id, deck_id, note_guid, template_ord) '
      "VALUES ('src-official', 11, 1, 1, 'guid-a', 0), "
      "('src-official', 12, 1, 1, 'guid-b', 0)",
    );

    // Legacy DB is empty — pure Official-first must still list cards.
    final courseDb = CourseDatabase(NativeDatabase.memory());
    addTearDown(courseDb.close);
    final legacy = AnkiNoteDao(courseDb);

    final browser = OfficialAnkiSourceAwareBrowser(
      sources: sources,
      legacyNotes: legacy,
    );
    final rows = await browser.search(
      importOrSourceId: 'src-official',
      ownerHint: AnkiEngineKind.official,
    );
    expect(rows, hasLength(2));
    expect(rows.every((r) => r.owner == AnkiEngineKind.official), isTrue);
    expect(rows.map((r) => r.cardId).toSet(), {11, 12});

    final filtered = await browser.search(
      importOrSourceId: 'src-official',
      query: '11',
      ownerHint: AnkiEngineKind.official,
    );
    expect(filtered.map((r) => r.cardId).toSet(), {11});
  });

  test('Official Collection search uses render text and suspend writes engine',
      () async {
    final catalog = OfficialAnkiDatabase.memory();
    addTearDown(catalog.close);
    OfficialAnkiHomeDue.reset();
    addTearDown(OfficialAnkiHomeDue.reset);
    final sources = OfficialAnkiSourceDao(catalog);
    sources.upsertSource(
      sourceId: 'src-official',
      profileId: 'profile-default-01',
      sourceHash: 'hash-o',
      sourceSize: 1,
      displayName: 'Official Only',
      state: 'active',
      backendCommit: 'x',
      nowMillis: 1,
    );
    catalog.handle.execute(
      'INSERT INTO anki_source_cards '
      '(source_id, card_id, note_id, deck_id, note_guid, template_ord) '
      "VALUES ('src-official', 1, 1, 1, 'guid-a', 0), "
      "('src-official', 2, 1, 1, 'guid-b', 0)",
    );
    final engine = FakeOfficialAnkiEngine();
    engine.seedPackage(packagePath: 'b.apkg', notes: 2, cards: 2);
    final courseDb = CourseDatabase(NativeDatabase.memory());
    addTearDown(courseDb.close);
    final browser = OfficialAnkiSourceAwareBrowser(
      sources: sources,
      legacyNotes: AnkiNoteDao(courseDb),
      engine: engine,
    );
    final rows = await browser.search(
      importOrSourceId: 'src-official',
      ownerHint: AnkiEngineKind.official,
    );
    expect(rows.map((r) => r.frontPreview).toSet(), {'Q1', 'Q2'});

    await browser.setOfficialSuspended(
      sourceId: 'src-official',
      cardId: 1,
      suspended: true,
    );
    expect(engine.suspended, contains(1));
    expect(
      OfficialAnkiHomeDue.suspendedCardIdsByImport['src-official'],
      contains(1),
    );
    final suspendedOnly = await browser.search(
      importOrSourceId: 'src-official',
      suspended: true,
      ownerHint: AnkiEngineKind.official,
    );
    expect(suspendedOnly.map((r) => r.cardId).toSet(), {1});
  });

  test('Official stats use catalog counts, not Turna FSRS retention', () async {
    final catalog = OfficialAnkiDatabase.memory();
    addTearDown(catalog.close);
    final sources = OfficialAnkiSourceDao(catalog);
    sources.upsertSource(
      sourceId: 'src-official',
      profileId: 'profile-default-01',
      sourceHash: 'hash-o',
      sourceSize: 1,
      displayName: 'Official Only',
      state: 'active',
      backendCommit: 'x',
      nowMillis: 1,
    );
    catalog.handle.execute(
      'INSERT INTO anki_source_cards '
      '(source_id, card_id, note_id, deck_id, note_guid, template_ord) '
      "VALUES ('src-official', 1, 1, 1, 'g', 0), "
      "('src-official', 2, 1, 1, 'g2', 0)",
    );

    final stats = OfficialAnkiSourceAwareStats(sources: sources);
    final snap = await stats.forOfficialSource('src-official');
    expect(snap.totalCards, 2);
    expect(snap.metricsProven, isFalse,
        reason: 'catalog inventory is not Official scheduler proof');
    expect(snap.note.contains('FSRS'), isFalse);
    expect(snap.owner, AnkiEngineKind.official);

    final engine = FakeOfficialAnkiEngine();
    engine.seedPackage(packagePath: 's.apkg', notes: 2, cards: 2);
    final withEngine = OfficialAnkiSourceAwareStats(
      sources: sources,
      engine: engine,
    );
    final proven = await withEngine.forOfficialSource('src-official');
    expect(proven.metricsProven, isTrue);
    expect(proven.newCount, isNotNull);
    expect(proven.reviewCount, isNotNull);

    final agg = stats.aggregateOfficial('profile-default-01');
    expect(agg.totalCards, 2);
    expect(agg.metricsProven, isFalse);
  });
}
